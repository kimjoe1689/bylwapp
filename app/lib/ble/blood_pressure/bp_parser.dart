import 'package:bylwapp/ble/blood_pressure/sfloat.dart';
import 'package:bylwapp/ble/bytes.dart';
import 'package:bylwapp/models/health_record.dart';

class BloodPressureReading {
  const BloodPressureReading({
    required this.systolic,
    required this.diastolic,
    required this.meanArterial,
    required this.unit,
    this.timestamp,
    this.pulse,
    this.userId,
    this.status,
  });

  final double systolic;
  final double diastolic;
  final double meanArterial;
  final String unit;
  final DateTime? timestamp;
  final double? pulse;
  final int? userId;
  final int? status;

  HealthMeasurement toMeasurement(DateTime fallbackTime) {
    return HealthMeasurement(
      type: 'blood_pressure',
      unit: unit,
      recordedAt: (timestamp ?? fallbackTime).toUtc(),
      values: {
        'systolic': systolic,
        'diastolic': diastolic,
        'mean_arterial': meanArterial,
        if (pulse != null) 'pulse': pulse,
        if (userId != null) 'user_id': userId,
        if (status != null) 'status': status,
        'timestamp_from_device': timestamp != null,
      },
    );
  }
}

/// Parses Blood Pressure Measurement (0x2A35).
BloodPressureReading parseBloodPressure(List<int> data) {
  final reader = _ByteReader(data);
  final flags = reader.u8();
  final unit = (flags & 0x01) == 0 ? 'mmHg' : 'kPa';
  final systolic = _required(reader.sfloat(), 'systolic');
  final diastolic = _required(reader.sfloat(), 'diastolic');
  final mean = _required(reader.sfloat(), 'mean_arterial');
  DateTime? timestamp;
  if ((flags & 0x02) != 0) {
    timestamp = reader.dateTime();
  }
  double? pulse;
  if ((flags & 0x04) != 0) {
    pulse = _required(reader.sfloat(), 'pulse');
  }
  int? userId;
  if ((flags & 0x08) != 0) {
    userId = reader.u8();
  }
  int? status;
  if ((flags & 0x10) != 0) {
    status = reader.u16();
  }
  return BloodPressureReading(
    systolic: systolic,
    diastolic: diastolic,
    meanArterial: mean,
    unit: unit,
    timestamp: timestamp,
    pulse: pulse,
    userId: userId,
    status: status,
  );
}

/// Date Time characteristic (0x2A08), little-endian year.
List<int> encodeDateTime(DateTime time) {
  final wall = time.toUtc();
  final year = wall.year;
  return [
    year & 0xff,
    (year >> 8) & 0xff,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
  ];
}

/// Current Time characteristic (0x2A2B). Day of week uses 1 = Monday.
List<int> encodeCurrentTime(DateTime time) {
  final wall = time.toUtc();
  return [...encodeDateTime(wall), wall.weekday, 0, 0x01];
}

double _required(double? value, String field) {
  if (value == null || value.isInfinite) {
    throw FormatException('blood pressure $field is not a finite SFLOAT');
  }
  return value;
}

class _ByteReader {
  _ByteReader(this.data);

  final List<int> data;
  int offset = 0;

  int u8() {
    _need(1);
    return data[offset++] & 0xff;
  }

  int u16() {
    _need(2);
    final value = u16le(data, offset);
    offset += 2;
    return value;
  }

  double? sfloat() {
    final word = u16();
    return Sfloat.decode(word);
  }

  DateTime dateTime() {
    final year = u16();
    final month = u8();
    final day = u8();
    final hour = u8();
    final minute = u8();
    final second = u8();
    return DateTime.utc(year, month, day, hour, minute, second);
  }

  void _need(int count) {
    if (offset + count > data.length) {
      throw const FormatException('truncated blood pressure packet');
    }
  }
}
