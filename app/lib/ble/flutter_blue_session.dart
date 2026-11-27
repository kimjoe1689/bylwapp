import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/ble/blood_pressure/bp_driver.dart';
import 'package:bylwapp/ble/bytes.dart';
import 'package:bylwapp/ble/driver_registry.dart';
import 'package:bylwapp/ble/ring/ring_driver.dart';
import 'package:bylwapp/ble/ring/ring_packet.dart';
import 'package:bylwapp/ble/ring/ring_sync.dart';
import 'package:bylwapp/ble/uuids.dart';
import 'package:bylwapp/models/health_record.dart';

/// flutter_blue_plus adapter.
///
/// TODO(hardware): connection stability, indication versus notification,
/// MTU, bonding, and the YE680B / H303 / R09 / R05 quirks below are not
/// verified. There is no radio in this environment. Parsers are covered by
/// unit tests with sample packets.
class FlutterBlueSession implements BleClient {
  final StreamController<List<BleScanHit>> _hits =
      StreamController<List<BleScanHit>>.broadcast();
  final StreamController<BleTrace> _traces =
      StreamController<BleTrace>.broadcast();

  @override
  Stream<BleTrace> get traces => _traces.stream;
  StreamSubscription<List<ScanResult>>? _scanSub;
  final List<StreamSubscription<List<int>>> _valueSubs = [];
  List<BluetoothService> _services = [];
  BluetoothDevice? _device;
  String _connectedName = '';
  void Function(HealthMeasurement measurement)? _onMeasurement;
  final BigDataAssembler _assembler = BigDataAssembler();
  final List<List<int>> _inbox = [];
  Completer<List<int>>? _waiter;
  bool _syncing = false;

  @override
  Stream<List<BleScanHit>> get scanHits => _hits.stream;

