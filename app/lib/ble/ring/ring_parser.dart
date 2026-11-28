import 'package:bylwapp/ble/bytes.dart';
import 'package:bylwapp/ble/ring/ring_packet.dart';
import 'package:bylwapp/models/health_record.dart';

class RingParseResult {
  const RingParseResult({
    this.measurements = const [],
    this.dayComplete = false,
    this.empty = false,
    this.ignored = false,
    this.packetNumber,
    this.packetTotal,
  });

  final List<HealthMeasurement> measurements;
  final bool dayComplete;
  final bool empty;
  final bool ignored;
  final int? packetNumber;
  final int? packetTotal;
}

class LiveActivitySnapshot {
  const LiveActivitySnapshot({
    required this.steps,
    required this.calories,
    required this.distanceMeters,
    required this.rawCalories,
  });

  final int steps;
  final int calories;
  final int distanceMeters;

  /// The uint24 as sent. The calorie scale is not settled.
  final int rawCalories;
}

class RingDeviceInfo {
  const RingDeviceInfo({
    this.temperature,
    this.spo2,
    this.stress,
    this.hrv,
    this.screenWidth,
    this.screenHeight,
    this.maxPacket,
    this.model,
    this.firmware,
    this.hardware,
  });

  final bool? temperature;
  final bool? spo2;
  final bool? stress;
  final bool? hrv;
  final int? screenWidth;
  final int? screenHeight;
  final int? maxPacket;
  final String? model;
  final String? firmware;
  final String? hardware;

  RingDeviceInfo merge(RingDeviceInfo newer) {
    return RingDeviceInfo(
      temperature: newer.temperature ?? temperature,
      spo2: newer.spo2 ?? spo2,
      stress: newer.stress ?? stress,
      hrv: newer.hrv ?? hrv,
      screenWidth: newer.screenWidth ?? screenWidth,
      screenHeight: newer.screenHeight ?? screenHeight,
      maxPacket: newer.maxPacket ?? maxPacket,
      model: newer.model ?? model,
      firmware: newer.firmware ?? firmware,
      hardware: newer.hardware ?? hardware,
    );
  }
}

class BatteryStatus {
  const BatteryStatus({required this.percent, required this.charging});

  final int percent;
  final bool charging;
}

/// The ring stores history as local wall-clock fields, with no timezone.
DateTime ringWallClock(
  int year,
  int month,
  int day, [
  int hour = 0,
  int minute = 0,
  int second = 0,
]) {
  return DateTime(year, month, day, hour, minute, second);
}

/// Old builds saved those wall-clock fields with a UTC constructor, so the
/// stored instant is ahead by the phone's offset. Rebuild the same fields
/// as a local time.
DateTime correctedRingInstant(DateTime storedUtc) {
  final utc = storedUtc.toUtc();
  return DateTime(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond,
    utc.microsecond,
  );
}

double? ringCelsius(int raw) {
  if (raw <= 0) return null;
  final shifted = raw / 10 + 20;
  if (shifted >= 30 && shifted <= 42) return shifted;
  final tenths = raw / 10;
  if (tenths >= 30 && tenths <= 42) return tenths;
  final hundredths = raw / 100;
  if (hundredths >= 30 && hundredths <= 42) return hundredths;
  if (raw >= 30 && raw <= 42) return raw.toDouble();
  return null;
}

/// Decodes one plaintext ring notification into measurements.
///
/// [today] is the ring's local midnight. [now] drops heart-rate slots the
/// firmware has not measured yet. [daysAgo] is only used for HRV.
RingParseResult parseRingPacket(
  List<int> packet, {
  required DateTime today,
  required DateTime now,
  int daysAgo = 0,
  int? hrPacketTotal,
}) {
  if (packet.isEmpty) {
    return const RingParseResult(ignored: true);
  }
  final command = packet[0] & 0xff;
  if (command == RingPacket.cmdManualHeartRate &&
      packet.length >= 4 &&
      packet.length != 16) {
    if ((packet[1] & 0xff) == RingPacket.manualTemperature) {
      return _parseManualTemperature(packet, now);
    }
    return _parseManualHeartRate(packet, now);
  }
  if (command == RingPacket.cmdBigDataV2) {
    return _parseBigData(packet, today);
  }
  if (!RingPacket.checksumValid(packet)) {
    return const RingParseResult(ignored: true);
  }
  switch (command) {
    case RingPacket.cmdSyncActivity:
      return _parseActivity(packet);
    case RingPacket.cmdSyncHeartRate:
      return _parseHeartRateHistory(
        packet,
        today: today,
        now: now,
        expectedTotal: hrPacketTotal,
      );
    case RingPacket.cmdSyncStress:
      return _parseStress(packet, today);
    case RingPacket.cmdSyncHrv:
      return _parseHrv(packet, today, daysAgo);
    case RingPacket.cmdManualHeartRate:
      if ((packet[1] & 0xff) == RingPacket.manualTemperature) {
        return _parseManualTemperature(packet, now);
      }
      return _parseManualHeartRate(packet, now);
    case RingPacket.cmdRealtimeHeartRate:
      return _parseRealtimeHeartRate(packet, now);
    case RingPacket.cmdNotification:
      return _parseNotification(packet, now);
    default:
      return const RingParseResult(ignored: true);
  }
}

