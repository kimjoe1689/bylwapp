import 'package:bylwapp/ble/bytes.dart';
import 'package:bylwapp/models/health_record.dart';

class HeartRateReading {
  const HeartRateReading({
    required this.bpm,
    required this.valueIsUint16,
    required this.sensorContact,
    this.energyExpendedKj,
    this.rrIntervalsMs = const [],
    this.raw = '',
  });

  final int bpm;
  final bool valueIsUint16;

  /// `unsupported`, `not_detected`, or `detected`.
  final String sensorContact;
  final int? energyExpendedKj;
  final List<double> rrIntervalsMs;

  final String raw;

  HealthMeasurement toMeasurement(DateTime recordedAt) {
    return HealthMeasurement(
      type: 'heart_rate',
      unit: 'bpm',
      recordedAt: recordedAt.toUtc(),
      values: {
        'bpm': bpm,
        'format': valueIsUint16 ? 'uint16' : 'uint8',
        'sensor_contact': sensorContact,
        'raw': raw,
        if (energyExpendedKj != null) 'energy_expended_kj': energyExpendedKj,
        if (rrIntervalsMs.isNotEmpty) 'rr_intervals_ms': rrIntervalsMs,
      },
    );
  }
}

/// Parses Heart Rate Measurement (0x2A37).
HeartRateReading parseHeartRate(List<int> data) {
  if (data.isEmpty) {
    throw const FormatException('empty heart rate packet');
  }
  final flags = data[0] & 0xff;
  var offset = 1;
  final uint16 = (flags & 0x01) != 0;
  final int bpm;
  if (uint16) {
    _need(data, offset, 2);
    bpm = u16le(data, offset);
    offset += 2;
  } else {
    _need(data, offset, 1);
    bpm = data[offset] & 0xff;
    offset += 1;
  }
  final contactBits = (flags >> 1) & 0x03;
  final contact = switch (contactBits) {
    2 => 'not_detected',
    3 => 'detected',
    _ => 'unsupported',
  };
  int? energy;
  if ((flags & 0x08) != 0) {
    _need(data, offset, 2);
    energy = u16le(data, offset);
    offset += 2;
  }
  final rr = <double>[];
  if ((flags & 0x10) != 0) {
    while (offset + 1 < data.length) {
      final raw = u16le(data, offset);
      offset += 2;
      rr.add(raw * 1000 / 1024);
    }
  }
  return HeartRateReading(
    bpm: bpm,
    valueIsUint16: uint16,
    sensorContact: contact,
    energyExpendedKj: energy,
    rrIntervalsMs: rr,
    raw: data.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' '),
  );
}

void _need(List<int> data, int offset, int count) {
  if (offset + count > data.length) {
    throw const FormatException('truncated heart rate packet');
  }
}
