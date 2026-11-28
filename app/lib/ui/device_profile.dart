import 'package:bylwapp/journal/canonical_event.dart';
import 'package:bylwapp/journal/journal_store.dart';

class DeviceProfile {
  const DeviceProfile({
    required this.kind,
    required this.title,
    required this.driverId,
    required this.sensorKind,
    required this.types,
    required this.guide,
  });

  final String kind;
  final String title;
  final String driverId;
  final String sensorKind;
  final Set<String> types;
  final String guide;

  static const ring = DeviceProfile(
    kind: 'ring',
    title: '戒指',
    driverId: 'yawell_ring',
    sensorKind: 'ring',
    types: {
      'heart_rate',
      'spo2',
      'temperature',
      'steps',
      'sleep',
      'sleep_session',
    },
    guide: '打开戒指蓝牙。已连接过的戒指会在打开应用时自动重连；第一次请到「设备」页扫描 R12、R09 或 R05。',
  );
  static const heart = DeviceProfile(
    kind: 'heart_rate',
    title: '心率带 H303',
    driverId: 'heart_rate',
    sensorKind: 'heart_rate',
    types: {'heart_rate'},
    guide: '把心率带戴好并打开，到「设备」页连接 H303。',
  );
  static const pressure = DeviceProfile(
    kind: 'blood_pressure',
    title: '血压计 YE680B',
    driverId: 'blood_pressure',
    sensorKind: 'blood_pressure',
    types: {'blood_pressure'},
    guide: '打开血压计，到「设备」页连接 YE680B，测量完成后读数会出现在这里。',
  );

  static DeviceProfile? ofKind(String kind) {
    return switch (kind) {
      'ring' => ring,
      'heart_rate' => heart,
      'blood_pressure' => pressure,
      _ => null,
    };
  }

  static String kindForMetric(String type) {
    return switch (type) {
      'blood_pressure' => 'blood_pressure',
      'heart_rate' => 'heart_rate',
      _ => 'ring',
    };
  }

  bool matches(CanonicalEvent event) {
    return event.sensorKind == sensorKind &&
        types.contains(event.measurementType);
  }
}

class SeriesStats {
  const SeriesStats({
    required this.min,
    required this.max,
    required this.average,
    required this.count,
  });

  final double min;
  final double max;
  final double average;
  final int count;
}

SeriesStats? seriesStats(Iterable<double> values) {
  final list = values.toList();
  if (list.isEmpty) {
    return null;
  }
  var low = list.first;
  var high = list.first;
  var sum = 0.0;
  for (final value in list) {
    if (value < low) low = value;
    if (value > high) high = value;
    sum += value;
  }
  return SeriesStats(
    min: low,
    max: high,
    average: sum / list.length,
    count: list.length,
  );
}

DateTime eventTime(CanonicalEvent event) {
  final wall = event.wallTimeUtc;
  if (wall != null) {
    final parsed = DateTime.tryParse(wall);
    if (parsed != null) {
      return parsed.toUtc();
    }
  }
  return DateTime.fromMicrosecondsSinceEpoch(event.monotonicUs, isUtc: true);
}

bool sameDevice(JournalRecord row, DeviceProfile profile) =>
    profile.matches(row.event);

String syncLabel(String state) {
  switch (state) {
    case 'synced':
      return '已同步';
    case 'conflict':
      return '冲突';
    case 'pending':
    case 'retry_failed':
    case 'auth_blocked':
      return '待上传';
    default:
      return state;
  }
}