/// A short label for unsolicited events. Null hides realtime streams and
/// replies that belong to a history sync.
String? ringNoticeLabel(List<int> packet) {
  if (packet.isEmpty) return null;
  final command = packet[0] & 0xff;
  if (command == RingPacket.cmdRealtimeHeartRate) return null;
  if (command == RingPacket.cmdManualHeartRate) {
    if (packet.length > 1 &&
        (packet[1] & 0xff) == RingPacket.manualTemperature) {
      final parsed = _parseManualTemperature(packet, DateTime.now());
      final celsius = parsed.measurements.isEmpty
          ? null
          : parsed.measurements.single.values['celsius'];
      if (celsius is num) return '体温 ${celsius.toStringAsFixed(1)}';
    }
    return null;
  }
  if (command == 0x2f) return null;
  if (command == RingPacket.cmdNotification) {
    return describeRingNotification(packet);
  }
  if (command == 0x02) {
    final subtype = packet.length > 1 ? packet[1] & 0xff : 0;
    final hex = subtype.toRadixString(16).padLeft(2, '0');
    if (subtype == 0) return '手势已确认';
    if (subtype == 2) return '检测到挥手';
    return '手势回应 0x02/$hex';
  }
  if (_routineHistoryCommand(command)) return null;
  final battery = parseBattery(packet);
  if (battery != null) return '电量 ${battery.percent}%';
  if (command == RingPacket.cmdBattery && packet.length >= 2) {
    return '电量 ${packet[1] & 0xff}%';
  }
  if (command == RingPacket.cmdFind) return '戒指已响应寻找';
  return 'unknown 0x${command.toRadixString(16).padLeft(2, '0')}';
}

/// A label for every packet. Unknown commands stay marked unknown.
String describeAnyRingPacket(List<int> packet) {
  final known = ringNoticeLabel(packet);
  if (known != null) return known;
  if (packet.isEmpty) return 'unknown';
  final command = packet[0] & 0xff;
  final routine = switch (command) {
    RingPacket.cmdSetDateTime => '对时',
    RingPacket.cmdSyncHeartRate => '心率历史',
    RingPacket.cmdAutoHeartRate => '自动心率',
    RingPacket.cmdAutoSpo2 => '自动血氧',
    RingPacket.cmdAutoStress => '自动压力',
    RingPacket.cmdSyncStress => '压力历史',
    RingPacket.cmdSyncHrv => 'HRV历史',
    RingPacket.cmdAutoTempPref => '体温开关',
    RingPacket.cmdSyncActivity => '步数历史',
    RingPacket.cmdTodaySummary => '今日汇总',
    RingPacket.cmdStopHeartRate => '停止心率',
    RingPacket.cmdRealtimeHeartRate => '心率保活',
    RingPacket.cmdBigDataV2 => '历史数据',
    RingPacket.cmdManualHeartRate => '实时测量',
    _ => null,
  };
  if (routine != null) return routine;
  final hex = command.toRadixString(16).padLeft(2, '0');
  if (packet.length < 2) return 'unknown 0x$hex';
  final sub = (packet[1] & 0xff).toRadixString(16).padLeft(2, '0');
  return 'unknown 0x$hex/0x$sub';
}

bool ringLabelUnknown(String label) {
  return label.startsWith('unknown') || label.startsWith('未知');
}

bool _routineHistoryCommand(int command) {
  return switch (command) {
    RingPacket.cmdSetDateTime ||
    RingPacket.cmdSyncHeartRate ||
    RingPacket.cmdAutoHeartRate ||
    RingPacket.cmdAutoSpo2 ||
    RingPacket.cmdAutoStress ||
    RingPacket.cmdSyncStress ||
    RingPacket.cmdSyncHrv ||
    RingPacket.cmdAutoTempPref ||
    RingPacket.cmdSyncActivity ||
    RingPacket.cmdTodaySummary ||
    RingPacket.cmdStopHeartRate ||
    RingPacket.cmdBigDataV2 => true,
    _ => false,
  };
}

