import 'dart:async';

import 'package:bylwapp/ble/ring/ring_actions.dart';
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

enum BleLinkPhase { disconnected, connecting, connected }

class BleLink {
  const BleLink({required this.phase, this.address, this.name, this.driverId});

  final BleLinkPhase phase;
  final String? address;
  final String? name;
  final String? driverId;
}

abstract class BleClient {
  Stream<List<BleScanHit>> get scanHits;

  Stream<BleTrace> get traces;

  Stream<BleLink> get links;

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

  /// Ring-only controls. Other devices return [RingActionResult.unsupported].
  Future<RingActionResult> performRingAction(RingAction action);

  Stream<RingNotice> get ringNotices;

  RingSnapshot get ringSnapshot;

  Stream<RingSnapshot> get ringSnapshots;

  Stream<String> get gestureRx;

  /// How many days before today the next history sync should request.
  void setRingHistoryDepth(int days);
}

class FakeBleClient implements BleClient {
  FakeBleClient({List<BleScanHit>? hits}) : _hits = hits ?? const [];

  final List<BleScanHit> _hits;
  final StreamController<List<BleScanHit>> _controller =
      StreamController<List<BleScanHit>>.broadcast();
  final StreamController<BleTrace> _traces =
      StreamController<BleTrace>.broadcast();
  final StreamController<BleLink> _links =
      StreamController<BleLink>.broadcast();
  final StreamController<RingNotice> _ringNotices =
      StreamController<RingNotice>.broadcast();
  final StreamController<RingSnapshot> _ringSnapshots =
      StreamController<RingSnapshot>.broadcast();
  final StreamController<String> _gestureRx =
      StreamController<String>.broadcast();

  @override
  Stream<List<BleScanHit>> get scanHits => _controller.stream;

  @override
  Stream<BleTrace> get traces => _traces.stream;

  @override
  Stream<BleLink> get links => _links.stream;

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

  @override
  Future<RingActionResult> performRingAction(RingAction action) async =>
      RingActionResult.unsupported;

  @override
  Stream<RingNotice> get ringNotices => _ringNotices.stream;

  @override
  RingSnapshot get ringSnapshot => const RingSnapshot();

  @override
  Stream<RingSnapshot> get ringSnapshots => _ringSnapshots.stream;

  @override
  Stream<String> get gestureRx => _gestureRx.stream;

  @override
  void setRingHistoryDepth(int days) {}
}
