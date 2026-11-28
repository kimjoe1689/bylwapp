import 'package:flutter_test/flutter_test.dart';

import 'package:bylwapp/ble/blood_pressure/bp_parser.dart';

void main() {
  test('parses a mmHg measurement with timestamp and pulse', () {
    // Flags 0x06: mmHg (bit 0 clear), timestamp, pulse.
    // 120 / 80 / 93 mmHg, 2026-11-27 08:15:09, pulse 70.
    const packet = [
      0x06,
      0x78,
      0x00,
      0x50,
      0x00,
      0x5D,
      0x00,
      0xEA,
      0x07,
      0x0B,
      0x1B,
      0x08,
      0x0F,
      0x09,
      0x46,
      0x00,
    ];

    final reading = parseBloodPressure(packet);
    expect(reading.unit, 'mmHg');
    expect(reading.systolic, 120);
    expect(reading.diastolic, 80);
    expect(reading.meanArterial, 93);
    expect(reading.pulse, 70);
    expect(reading.timestamp, DateTime.utc(2026, 11, 27, 8, 15, 9));

    final measurement = reading.toMeasurement(DateTime.utc(2020));
    expect(measurement.type, 'blood_pressure');
    expect(measurement.values['timestamp_from_device'], isTrue);
  });

  test(
    'uses kPa when the unit flag is set and falls back when time is absent',
    () {
      const packet = [0x01, 0x78, 0x00, 0x50, 0x00, 0x5D, 0x00];
      final reading = parseBloodPressure(packet);
      expect(reading.unit, 'kPa');
      expect(reading.timestamp, isNull);
      final fallback = DateTime.utc(2026, 1, 2, 3, 4, 5);
      expect(reading.toMeasurement(fallback).recordedAt, fallback);
    },
  );

  test('encodes date time and current time', () {
    final time = DateTime.utc(2026, 11, 27, 8, 15, 9);
    expect(encodeDateTime(time), [0xEA, 0x07, 0x0B, 0x1B, 0x08, 0x0F, 0x09]);
    expect(encodeCurrentTime(time), [
      0xEA,
      0x07,
      0x0B,
      0x1B,
      0x08,
      0x0F,
      0x09,
      DateTime.friday,
      0x00,
      0x01,
    ]);
  });

  test('rejects a truncated packet', () {
    expect(() => parseBloodPressure(const [0x00, 0x78]), throwsFormatException);
  });
}