BatteryStatus? parseBattery(List<int> packet) {
  if (packet.length < 3 || (packet[0] & 0xff) != RingPacket.cmdBattery) {
    return null;
  }
  if (!RingPacket.checksumValid(packet)) {
    return null;
  }
  return BatteryStatus(
    percent: packet[1] & 0xff,
    charging: (packet[2] & 0xff) == 1,
  );
}

LiveActivitySnapshot? parseLiveActivity(List<int> packet) {
  if (packet.length < 11 || (packet[0] & 0xff) != RingPacket.cmdNotification) {
    return null;
  }
  if ((packet[1] & 0xff) != RingPacket.notificationLiveActivity) {
    return null;
  }
  final rawCalories = _u24(packet[5], packet[6], packet[7]);
  return LiveActivitySnapshot(
    steps: _u24(packet[2], packet[3], packet[4]),
    calories: rawCalories ~/ 10,
    distanceMeters: _u24(packet[8], packet[9], packet[10]),
    rawCalories: rawCalories,
  );
}

/// Set-time replies carry capability bits, not the clock.
RingDeviceInfo? parseSetTimeReply(List<int> packet) {
  if (packet.length < 15 || (packet[0] & 0xff) != RingPacket.cmdSetDateTime) {
    return null;
  }
  final flags1 = packet[4] & 0xff;
  final flags4 = packet[14] & 0xff;
  final widthBe = _u16be(packet, 5);
  final heightBe = _u16be(packet, 7);
  final widthLe = _u16le(packet, 5);
  final heightLe = _u16le(packet, 7);
  final width = widthBe != 0 ? widthBe : widthLe;
  final height = heightBe != 0 ? heightBe : heightLe;
  return RingDeviceInfo(
    temperature: (packet[1] & 0xff) == 1,
    spo2: (flags1 & 0x02) != 0,
    stress: (flags4 & 0x10) != 0,
    hrv: (flags4 & 0x20) != 0,
    screenWidth: width == 0 ? null : width,
    screenHeight: height == 0 ? null : height,
  );
}

/// 0x2f reports the largest packet the ring accepts.
int? parsePackageLength(List<int> packet) {
  if (packet.length < 2 || (packet[0] & 0xff) != 0x2f) return null;
  final length = packet[1] & 0xff;
  return length == 0 ? null : length;
}

/// Chinese label for a 0x73 notification, including unknown subtypes.
String describeRingNotification(List<int> packet) {
  final subtype = packet.length > 1 ? packet[1] & 0xff : 0;
  final hex = subtype.toRadixString(16).padLeft(2, '0');
  switch (subtype) {
    case 0x01:
      return '有新的心率数据';
    case 0x03:
      return '有新的血氧数据';
    case 0x04:
      return '有新的步数明细';
    case 0x05:
      return '有新的体温数据';
    case 0x0c:
      final percent = packet.length > 2 ? packet[2] & 0xff : 0;
      final charging = packet.length > 3 && (packet[3] & 0xff) == 1;
      return charging ? '电量 $percent% 充电中' : '电量 $percent%';
    case 0x12:
      final live = parseLiveActivity(packet);
      if (live == null) return '实时步数';
      return '步数 ${live.steps}，距离 ${live.distanceMeters} 米，热量原始值 ${live.rawCalories}（单位未确定）';
    case 0x27:
      final raw = _guessTemperatureRaw(packet);
      if (raw == null) return '推测体温';
      final celsius = raw / 10 + 20;
      return '推测体温 ${celsius.toStringAsFixed(1)} °C';
    default:
      return '未知通知 0x73/0x$hex';
  }
}

int? _guessTemperatureRaw(List<int> packet) {
  for (final index in [2, 3]) {
    if (packet.length <= index) continue;
    final raw = packet[index] & 0xff;
    final celsius = raw / 10 + 20;
    if (celsius >= 30 && celsius <= 42) return raw;
  }
  return null;
}

int _u16be(List<int> packet, int offset) {
  return ((packet[offset] & 0xff) << 8) | (packet[offset + 1] & 0xff);
}

int _u16le(List<int> packet, int offset) {
  return (packet[offset] & 0xff) | ((packet[offset + 1] & 0xff) << 8);
}