  @override
  Future<void> startScan() async {
    // A combined service filter would hide devices that advertise only one profile.
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      final hits = <BleScanHit>[];
      for (final result in results) {
        final name = result.advertisementData.advName;
        final services = result.advertisementData.serviceUuids
            .map((guid) => guid.str128)
            .toList();
        final driver = matchDriver(
          advertisedName: name,
          serviceUuids: services,
        );
        hits.add(
          BleScanHit(
            name: name.isEmpty ? '未命名设备' : name,
            address: result.device.remoteId.str,
            rssi: result.rssi,
            driverId: driver?.id,
          ),
        );
      }
      if (!_hits.isClosed) {
        _hits.add(hits);
      }
    });
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
  }

  @override
  Future<void> connect({
    required BleScanHit hit,
    required void Function(HealthMeasurement measurement) onMeasurement,
  }) async {
    final driver = driverById(hit.driverId);
    if (driver == null) {
      throw StateError('无法识别这台设备的协议');
    }
    await disconnect();
    final device = BluetoothDevice.fromId(hit.address);
    // Personal / educational use of flutter_blue_plus 2.x. Commercial apps need License.commercial.
    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 20),
    );
    _services = await device.discoverServices();
    _device = device;
    _connectedName = hit.name;
    _onMeasurement = onMeasurement;
    _assembler.reset();
    for (final watch in driver.watches) {
      final characteristic = _find(watch.serviceUuid, watch.characteristicUuid);
      if (characteristic == null) {
        continue;
      }
      final forceIndications = watch.indicate && !kIsWeb && Platform.isAndroid;
      await characteristic.setNotifyValue(
        true,
        forceIndications: forceIndications,
      );
      final sub = characteristic.onValueReceived.listen((value) {
        _trace('rx', watch.characteristicUuid, value);
        _onValue(watch.characteristicUuid, value);
      });
      _valueSubs.add(sub);
      device.cancelWhenDisconnected(sub);
    }
  }

  @override
  Future<int> syncConnected({required bool temperatureLoggingEnabled}) async {
    final device = _device;
    if (device == null) {
      throw StateError('还没有连接设备');
    }
    final driver = matchDriver(
      advertisedName: _connectedName,
      serviceUuids: const [],
    );
    if (driver is BloodPressureDriver) {
      await _writeClock(driver);
      return 0;
    }
    if (driver is! YawellRingDriver) {
      // The standard heart-rate profile has no history channel.
      return 0;
    }
    return _syncRing(
      YawellRingDriver().supportsTemperature(_connectedName),
      temperatureLoggingEnabled: temperatureLoggingEnabled,
    );
  }

  @override
  Future<void> disconnect() async {
    for (final sub in _valueSubs) {
      await sub.cancel();
    }
    _valueSubs.clear();
    final device = _device;
    _device = null;
    _services = [];
    _onMeasurement = null;
    if (device != null) {
      await device.disconnect();
    }
  }

  void _trace(String direction, String characteristicUuid, List<int> bytes) {
    if (!_traces.isClosed) {
      _traces.add(
        BleTrace(
          at: DateTime.now().toUtc(),
          direction: direction,
          characteristicUuid: characteristicUuid,
          bytes: List<int>.from(bytes),
        ),
      );
    }
  }

  void _onValue(String characteristicUuid, List<int> value) {
    List<int>? packet = value;
    if (normalizeUuid(characteristicUuid) == ringNotifyV2Uuid) {
      packet = _assembler.add(value);
      if (packet == null) {
        return;
      }
    }
    if (_syncing) {
      _enqueue(packet);
      return;
    }
    final driver = matchDriver(
      advertisedName: _connectedName,
      serviceUuids: const [],
    );
    if (driver == null) {
      return;
    }
    final measurements = driver.parse(
      characteristicUuid,
      packet,
      now: DateTime.now().toUtc(),
    );
    for (final measurement in measurements) {
      _onMeasurement?.call(measurement);
    }
  }

  Future<void> _writeClock(BloodPressureDriver driver) async {
    final now = DateTime.now().toUtc();
    for (final write in driver.timeSync(now)) {
      final characteristic = _find(write.serviceUuid, write.characteristicUuid);
      if (characteristic == null) {
        continue;
      }
      _trace('tx', write.characteristicUuid, write.bytes);
      await characteristic.write(write.bytes);
      return;
    }
    throw StateError('这台血压计没有暴露 0x2A08 或 0x2A2B，无法对时');
  }

  Future<int> _syncRing(
    bool temperatureCapable, {
    required bool temperatureLoggingEnabled,
  }) async {
    final cursor = RingSyncCursor(
      now: DateTime.now().toUtc(),
      temperatureCapable: temperatureCapable,
      temperatureLoggingEnabled: temperatureLoggingEnabled,
    );
    _syncing = true;
    _inbox.clear();
    var saved = 0;
    try {
      while (!cursor.isDone) {
        final command = cursor.nextCommand();
        if (command == null) {
          break;
        }
        final characteristic = _find(
          command.serviceUuid,
          command.characteristicUuid,
        );
        if (characteristic == null) {
          throw StateError('缺少特征 ${command.characteristicUuid}');
        }
        _trace('tx', command.characteristicUuid, command.bytes);
        await characteristic.write(
          command.bytes,
          allowLongWrite: command.bytes.length > 20,
        );
        final deadline = DateTime.now().add(const Duration(seconds: 8));
        while (cursor.awaitingMore) {
          final remaining = deadline.difference(DateTime.now());
          if (remaining.isNegative) {
            // TODO(hardware): the ring sometimes never answers; Gadgetbridge aborts after 30s.
            throw TimeoutException('等待戒指响应超时（${command.label}）');
          }
          final packet = await _nextPacket(remaining);
          final measurements = cursor.consume(packet);
          saved += measurements.length;
          for (final measurement in measurements) {
            _onMeasurement?.call(measurement);
          }
        }
      }
    } finally {
      _syncing = false;
    }
    return saved;
  }

  BluetoothCharacteristic? _find(
    String serviceUuid,
    String characteristicUuid,
  ) {
    final serviceId = normalizeUuid(serviceUuid);
    final characteristicId = normalizeUuid(characteristicUuid);
    for (final service in _services) {
      if (service.uuid.str128 != serviceId) {
        continue;
      }
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid.str128 == characteristicId) {
          return characteristic;
        }
      }
    }
    return null;
  }

  void _enqueue(List<int> packet) {
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      _waiter = null;
      waiter.complete(packet);
      return;
    }
    _inbox.add(packet);
  }

  Future<List<int>> _nextPacket(Duration timeout) async {
    if (_inbox.isNotEmpty) {
      return _inbox.removeAt(0);
    }
    final completer = Completer<List<int>>();
    _waiter = completer;
    try {
      return await completer.future.timeout(timeout);
    } finally {
      if (identical(_waiter, completer)) {
        _waiter = null;
      }
    }
  }
}
