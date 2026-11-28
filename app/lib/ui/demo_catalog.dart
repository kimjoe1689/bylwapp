import 'package:bylwapp/models/health_record.dart';

/// In-memory preview readings. Callers must not persist or upload these.
class DemoCatalog {
  static final recordedAt = DateTime.utc(2026, 11, 27, 8, 20);

  static const devices = [
    ('Colmi R09', 'ring', 'R09-DEMO', '戒指'),
    ('Magene H303', 'heart_rate', 'H303-DEMO', '心率带'),
    ('Yuwell YE680B', 'blood_pressure', 'YE680B-DEMO', '血压计'),
  ];

  static List<LocalRecord> records() {
    LocalRecord row(
      String name,
      String kind,
      String address,
      String type,
      String unit,
      Map<String, Object?> values,
      int minute,
    ) {
      return LocalRecord(
        device: HealthDevice(
          name: name,
          kind: kind,
          address: address,
          model: name,
        ),
        measurement: HealthMeasurement(
          type: type,
          unit: unit,
          recordedAt: recordedAt.add(Duration(minutes: minute)),
          values: values,
        ),
      );
    }

    return [
      row(
        'Yuwell YE680B',
        'blood_pressure',
        'YE680B-DEMO',
        'blood_pressure',
        'mmHg',
        {'systolic': 118, 'diastolic': 76, 'pulse': 68},
        0,
      ),
      row(
        'Yuwell YE680B',
        'blood_pressure',
        'YE680B-DEMO',
        'blood_pressure',
        'mmHg',
        {'systolic': 122, 'diastolic': 78, 'pulse': 70},
        20,
      ),
      row('Magene H303', 'heart_rate', 'H303-DEMO', 'heart_rate', 'bpm', {
        'bpm': 66,
      }, 5),
      row('Magene H303', 'heart_rate', 'H303-DEMO', 'heart_rate', 'bpm', {
        'bpm': 72,
      }, 25),
      row('Colmi R09', 'ring', 'R09-DEMO', 'spo2', '%', {'spo2': 98}, 8),
      row('Colmi R09', 'ring', 'R09-DEMO', 'temperature', '°C', {
        'celsius': 36.4,
      }, 9),
      row('Colmi R09', 'ring', 'R09-DEMO', 'steps', 'steps', {
        'steps': 1860,
      }, 10),
      row('Colmi R09', 'ring', 'R09-DEMO', 'sleep', 'min', {
        'stage': 'light',
        'duration_min': 40,
      }, 11),
    ];
  }
}