RingParseResult _parseActivity(List<int> packet) {
  final marker = packet[1] & 0xff;
  if (marker == 0xff) {
    return const RingParseResult(empty: true, dayComplete: true);
  }
  if (marker == 0xf0) {
    return const RingParseResult();
  }
  final year = bcdByte(packet[1]);
  final month = bcdByte(packet[2]);
  final day = bcdByte(packet[3]);
  if (year == null || month == null || day == null) {
    return const RingParseResult(ignored: true);
  }
  final hour = (packet[4] & 0xff) ~/ 4;
  final recordedAt = ringWallClock(2000 + year, month, day, hour);
  final calories = u16le(packet, 7);
  final steps = u16le(packet, 9);
  final distance = u16le(packet, 11);
  final current = packet[5] & 0xff;
  final total = packet[6] & 0xff;
  return RingParseResult(
    dayComplete: total > 0 && current == total - 1,
    packetNumber: current,
    packetTotal: total,
    measurements: [
      HealthMeasurement(
        type: 'steps',
        unit: 'steps',
        recordedAt: recordedAt,
        values: {'steps': steps, 'calories': calories, 'distance_m': distance},
      ),
    ],
  );
}

RingParseResult _parseHeartRateHistory(
  List<int> packet, {
  required DateTime today,
  required DateTime now,
  int? expectedTotal,
}) {
  final number = packet[1] & 0xff;
  if (number == 0xff) {
    return const RingParseResult(
      empty: true,
      dayComplete: true,
      packetNumber: 0xff,
    );
  }
  if (number == 0) {
    final total = packet[2] & 0xff;
    return RingParseResult(
      packetNumber: 0,
      packetTotal: total,
      empty: total <= 1,
      dayComplete: total <= 1,
    );
  }
  final start = number == 1 ? 6 : 2;
  var previousMinutes = 0;
  if (number > 1) {
    previousMinutes = 9 * 5 + (number - 2) * 13 * 5;
  }
  final samples = <HealthMeasurement>[];
  for (var i = start; i < packet.length - 1; i++) {
    final bpm = packet[i] & 0xff;
    if (bpm == 0) {
      continue;
    }
    final minuteOfDay = previousMinutes + (i - start) * 5;
    final recordedAt = ringWallClock(
      today.year,
      today.month,
      today.day,
      minuteOfDay ~/ 60,
      minuteOfDay % 60,
    );
    if (recordedAt.isAfter(now)) {
      continue;
    }
    samples.add(
      HealthMeasurement(
        type: 'heart_rate',
        unit: 'bpm',
        recordedAt: recordedAt,
        values: {'bpm': bpm},
      ),
    );
  }
  final total = expectedTotal;
  final done = total != null && number == total - 1;
  return RingParseResult(
    measurements: samples,
    dayComplete: done,
    packetNumber: number,
    packetTotal: total,
  );
}

RingParseResult _parseStress(List<int> packet, DateTime today) {
  final number = packet[1] & 0xff;
  if (number == 0xff) {
    return const RingParseResult(
      empty: true,
      dayComplete: true,
      packetNumber: 0xff,
    );
  }
  if (number == 0) {
    return const RingParseResult(packetNumber: 0);
  }
  final start = number == 1 ? 3 : 2;
  var previousMinutes = 0;
  if (number > 1) {
    previousMinutes = 12 * 30 + (number - 2) * 13 * 30;
  }
  final samples = <HealthMeasurement>[];
  for (var i = start; i < packet.length - 1; i++) {
    final stress = packet[i] & 0xff;
    if (stress == 0) {
      continue;
    }
    final minuteOfDay = previousMinutes + (i - start) * 30;
    samples.add(
      HealthMeasurement(
        type: 'stress',
        unit: 'level',
        recordedAt: ringWallClock(
          today.year,
          today.month,
          today.day,
          minuteOfDay ~/ 60,
          minuteOfDay % 60,
        ),
        values: {'stress': stress},
      ),
    );
  }
  return RingParseResult(
    measurements: samples,
    dayComplete: number == 4,
    packetNumber: number,
  );
}

