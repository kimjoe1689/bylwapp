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
  });

  final int steps;
  final int calories;
  final int distanceMeters;
}

class BatteryStatus {
  const BatteryStatus({required this.percent, required this.charging});

  final int percent;
  final bool charging;
}

/// Decodes one plaintext ring notification into measurements.
///
/// [today] is the ring's local midnight, stored as UTC because the protocol
/// has no timezone. [now] drops heart-rate slots that the firmware has not
/// measured yet. [daysAgo] is only used for HRV, which does not carry a date.
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
      return _parseManualHeartRate(packet, now);
    case RingPacket.cmdRealtimeHeartRate:
      return _parseRealtimeHeartRate(packet, now);
    case RingPacket.cmdNotification:
      return _parseNotification(packet, now);
    default:
      return const RingParseResult(ignored: true);
  }
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
  return LiveActivitySnapshot(
    steps: _u24(packet[2], packet[3], packet[4]),
    calories: _u24(packet[5], packet[6], packet[7]) ~/ 10,
    distanceMeters: _u24(packet[8], packet[9], packet[10]),
  );
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
  final recordedAt = DateTime.utc(2000 + year, month, day, hour);
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
    final recordedAt = DateTime.utc(
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
        recordedAt: DateTime.utc(
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
        recordedAt: DateTime.utc(
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
            recordedAt: DateTime.utc(day.year, day.month, day.day, hour),
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
    final midnight = today.subtract(Duration(days: daysAgo));
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
    recordedAt: DateTime.utc(day.year, day.month, day.day, hour, minute),
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
