class HealthDevice {
  const HealthDevice({
    required this.name,
    required this.kind,
    required this.address,
    this.model = '',
  });

  final String name;
  final String kind;
  final String address;
  final String model;

  Map<String, dynamic> toJson() => {
    'name': name,
    'kind': kind,
    'address': address,
    'model': model,
  };
}

class HealthMeasurement {
  const HealthMeasurement({
    required this.type,
    required this.unit,
    required this.recordedAt,
    required this.values,
  });

  final String type;
  final String unit;
  final DateTime recordedAt;
  final Map<String, Object?> values;

  Map<String, dynamic> toJson() => {
    'type': type,
    'unit': unit,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'values': values,
  };

  factory HealthMeasurement.fromJson(Map<String, dynamic> json) {
    final rawValues = json['values'];
    final values = <String, Object?>{};
    if (rawValues is Map) {
      rawValues.forEach((key, value) => values['$key'] = value);
    }
    return HealthMeasurement(
      type: json['type'] as String,
      unit: json['unit'] as String,
      recordedAt: DateTime.parse(json['recorded_at'] as String).toUtc(),
      values: values,
    );
  }
}

class LocalRecord {
  const LocalRecord({
    this.id,
    required this.device,
    required this.measurement,
    this.synced = false,
  });

  final int? id;
  final HealthDevice device;
  final HealthMeasurement measurement;
  final bool synced;
}

String measurementLabel(String type) {
  switch (type) {
    case 'blood_pressure':
      return '血压';
    case 'heart_rate':
      return '心率';
    case 'steps':
      return '步数';
    case 'spo2':
      return '血氧';
    case 'sleep':
      return '睡眠';
    case 'sleep_session':
      return '睡眠时段';
    case 'stress':
      return '压力';
    case 'hrv':
      return 'HRV';
    case 'temperature':
      return '体温';
    default:
      return type;
  }
}

String summarize(HealthMeasurement measurement) {
  String number(Object? value) {
    if (value is num && value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return '${value ?? '--'}';
  }

  final values = measurement.values;
  switch (measurement.type) {
    case 'blood_pressure':
      return '${number(values['systolic'])}/${number(values['diastolic'])} ${measurement.unit}';
    case 'heart_rate':
      return '${number(values['bpm'])} ${measurement.unit}';
    case 'steps':
      return '${number(values['steps'])} ${measurement.unit}';
    case 'spo2':
      return '${number(values['spo2'])} ${measurement.unit}';
    case 'sleep':
      return '${values['stage'] ?? ''} ${number(values['duration_min'])} ${measurement.unit}';
    case 'stress':
      return '${number(values['stress'])} ${measurement.unit}';
    case 'hrv':
      return '${number(values['hrv_ms'])} ${measurement.unit}';
    case 'temperature':
      return '${number(values['celsius'])} ${measurement.unit}';
    default:
      return '${measurement.type} ${measurement.unit}';
  }
}