RingParseResult _parseHrv(List<int> packet, DateTime today, int daysAgo) {
  final number = packet[1] & 0xff;
  final day = today.subtract(Duration(days: daysAgo));
  if (number == 0xff) {
    return const RingParseResult(
      empty: true,
      dayComplete: true,
      packetNumber: 0xff,
    );
  }
  if (number == 0) {
    return RingParseResult(
      packetNumber: 0,
      packetTotal: packet.length > 2 ? packet[2] & 0xff : null,
    );
  }
  final start = number == 1 ? 3 : 2;
  var previousMinutes = 0;
  if (number > 1) {
    previousMinutes = 12 * 30 + (number - 2) * 13 * 30;
  }
  final samples = <HealthMeasurement>[];
  for (var i = start; i < packet.length - 1; i++) {
    final hrv = packet[i] & 0xff;
    if (hrv == 0) {
      continue;
    }
    final minuteOfDay = previousMinutes + (i - start) * 30;
    samples.add(
      HealthMeasurement(
        type: 'hrv',
        unit: 'ms',
        recordedAt: ringWallClock(
          day.year,
          day.month,
          day.day,
          minuteOfDay ~/ 60,
          minuteOfDay % 60,
        ),
        values: {'hrv_ms': hrv},
      ),
    );
  }
  return RingParseResult(
    measurements: samples,
    dayComplete: number == 4,
    packetNumber: number,
  );
}

RingParseResult _parseManualTemperature(List<int> packet, DateTime now) {
  if (packet.length < 4) return const RingParseResult(ignored: true);
  final raw = (packet[2] & 0xff) == 0
      ? packet[3] & 0xff
      : (packet[2] & 0xff) | ((packet[3] & 0xff) << 8);
  final celsius = ringCelsius(raw);
  if (celsius == null) {
    return const RingParseResult(empty: true);
  }
  return RingParseResult(
    measurements: [
      HealthMeasurement(
        type: 'temperature',
        unit: '°C',
        recordedAt: now.toUtc(),
        values: {'celsius': celsius, 'raw': raw, 'source': 'manual'},
      ),
    ],
  );
}

RingParseResult _parseManualHeartRate(List<int> packet, DateTime now) {
  if (packet.length < 4) {
    return const RingParseResult(ignored: true);
  }
  final error = packet[2] & 0xff;
  final bpm = packet[3] & 0xff;
  if (error != 0 || bpm == 0) {
    return RingParseResult(ignored: error != 0, empty: bpm == 0);
  }
  return RingParseResult(
    measurements: [
      HealthMeasurement(
        type: 'heart_rate',
        unit: 'bpm',
        recordedAt: now.toUtc(),
        values: {'bpm': bpm, 'source': 'manual'},
      ),
    ],
  );
}

RingParseResult _parseRealtimeHeartRate(List<int> packet, DateTime now) {
  if (packet.length < 2) {
    return const RingParseResult(ignored: true);
  }
  final bpm = packet[1] & 0xff;
  if (bpm == 0) {
    return const RingParseResult(empty: true);
  }
  return RingParseResult(
    measurements: [
      HealthMeasurement(
        type: 'heart_rate',
        unit: 'bpm',
        recordedAt: now.toUtc(),
        values: {'bpm': bpm, 'source': 'realtime'},
      ),
    ],
  );
}

RingParseResult _parseNotification(List<int> packet, DateTime now) {
  final live = parseLiveActivity(packet);
  if (live == null) {
    return const RingParseResult(ignored: true);
  }
  return RingParseResult(
    measurements: [
      HealthMeasurement(
        type: 'steps',
        unit: 'steps',
        recordedAt: now.toUtc(),
        values: {
          'steps': live.steps,
          'calories': live.calories,
          'distance_m': live.distanceMeters,
          'cumulative': true,
        },
      ),
    ],
  );
}

RingParseResult _parseBigData(List<int> packet, DateTime today) {
  if (packet.length < 6) {
    return const RingParseResult(ignored: true);
  }
  final length = u16le(packet, 2);
  if (packet.length < length + 6) {
    return const RingParseResult(ignored: true);
  }
  final payload = packet.sublist(6, 6 + length);
  final crc = u16le(packet, 4);
  if (crc != RingPacket.crc16Modbus(payload)) {
    return const RingParseResult(ignored: true);
  }
  switch (packet[1] & 0xff) {
    case RingPacket.bigDataSpo2:
      return RingParseResult(
        measurements: _spo2(payload, today),
        dayComplete: true,
      );
    case RingPacket.bigDataSleep:
      return RingParseResult(
        measurements: _sleep(payload, today),
        dayComplete: true,
        empty: length < 2,
      );
    case RingPacket.bigDataTemperature:
      if (length < 50) {
        return const RingParseResult(empty: true, dayComplete: true);
      }
      return RingParseResult(
        measurements: _temperature(payload, today),
        dayComplete: true,
      );
    default:
      return const RingParseResult(ignored: true);
  }
}

