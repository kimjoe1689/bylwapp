import 'package:bylwapp/ble/bytes.dart';
import 'package:bylwapp/ble/ring/ring_packet.dart';
import 'package:bylwapp/ble/ring/ring_parser.dart';
import 'package:bylwapp/ble/uuids.dart';
import 'package:bylwapp/models/health_record.dart';

enum RingSyncPhase {
  activity,
  heartRate,
  stress,
  spo2,
  sleep,
  hrv,
  temperature,
  done,
}

class RingCommand {
  const RingCommand({
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.bytes,
    required this.label,
  });

  final String serviceUuid;
  final String characteristicUuid;
  final List<int> bytes;
  final String label;
}

/// Request/response history sync for a QRing-family ring.
///
/// The sequence matches Gadgetbridge: activity and heart rate for eight days,
/// then stress, SpO2, sleep, HRV, and temperature when the model supports it.
/// Temperature logging is written first on R09/R05; samples only appear after
/// the ring has actually recorded with that setting enabled.
class RingSyncCursor {
  RingSyncCursor({
    required DateTime now,
    required this.temperatureCapable,
    this.temperatureLoggingEnabled = false,
    this.maxDaysAgo = 1,
  }) : now = now,
       today = DateTime(
         now.toLocal().year,
         now.toLocal().month,
         now.toLocal().day,
       );

  final DateTime now;
  final DateTime today;
  final bool temperatureCapable;
  final int maxDaysAgo;
  bool temperatureLoggingEnabled;

  /// Older days often have no reply. Don't wait the full history timeout.
  Duration get commandTimeout =>
      daysAgo == 0 ? const Duration(seconds: 8) : const Duration(seconds: 2);

  RingSyncPhase phase = RingSyncPhase.activity;
  int daysAgo = 0;
  int? hrPacketTotal;
  bool _awaitingTemperatureAck = false;
  bool _requestOpen = false;

  bool get isDone => phase == RingSyncPhase.done;

  /// True until the ring finishes the command returned by [nextCommand].
  bool get awaitingMore => _requestOpen;

  RingCommand? nextCommand() {
    if (phase == RingSyncPhase.done) {
      return null;
    }
    _requestOpen = true;
    switch (phase) {
      case RingSyncPhase.activity:
        return _v1('activity-$daysAgo', [
          RingPacket.cmdSyncActivity,
          daysAgo,
          0x0f,
          0x00,
          0x5f,
          0x01,
        ]);
      case RingSyncPhase.heartRate:
        final instant = daysAgo == 0
            ? now.toLocal()
            : today.subtract(Duration(days: daysAgo));
        final seconds = instant.millisecondsSinceEpoch ~/ 1000;
        return _v1('heart-rate-$daysAgo', [
          RingPacket.cmdSyncHeartRate,
          seconds & 0xff,
          (seconds >> 8) & 0xff,
          (seconds >> 16) & 0xff,
          (seconds >> 24) & 0xff,
        ]);
      case RingSyncPhase.stress:
        return _v1('stress', const [RingPacket.cmdSyncStress]);
      case RingSyncPhase.spo2:
        return _v2('spo2', const [
          RingPacket.cmdBigDataV2,
          RingPacket.bigDataSpo2,
          0x01,
          0x00,
          0xff,
          0x00,
          0xff,
        ]);
      case RingSyncPhase.sleep:
        return _v2('sleep', const [
          RingPacket.cmdBigDataV2,
          RingPacket.bigDataSleep,
          0x01,
          0x00,
          0xff,
          0x00,
          0xff,
        ]);
      case RingSyncPhase.hrv:
        return _v1('hrv-$daysAgo', [
          RingPacket.cmdSyncHrv,
          daysAgo & 0xff,
          (daysAgo >> 8) & 0xff,
          (daysAgo >> 16) & 0xff,
          (daysAgo >> 24) & 0xff,
        ]);
      case RingSyncPhase.temperature:
        if (temperatureCapable && !temperatureLoggingEnabled) {
          _awaitingTemperatureAck = true;
          temperatureLoggingEnabled = true;
          return RingCommand(
            serviceUuid: ringServiceV1Uuid,
            characteristicUuid: ringWriteUuid,
            bytes: RingPacket.temperatureLogging(enabled: true),
            label: 'enable-temperature',
          );
        }
        return _v2(
          'temperature',
          RingPacket.bigDataRead(RingPacket.bigDataTemperature),
        );
      case RingSyncPhase.done:
        return null;
    }
  }

