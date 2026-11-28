import 'package:flutter_test/flutter_test.dart';

import 'package:bylwapp/ble/heart_rate/hr_parser.dart';

void main() {
  final now = DateTime.utc(2026, 11, 27, 8);

  test('reads uint8 heart rate and unsupported contact', () {
    final reading = parseHeartRate(const [0x00, 0x48]);
    expect(reading.bpm, 72);
    expect(reading.valueIsUint16, isFalse);
    expect(reading.sensorContact, 'unsupported');
    expect(reading.toMeasurement(now).unit, 'bpm');
  });

  test('reads uint16 heart rate', () {
    final reading = parseHeartRate(const [0x01, 0x2C, 0x01]);
    expect(reading.bpm, 300);
    expect(reading.valueIsUint16, isTrue);
  });

  test('reads sensor contact, energy, and RR intervals', () {
    expect(parseHeartRate(const [0x06, 0x50]).sensorContact, 'detected');
    expect(parseHeartRate(const [0x04, 0x50]).sensorContact, 'not_detected');

    final withEnergy = parseHeartRate(const [0x08, 0x46, 0x0F, 0x00]);
    expect(withEnergy.bpm, 70);
    expect(withEnergy.energyExpendedKj, 15);

    // 1024 / 1024 seconds = 1000 ms.
    final withRr = parseHeartRate(const [0x10, 0x3C, 0x00, 0x04]);
    expect(withRr.bpm, 60);
    expect(withRr.rrIntervalsMs, [1000]);

    // uint16 bpm 256, energy 2 kJ, one 512-tick RR interval (500 ms).
    final combined = parseHeartRate(const [
      0x19,
      0x00,
      0x01,
      0x02,
      0x00,
      0x00,
      0x02,
    ]);
    expect(combined.bpm, 256);
    expect(combined.energyExpendedKj, 2);
    expect(combined.rrIntervalsMs.single, 500);
  });

  test('keeps a worn flag without dropping the heart rate', () {
    final detected = parseHeartRate(const [0x06, 0x48]);
    expect(detected.bpm, 72);
    expect(detected.sensorContact, 'detected');
    expect(detected.raw, '06 48');

    final loose = parseHeartRate(const [0x04, 0x48]);
    expect(loose.bpm, 72);
    expect(loose.sensorContact, 'not_detected');
    expect(loose.toMeasurement(now).values['bpm'], 72);
  });

  test('keeps a zero heart rate and the raw packet', () {
    final reading = parseHeartRate(const [0x00, 0x00]);
    expect(reading.bpm, 0);
    expect(reading.sensorContact, 'unsupported');
    expect(reading.toMeasurement(now).values['raw'], '00 00');
  });

  test('reads an H303 notification with contact and RR intervals', () {
    final reading = parseHeartRate(const [0x16, 0x48, 0x00, 0x04]);
    expect(reading.bpm, 72);
    expect(reading.valueIsUint16, isFalse);
    expect(reading.sensorContact, 'detected');
    expect(reading.rrIntervalsMs, [1000]);
    expect(reading.raw, '16 48 00 04');
  });

  test('rejects a truncated value', () {
    expect(() => parseHeartRate(const [0x01]), throwsFormatException);
  });
}
