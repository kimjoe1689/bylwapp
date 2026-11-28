import 'package:bylwapp/ble/bytes.dart';

/// QRing / Yawell / Colmi plaintext framing.
///
/// Layout follows Gadgetbridge's yawell ring support
/// (service/devices/yawell/ring): 16-byte commands whose last byte is the
/// sum of the preceding payload, and big-data v2 frames with CRC-16/MODBUS.
class RingPacket {
  const RingPacket._();

  static const int cmdSetDateTime = 0x01;
  static const int cmdBattery = 0x03;
  static const int cmdPowerOff = 0x08;
  static const int cmdFind = 0x10;
  static const int cmdSyncHeartRate = 0x15;
  static const int cmdAutoHeartRate = 0x16;
  static const int cmdRealtimeHeartRate = 0x1e;
  static const int cmdAutoSpo2 = 0x2c;
  static const int cmdAutoStress = 0x36;
  static const int cmdAutoTempPref = 0x3a;
  static const int cmdSyncStress = 0x37;
  static const int cmdSyncHrv = 0x39;
  static const int cmdSyncActivity = 0x43;
  static const int cmdTodaySummary = 0x48;
  static const int cmdManualHeartRate = 0x69;
  static const int cmdStopHeartRate = 0x6a;
  static const int cmdFactoryReset = 0xff;
  static const int cmdNotification = 0x73;
  static const int cmdBigDataV2 = 0xbc;

  static const int notificationLiveActivity = 0x12;
  static const int prefWrite = 0x02;

  static const int bigDataTemperature = 0x25;
  static const int bigDataSleep = 0x27;
  static const int bigDataSpo2 = 0x2a;

  static const int sleepLight = 0x02;
  static const int sleepDeep = 0x03;
  static const int sleepRem = 0x04;
  static const int sleepAwake = 0x05;

  /// Builds a 16-byte command. The checksum covers [contents] only; padding is zero.
  static List<int> build(List<int> contents) {
    if (contents.length > 15) {
      throw ArgumentError('ring packet content is longer than 15 bytes');
    }
    final packet = List<int>.filled(16, 0);
    var sum = 0;
    for (var i = 0; i < contents.length; i++) {
      final byte = contents[i] & 0xff;
      packet[i] = byte;
      sum = (sum + byte) & 0xff;
    }
    packet[15] = sum;
    return packet;
  }

  static bool checksumValid(List<int> packet) {
    if (packet.length != 16) {
      return false;
    }
    var sum = 0;
    for (var i = 0; i < 15; i++) {
      sum = (sum + (packet[i] & 0xff)) & 0xff;
    }
    return sum == (packet[15] & 0xff);
  }

  /// CRC-16/MODBUS: poly 0xA001, init 0xFFFF, no final xor.
  static int crc16Modbus(List<int> data) {
    var crc = 0xffff;
    for (final value in data) {
      crc ^= value & 0xff;
      for (var i = 0; i < 8; i++) {
        if ((crc & 1) != 0) {
          crc = (crc >>> 1) ^ 0xa001;
        } else {
          crc >>>= 1;
        }
      }
    }
    return crc & 0xffff;
  }

  static List<int> buildBigData({
    required int type,
    required List<int> payload,
  }) {
    final crc = crc16Modbus(payload);
    return [
      cmdBigDataV2,
      type & 0xff,
      payload.length & 0xff,
      (payload.length >> 8) & 0xff,
      crc & 0xff,
      (crc >> 8) & 0xff,
      ...payload,
    ];
  }

  /// Colmi/QRing stores the phone's local wall clock as BCD, not UTC.
  static List<int> encodeDateTime(DateTime time) {
    final wall = time.toLocal();
    return build([
      cmdSetDateTime,
      _decimalAsHex(wall.year % 100),
      _decimalAsHex(wall.month),
      _decimalAsHex(wall.day),
      _decimalAsHex(wall.hour),
      _decimalAsHex(wall.minute),
      _decimalAsHex(wall.second),
    ]);
  }

  static List<int> batteryRequest() => build(const [cmdBattery]);

  /// Starts a manual/realtime heart-rate session: 0x69 0x01 0x01.
  static List<int> startRealtimeHeartRate() =>
      build(const [cmdManualHeartRate, 0x01, 0x01]);

  /// Keep-alive. Gadgetbridge repeats 0x1e while the session is open.
  static List<int> continueRealtimeHeartRate() =>
      build(const [cmdRealtimeHeartRate]);

  static List<int> stopRealtimeHeartRate() => build(const [cmdStopHeartRate]);

  static List<int> findRing() => build(const [cmdFind, 0x01]);

  static List<int> powerOff() => build(const [cmdPowerOff]);

  static List<int> factoryReset() => build(const [cmdFactoryReset]);

  static List<int> todaySummary() => build(const [cmdTodaySummary]);

  static List<int> readAuto(int command) => build([command & 0xff]);

  /// Write preference: subcommand 0x02, enabled, interval minutes.
  static List<int> writeAuto(
    int command, {
    required bool enabled,
    required int minutes,
  }) {
    return build([
      command & 0xff,
      prefWrite,
      enabled ? 0x01 : 0x00,
      minutes < 1 ? 1 : (minutes > 240 ? 240 : minutes),
    ]);
  }

  /// Turns temperature logging on or off. R09 and R05 only; history stays empty until this is on.
  static List<int> temperatureLogging({required bool enabled}) {
    return build([cmdAutoTempPref, 0x03, prefWrite, enabled ? 0x01 : 0x00]);
  }
}

int? bcdByte(int byte) {
  final hi = (byte >> 4) & 0x0f;
  final lo = byte & 0x0f;
  if (hi > 9 || lo > 9) {
    return null;
  }
  return hi * 10 + lo;
}

int _decimalAsHex(int value) {
  if (value < 0 || value > 99) {
    throw FormatException('cannot encode $value as a decimal byte');
  }
  return ((value ~/ 10) << 4) | (value % 10);
}

/// Reassembles notify-v2 frames the way Gadgetbridge concatenates them.
class BigDataAssembler {
  List<int>? _buffer;
  int? _payloadLength;

  void reset() {
    _buffer = null;
    _payloadLength = null;
  }

  /// Returns a complete frame, or null while more chunks are required.
  List<int>? add(List<int> chunk) {
    if (_buffer != null) {
      final combined = [..._buffer!, ...chunk];
      if (combined.length < _payloadLength! + 6) {
        _buffer = combined;
        return null;
      }
      reset();
      return combined;
    }
    if (chunk.length < 4 || (chunk[0] & 0xff) != RingPacket.cmdBigDataV2) {
      return chunk;
    }
    final length = u16le(chunk, 2);
    if (chunk.length < length + 6) {
      _payloadLength = length;
      _buffer = List<int>.from(chunk);
      return null;
    }
    return chunk;
  }
}