  List<HealthMeasurement> consume(List<int> packet) {
    if (_awaitingTemperatureAck) {
      if (packet.isNotEmpty &&
          (packet[0] & 0xff) == RingPacket.cmdAutoTempPref &&
          RingPacket.checksumValid(packet)) {
        _awaitingTemperatureAck = false;
        _requestOpen = false;
      }
      return const [];
    }
    final sampleDay = phase == RingSyncPhase.heartRate
        ? today.subtract(Duration(days: daysAgo))
        : today;
    final parsed = parseRingPacket(
      packet,
      today: sampleDay,
      now: now,
      daysAgo: daysAgo,
      hrPacketTotal: hrPacketTotal,
    );
    if (parsed.ignored) {
      return const [];
    }
    if (phase == RingSyncPhase.heartRate &&
        parsed.packetNumber == 0 &&
        parsed.packetTotal != null) {
      hrPacketTotal = parsed.packetTotal;
    }
    if (parsed.dayComplete) {
      _requestOpen = false;
      _advance();
    }
    return [
      for (final measurement in parsed.measurements)
        HealthMeasurement(
          type: measurement.type,
          unit: measurement.unit,
          recordedAt: measurement.recordedAt,
          values: {...measurement.values, 'stream': 'history'},
        ),
    ];
  }

  /// A timeout means this day did not answer. Stop asking for older days.
  void skipCurrent() {
    _awaitingTemperatureAck = false;
    _requestOpen = false;
    _endPhase();
  }

  void _advance() {
    switch (phase) {
      case RingSyncPhase.activity:
        if (daysAgo < maxDaysAgo) {
          daysAgo += 1;
        } else {
          _endPhase();
        }
      case RingSyncPhase.heartRate:
        if (daysAgo < maxDaysAgo) {
          daysAgo += 1;
          hrPacketTotal = null;
        } else {
          _endPhase();
        }
      case RingSyncPhase.stress:
      case RingSyncPhase.spo2:
      case RingSyncPhase.sleep:
        _endPhase();
      case RingSyncPhase.hrv:
        if (daysAgo < maxDaysAgo) {
          daysAgo += 1;
        } else {
          _endPhase();
        }
      case RingSyncPhase.temperature:
      case RingSyncPhase.done:
        _endPhase();
    }
  }

  void _endPhase() {
    daysAgo = 0;
    hrPacketTotal = null;
    switch (phase) {
      case RingSyncPhase.activity:
        phase = RingSyncPhase.heartRate;
      case RingSyncPhase.heartRate:
        phase = RingSyncPhase.stress;
      case RingSyncPhase.stress:
        phase = RingSyncPhase.spo2;
      case RingSyncPhase.spo2:
        phase = RingSyncPhase.sleep;
      case RingSyncPhase.sleep:
        phase = RingSyncPhase.hrv;
      case RingSyncPhase.hrv:
        phase = temperatureCapable
            ? RingSyncPhase.temperature
            : RingSyncPhase.done;
      case RingSyncPhase.temperature:
      case RingSyncPhase.done:
        phase = RingSyncPhase.done;
    }
  }

  RingCommand _v1(String label, List<int> contents) {
    return RingCommand(
      serviceUuid: ringServiceV1Uuid,
      characteristicUuid: ringWriteUuid,
      bytes: RingPacket.build(contents),
      label: label,
    );
  }

  RingCommand _v2(String label, List<int> bytes) {
    return RingCommand(
      serviceUuid: ringServiceV2Uuid,
      characteristicUuid: ringCommandUuid,
      bytes: bytes,
      label: label,
    );
  }
}

/// Days of history to request. A first sync asks for today and yesterday.
/// Later syncs only cover days since the last successful one.
int ringHistoryDepth(DateTime? lastSuccess, DateTime now) {
  if (lastSuccess == null) return 1;
  final today = DateTime(now.year, now.month, now.day);
  final then = DateTime(
    lastSuccess.toLocal().year,
    lastSuccess.toLocal().month,
    lastSuccess.toLocal().day,
  );
  final days = today.difference(then).inDays;
  if (days < 0) return 0;
  if (days > 7) return 7;
  return days;
}

bool ringNameSupportsTemperature(String name) {
  return RegExp(r'^R09_').hasMatch(name) ||
      RegExp(r'^R05_[0-9A-F]{4}$').hasMatch(name);
}

bool ringNameMatches(String name) {
  return RegExp(r'^(R02|R03|R05|R06|R07|R09|R10|R12)_').hasMatch(name);
}

bool serviceListHas(List<String> uuids, String expected) {
  final target = normalizeUuid(expected);
  return uuids.map(normalizeUuid).contains(target);
}
