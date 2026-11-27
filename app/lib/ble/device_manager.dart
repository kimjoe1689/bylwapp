import 'package:flutter/foundation.dart';

import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/ble/driver_registry.dart';
import 'package:bylwapp/ble/persist_gate.dart';
import 'package:bylwapp/models/health_record.dart';

/// Connection and live readings shared by every tab.
class BleDeviceManager extends ChangeNotifier {
  BleLinkPhase phase = BleLinkPhase.disconnected;
  BleScanHit? device;
  final PersistGate gate = PersistGate();
  final Map<String, HealthMeasurement> latestByKind = {};
  final Map<String, HealthMeasurement> latestByType = {};
  final Map<String, List<HealthMeasurement>> recentByAddress = {};

  void applyLink(BleLink link) {
    phase = link.phase;
    if (link.address != null && link.address!.isNotEmpty) {
      device = BleScanHit(
        name: link.name ?? device?.name ?? '设备',
        address: link.address!,
        rssi: device?.rssi ?? 0,
        driverId: link.driverId ?? device?.driverId,
      );
    }
    notifyListeners();
  }

  void addReading(String kind, String address, HealthMeasurement measurement) {
    latestByKind[kind] = measurement;
    latestByType[measurement.type] = measurement;
    final recent = recentByAddress.putIfAbsent(address, () => []);
    recent.insert(0, measurement);
    if (recent.length > 60) {
      recent.removeLast();
    }
    notifyListeners();
  }

  bool isConnectedTo(String address) {
    return phase == BleLinkPhase.connected &&
        device?.address.toUpperCase() == address.toUpperCase();
  }

  bool tracksKind(String kind) {
    return driverById(device?.driverId)?.kind == kind;
  }

  String phaseLabel(String kind) {
    if (!tracksKind(kind) || device == null) {
      return '未连接';
    }
    switch (phase) {
      case BleLinkPhase.connecting:
        return '连接中';
      case BleLinkPhase.connected:
        return '已连接';
      case BleLinkPhase.disconnected:
        return '已断开';
    }
  }
}
