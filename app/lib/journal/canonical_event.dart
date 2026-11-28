import 'dart:convert';

import 'package:crypto/crypto.dart';

const schemaVersion = 'bylw-measure/1';

class CanonicalEvent {
  CanonicalEvent({
    required this.eventId,
    required this.deviceId,
    required this.sessionId,
    required this.sensorAddress,
    required this.sensorKind,
    required this.sensorModel,
    required this.measurementType,
    required this.unit,
    required this.monotonicUs,
    required this.clockState,
    required this.operatingState,
    required this.values,
    this.wallTimeUtc,
  });

  final String eventId;
  final String deviceId;
  final String sessionId;
  final String sensorAddress;
  final String sensorKind;
  final String sensorModel;
  final String measurementType;
  final String unit;
  final int monotonicUs;
  final String? wallTimeUtc;
  final String clockState;
  final String operatingState;
  final Map<String, Object?> values;

  String get canonicalJson {
    final fields = <String, Object?>{
      'clock_state': clockState,
      'device_id': deviceId,
      'event_id': eventId,
      'measurement_type': measurementType,
      'monotonic_us': monotonicUs,
      'operating_state': operatingState,
      'schema_version': schemaVersion,
      'sensor_address': sensorAddress,
      'sensor_kind': sensorKind,
      'sensor_model': sensorModel,
      'session_id': sessionId,
      'unit': unit,
      'values': values,
      'wall_time_utc': wallTimeUtc,
    };
    final keys = fields.keys.toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_encode(fields[key])}').join(',')}}';
  }

  String get payloadHash =>
      sha256.convert(utf8.encode(canonicalJson)).toString();

  CanonicalEvent withClock(DateTime instant) {
    final utc = instant.toUtc();
    return CanonicalEvent(
      eventId: eventId,
      deviceId: deviceId,
      sessionId: sessionId,
      sensorAddress: sensorAddress,
      sensorKind: sensorKind,
      sensorModel: sensorModel,
      measurementType: measurementType,
      unit: unit,
      monotonicUs: utc.microsecondsSinceEpoch,
      clockState: clockState,
      operatingState: operatingState,
      values: values,
      wallTimeUtc: zulu(utc),
    );
  }

  CanonicalEvent rebindDevice(String deviceId) {
    return CanonicalEvent(
      eventId: eventId,
      deviceId: deviceId,
      sessionId: sessionId,
      sensorAddress: sensorAddress,
      sensorKind: sensorKind,
      sensorModel: sensorModel,
      measurementType: measurementType,
      unit: unit,
      monotonicUs: monotonicUs,
      clockState: clockState,
      operatingState: operatingState,
      values: values,
      wallTimeUtc: wallTimeUtc,
    );
  }
}

String _encode(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is bool || value is String) {
    return jsonEncode(value);
  }
  if (value is int) {
    return value.toString();
  }
  if (value is double) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(4);
  }
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_encode(value[key])}').join(',')}}';
  }
  if (value is List) {
    return '[${value.map(_encode).join(',')}]';
  }
  return jsonEncode(value);
}

String zulu(DateTime time) {
  final utc = time.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
}

String pathToken(String raw) {
  final cleaned = raw.replaceAll(RegExp('[^A-Za-z0-9._-]'), '-');
  return cleaned.isEmpty ? 'unknown' : cleaned;
}