List<HealthMeasurement> _spo2(List<int> payload, DateTime today) {
  final samples = <HealthMeasurement>[];
  var index = 0;
  var daysAgo = -1;
  while (daysAgo != 0 && index < payload.length) {
    daysAgo = payload[index] & 0xff;
    index++;
    final day = today.subtract(Duration(days: daysAgo));
    for (var hour = 0; hour <= 23 && index + 1 < payload.length; hour++) {
      final min = payload[index] & 0xff;
      final max = payload[index + 1] & 0xff;
      index += 2;
      if (min > 0 && max > 0) {
        samples.add(
          HealthMeasurement(
            type: 'spo2',
            unit: '%',
            recordedAt: ringWallClock(day.year, day.month, day.day, hour),
            values: {'spo2': ((min + max) / 2).round(), 'min': min, 'max': max},
          ),
        );
      }
    }
  }
  return samples;
}

List<HealthMeasurement> _sleep(List<int> payload, DateTime today) {
  if (payload.isEmpty) {
    return const [];
  }
  final days = payload[0] & 0xff;
  var index = 1;
  final samples = <HealthMeasurement>[];
  for (var i = 0; i < days; i++) {
    if (index + 6 > payload.length) {
      break;
    }
    final daysAgo = payload[index] & 0xff;
    final dayBytes = payload[index + 1] & 0xff;
    final sleepStart = u16le(payload, index + 2);
    final sleepEnd = u16le(payload, index + 4);
    index += 6;
    final day = today.subtract(Duration(days: daysAgo));
    final midnight = ringWallClock(day.year, day.month, day.day);
    final start = midnight.add(
      Duration(minutes: sleepStart > sleepEnd ? sleepStart - 1440 : sleepStart),
    );
    final end = midnight.add(Duration(minutes: sleepEnd));
    samples.add(
      HealthMeasurement(
        type: 'sleep_session',
        unit: 'min',
        recordedAt: start,
        values: {
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
          'days_ago': daysAgo,
        },
      ),
    );
    final stageCount = dayBytes < 4 ? 0 : ((dayBytes - 4) ~/ 2);
    var cursor = start;
    for (
      var stage = 0;
      stage < stageCount && index + 1 < payload.length;
      stage++
    ) {
      final code = payload[index] & 0xff;
      final minutes = payload[index + 1] & 0xff;
      index += 2;
      if (minutes == 0) {
        continue;
      }
      samples.add(
        HealthMeasurement(
          type: 'sleep',
          unit: 'min',
          recordedAt: cursor,
          values: {
            'stage': _stageName(code),
            'stage_code': code,
            'duration_min': minutes,
          },
        ),
      );
      cursor = cursor.add(Duration(minutes: minutes));
    }
  }
  return samples;
}

List<HealthMeasurement> _temperature(List<int> payload, DateTime today) {
  final samples = <HealthMeasurement>[];
  var index = 0;
  var daysAgo = -1;
  while (daysAgo != 0 && index < payload.length) {
    daysAgo = payload[index] & 0xff;
    index += 2;
    final day = today.subtract(Duration(days: daysAgo));
    for (var hour = 0; hour <= 23 && index + 1 < payload.length; hour++) {
      final onHour = payload[index] & 0xff;
      final onHalf = payload[index + 1] & 0xff;
      index += 2;
      if (onHour > 0) {
        samples.add(_temp(day, hour, 0, onHour));
      }
      if (onHalf > 0) {
        samples.add(_temp(day, hour, 30, onHalf));
      }
    }
  }
  return samples;
}

HealthMeasurement _temp(DateTime day, int hour, int minute, int raw) {
  return HealthMeasurement(
    type: 'temperature',
    unit: '°C',
    recordedAt: ringWallClock(day.year, day.month, day.day, hour, minute),
    values: {'celsius': raw / 10 + 20},
  );
}

String _stageName(int code) {
  switch (code) {
    case RingPacket.sleepLight:
      return 'light';
    case RingPacket.sleepDeep:
      return 'deep';
    case RingPacket.sleepRem:
      return 'rem';
    case RingPacket.sleepAwake:
      return 'awake';
    default:
      return 'unknown';
  }
}

int _u24(int high, int mid, int low) {
  return ((high & 0xff) << 16) | ((mid & 0xff) << 8) | (low & 0xff);
}
