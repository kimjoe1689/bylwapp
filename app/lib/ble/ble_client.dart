import 'dart:async';

import 'package:bylwapp/models/health_record.dart';

class BleTrace {
  const BleTrace({
    required this.at,
    required this.direction,
    required this.characteristicUuid,
    required this.bytes,
  });

  final DateTime at;
  final String direction;
  final String characteristicUuid;
  final List<int> bytes;

  String get hex =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}

class BleScanHit {
  const BleScanHit({
    required this.name,
    required this.address,
    required this.rssi,
    this.driverId,
  });

  final String name;
  final String address;
  final int rssi;
  final String? driverId;
}

abstract class BleClient {
  Stream<List<BleScanHit>> get scanHits;

  Stream<BleTrace> get traces;

  Future<void> startScan();

  Future<void> stopScan();

  Future<void> connect({
    required BleScanHit hit,
    required void Function(HealthMeasurement measurement) onMeasurement,
  });

  /// Pulls history or writes the clock, depending on the connected driver.
  /// Returns how many measurements were parsed. Hardware behavior is unverified.
  Future<int> syncConnected({required bool temperatureLoggingEnabled});

  Future<void> disconnect();
}

class FakeBleClient implements BleClient {
  FakeBleClient({List<BleScanHit>? hits}) : _hits = hits ?? const [];

  final List<BleScanHit> _hits;
  final StreamController<List<BleScanHit>> _controller =
      StreamController<List<BleScanHit>>.broadcast();
  final StreamController<BleTrace> _traces =
      StreamController<BleTrace>.broadcast();

  @override
  Stream<List<BleScanHit>> get scanHits => _controller.stream;

  @override
  Stream<BleTrace> get traces => _traces.stream;

  @override
  Future<void> startScan() async {
    _controller.add(_hits);
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect({
    required BleScanHit hit,
    required void Function(HealthMeasurement measurement) onMeasurement,
  }) async {}

  @override
  Future<int> syncConnected({required bool temperatureLoggingEnabled}) async =>
      0;

  @override
  Future<void> disconnect() async {}
}
