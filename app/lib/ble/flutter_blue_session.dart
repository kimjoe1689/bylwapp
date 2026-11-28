import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/ble/blood_pressure/bp_driver.dart';
import 'package:bylwapp/ble/bylw_log.dart';
import 'package:bylwapp/ble/bytes.dart';
import 'package:bylwapp/ble/device_driver.dart';
import 'package:bylwapp/ble/driver_registry.dart';
import 'package:bylwapp/ble/ring/ring_actions.dart';
import 'package:bylwapp/ble/ring/ring_driver.dart';
import 'package:bylwapp/ble/ring/ring_parser.dart';
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
  final StreamController<BleLink> _links =
      StreamController<BleLink>.broadcast();

  @override
  Stream<BleTrace> get traces => _traces.stream;

  @override
  Stream<BleLink> get links => _links.stream;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<OnCharacteristicReceivedEvent>? _globalSub;
  final List<StreamSubscription<List<int>>> _valueSubs = [];
  final Set<String> _watched = {};
  List<BluetoothService> _services = [];
  BluetoothDevice? _device;
  HealthDeviceDriver? _driver;
  String _connectedName = '';
  String _connectedAddress = '';
  bool _wantConnected = false;
  bool _arming = false;
  bool _armAgain = false;
  String _lastRxKey = '';
  int _lastRxUs = 0;
  Timer? _ringResync;
  Timer? _ringKeepalive;
  bool _ringBusy = false;
  bool _measuringHr = false;
  final StreamController<RingNotice> _ringNotices =
      StreamController<RingNotice>.broadcast();
  final StreamController<RingSnapshot> _ringSnapshots =
      StreamController<RingSnapshot>.broadcast();
  RingSnapshot _ringSnapshot = const RingSnapshot();

  @override
  Stream<RingNotice> get ringNotices => _ringNotices.stream;

  @override
  RingSnapshot get ringSnapshot => _ringSnapshot;

  @override
  Stream<RingSnapshot> get ringSnapshots => _ringSnapshots.stream;

  void _publishRing(RingSnapshot next, {RingNotice? notice}) {
    _ringSnapshot = next;
    if (!_ringSnapshots.isClosed) _ringSnapshots.add(next);
    if (notice != null && !_ringNotices.isClosed) _ringNotices.add(notice);
  }

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
    final already =
        _wantConnected &&
        _device != null &&
        _connectedAddress.toUpperCase() == hit.address.toUpperCase() &&
        _device!.isConnected;
    if (already) {
      bylwLog('already connected ${hit.address}, skip reconnect');
      _onMeasurement = onMeasurement;
      _driver = driver;
      _emit(
        BleLinkPhase.connected,
        address: hit.address,
        name: hit.name,
        driverId: driver.id,
      );
      return;
    }
    await disconnect();
    _wantConnected = true;
    _driver = driver;
    _onMeasurement = onMeasurement;
    _connectedName = hit.name;
    _connectedAddress = hit.address;
    _assembler.reset();
    _emit(
      BleLinkPhase.connecting,
      address: hit.address,
      name: hit.name,
      driverId: driver.id,
    );
    final device = BluetoothDevice.fromId(hit.address);
    _device = device;
    await _connSub?.cancel();
    _connSub = device.connectionState.listen((state) {
      if (!identical(_device, device)) {
        return;
      }
      bylwLog('connectionState ${hit.address} $state');
      if (state == BluetoothConnectionState.connected) {
        _emit(
          BleLinkPhase.connected,
          address: hit.address,
          name: hit.name,
          driverId: driver.id,
        );
        _arm();
      } else if (state == BluetoothConnectionState.disconnected &&
          _wantConnected) {
        _emit(
          BleLinkPhase.disconnected,
          address: hit.address,
          name: hit.name,
          driverId: driver.id,
        );
      }
    });
    // Personal / educational use of flutter_blue_plus 2.x. Commercial apps need License.commercial.
    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 20),
    );
    await _arm();
  }

  @override
  Future<int> syncConnected({required bool temperatureLoggingEnabled}) async {
    final device = _device;
    if (device == null) {
      throw StateError('还没有连接设备');
    }
    final driver = _driver;
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
    final address = _connectedAddress;
    final name = _connectedName;
    final driverId = _driver?.id;
    _wantConnected = false;
    _ringResync?.cancel();
    _ringKeepalive?.cancel();
    _ringResync = null;
    _ringKeepalive = null;
    await _cancelChrSubs();
    await _connSub?.cancel();
    _connSub = null;
    final device = _device;
    _device = null;
    _services = [];
    _watched.clear();
    _driver = null;
    _onMeasurement = null;
    _connectedAddress = '';
    if (device != null) {
      try {
        await device.disconnect();
      } catch (error) {
        bylwLog('disconnect $error');
      }
    }
    if (address.isNotEmpty) {
      _emit(
        BleLinkPhase.disconnected,
        address: address,
        name: name,
        driverId: driverId,
      );
    }
  }

  Future<void> _arm() async {
    if (_arming) {
      _armAgain = true;
      return;
    }
    _arming = true;
    try {
      final device = _device;
      final driver = _driver;
      if (device == null || driver == null || !_wantConnected) {
        return;
      }
      bylwLog('discover ${device.remoteId.str}');
      final services = await device.discoverServices();
      if (!_wantConnected || !identical(_device, device)) {
        return;
      }
      _services = services;
      _watched
        ..clear()
        ..addAll(
          driver.watches.map(
            (watch) => normalizeUuid(watch.characteristicUuid),
          ),
        );
      _ensureGlobalRx();
      await _cancelChrSubs();
      for (final watch in driver.watches) {
        final characteristic = _find(
          watch.serviceUuid,
          watch.characteristicUuid,
        );
        if (characteristic == null) {
          bylwLog('missing ${watch.characteristicUuid}');
          continue;
        }
        final sub = characteristic.onValueReceived.listen(
          (value) => _handleRx(watch.characteristicUuid, value),
          onError: (Object error) => bylwLog('chr stream $error'),
        );
        _valueSubs.add(sub);
        final forceIndications =
            watch.indicate && !kIsWeb && Platform.isAndroid;
        bylwLog(
          'setNotify ${characteristic.uuid.str128} indicate=$forceIndications instance=${characteristic.instanceId}',
        );
        await characteristic.setNotifyValue(
          true,
          forceIndications: forceIndications,
        );
        bylwLog('setNotify ok ${characteristic.uuid.str128}');
      }
    } catch (error) {
      bylwLog('arm failed $error');
    } finally {
      _arming = false;
      final again = _armAgain;
      _armAgain = false;
      if (again) {
        await _arm();
      } else if (_driver is YawellRingDriver && _wantConnected) {
        unawaited(_ringBringUp());
      }
    }
  }

  Future<void> _ringBringUp() async {
    if (_ringBusy || _driver is! YawellRingDriver || !_wantConnected) {
      return;
    }
    _ringBusy = true;
    _ringResync?.cancel();
    _ringKeepalive?.cancel();
    try {
      await _ringStage('set-time', () async {
        await _writeRing(RingPacket.encodeDateTime(DateTime.now()), 'set-time');
        await _awaitCommand(RingPacket.cmdSetDateTime);
      });
      await _ringStage('battery', () async {
        await _writeRing(RingPacket.batteryRequest(), 'battery');
        final packet = await _awaitCommand(RingPacket.cmdBattery);
        final battery = packet == null ? null : parseBattery(packet);
        if (battery != null) {
          bylwLog(
            'stage battery percent=${battery.percent} charging=${battery.charging}',
          );
          _publishRing(
            _ringSnapshot.copyWith(
              batteryPercent: battery.percent,
              charging: battery.charging,
            ),
            notice: RingNotice(
              at: DateTime.now(),
              hex: '',
              label: '电量 ${battery.percent}%',
            ),
          );
        }
      });
      await _ringStage('realtime-hr', () async {
        await _writeRing(RingPacket.startRealtimeHeartRate(), 'realtime-hr');
        _measuringHr = true;
        _publishRing(_ringSnapshot.copyWith(measuring: true));
      });
      await _ringStage('history', () async {
        final saved = await _syncRing(
          (_driver as YawellRingDriver).supportsTemperature(_connectedName),
          temperatureLoggingEnabled: false,
        );
        bylwLog('stage history saved=$saved');
        _publishRing(
          _ringSnapshot.copyWith(historySyncedAt: DateTime.now()),
          notice: RingNotice(at: DateTime.now(), hex: '', label: '历史已同步'),
        );
      });
    } finally {
      _ringBusy = false;
    }
    if (!_wantConnected || _driver is! YawellRingDriver) {
      return;
    }
    _ringKeepalive = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_wantConnected || _syncing || _ringBusy || !_measuringHr) {
        return;
      }
      unawaited(
        _writeRing(RingPacket.continueRealtimeHeartRate(), 'hr-continue'),
      );
    });
    _ringResync = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_wantConnected && !_ringBusy) {
        unawaited(_ringBringUp());
      }
    });
  }

  Future<void> _ringStage(String name, Future<void> Function() body) async {
    bylwLog('stage $name start');
    try {
      await body();
      bylwLog('stage $name end');
    } catch (error) {
      bylwLog('stage $name skip $error');
    }
  }

  @override
  Future<RingActionResult> performRingAction(RingAction action) async {
    if (_driver is! YawellRingDriver || !_wantConnected) {
      return RingActionResult.unsupported;
    }
    try {
      switch (action.id) {
        case 'find':
          await _writeRing(RingPacket.findRing(), 'find');
          return RingActionResult.ok;
        case 'time':
          await _writeRing(
            RingPacket.encodeDateTime(DateTime.now()),
            'set-time',
          );
          return RingActionResult.ok;
        case 'history':
          if (_ringBusy) {
            return const RingActionResult(supported: true, message: '正在同步');
          }
          unawaited(_ringBringUp());
          return const RingActionResult(supported: true, message: '已开始同步');
        case 'battery':
          await _writeRing(RingPacket.batteryRequest(), 'battery');
          final packet = await _awaitCommand(RingPacket.cmdBattery);
          final battery = packet == null ? null : parseBattery(packet);
          if (battery == null) return RingActionResult.unsupported;
          _publishRing(
            _ringSnapshot.copyWith(
              batteryPercent: battery.percent,
              charging: battery.charging,
            ),
            notice: RingNotice(
              at: DateTime.now(),
              hex: '',
              label: '电量 ${battery.percent}%',
            ),
          );
          return RingActionResult(
            supported: true,
            message: '电量 ${battery.percent}%',
            batteryPercent: battery.percent,
            charging: battery.charging,
          );
        case 'power':
          await _writeRing(RingPacket.powerOff(), 'power-off');
          return RingActionResult.ok;
        case 'factory':
          await _writeRing(RingPacket.factoryReset(), 'factory-reset');
          return RingActionResult.ok;
        case 'live-start':
          await _writeRing(RingPacket.startRealtimeHeartRate(), 'realtime-hr');
          _measuringHr = true;
          _publishRing(_ringSnapshot.copyWith(measuring: true));
          return RingActionResult.ok;
        case 'live-stop':
          await _writeRing(RingPacket.stopRealtimeHeartRate(), 'stop-hr');
          _measuringHr = false;
          _publishRing(_ringSnapshot.copyWith(measuring: false));
          return RingActionResult.ok;
        case 'auto-read':
          return await _auto(action, write: false);
        case 'auto-write':
          return await _auto(action, write: true);
        default:
          return RingActionResult.unsupported;
      }
    } catch (error) {
      bylwLog('ring action ${action.id} skip $error');
      return RingActionResult.unsupported;
    }
  }

  Future<RingActionResult> _auto(
    RingAction action, {
    required bool write,
  }) async {
    final command = switch (action.metric) {
      'heart_rate' => RingPacket.cmdAutoHeartRate,
      'spo2' => RingPacket.cmdAutoSpo2,
      'stress' => RingPacket.cmdAutoStress,
      _ => null,
    };
    if (command == null) return RingActionResult.unsupported;
    if (write) {
      await _writeRing(
        RingPacket.writeAuto(
          command,
          enabled: action.enabled ?? false,
          minutes: action.minutes ?? 30,
        ),
        'auto-${action.metric}',
      );
      final ack = await _awaitCommand(command);
      if (ack == null) return RingActionResult.unsupported;
      return const RingActionResult(supported: true, message: '已设置');
    }
    await _writeRing(
      RingPacket.readAuto(command),
      'read-auto-${action.metric}',
    );
    final packet = await _awaitCommand(command);
    if (packet == null || packet.length < 3) {
      return RingActionResult.unsupported;
    }
    return RingActionResult(
      supported: true,
      enabled: (packet[1] & 0xff) != 0,
      minutes: packet[2] & 0xff,
      message: '已读取',
    );
  }

  Future<void> _writeRing(
    List<int> bytes,
    String label, {
    String serviceUuid = ringServiceV1Uuid,
    String characteristicUuid = ringWriteUuid,
  }) async {
    final characteristic = _find(serviceUuid, characteristicUuid);
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    if (characteristic == null) {
      bylwLog('tx $label missing $characteristicUuid');
      return;
    }
    bylwLog('tx $label $hex');
    _trace('tx', characteristicUuid, bytes);
    try {
      await characteristic.write(bytes, withoutResponse: bytes.length <= 20);
    } catch (error) {
      bylwLog('tx $label without-response failed $error');
      await characteristic.write(bytes, withoutResponse: false);
    }
  }

  Future<List<int>?> _awaitCommand(int command) async {
    _syncing = true;
    _inbox.clear();
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (true) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining.isNegative) {
          return null;
        }
        final packet = await _nextPacket(remaining);
        if (packet.isNotEmpty && (packet[0] & 0xff) == command) {
          return packet;
        }
      }
    } on TimeoutException {
      return null;
    } finally {
      _syncing = false;
    }
  }

  void _ensureGlobalRx() {
    _globalSub ??= FlutterBluePlus.events.onCharacteristicReceived.listen((
      event,
    ) {
      if (_connectedAddress.isEmpty) {
        return;
      }
      if (event.device.remoteId.str.toUpperCase() !=
          _connectedAddress.toUpperCase()) {
        return;
      }
      final uuid = event.characteristic.uuid.str128;
      if (!_watched.contains(uuid)) {
        return;
      }
      _handleRx(uuid, event.value);
    }, onError: (Object error) => bylwLog('event stream $error'));
  }

  Future<void> _cancelChrSubs() async {
    for (final sub in _valueSubs) {
      await sub.cancel();
    }
    _valueSubs.clear();
  }

  void _emit(
    BleLinkPhase phase, {
    String? address,
    String? name,
    String? driverId,
  }) {
    if (_links.isClosed) {
      return;
    }
    _links.add(
      BleLink(phase: phase, address: address, name: name, driverId: driverId),
    );
  }

  void _handleRx(String characteristicUuid, List<int> value) {
    final key = '$characteristicUuid:${value.join(',')}';
    final now = DateTime.now().microsecondsSinceEpoch;
    if (key == _lastRxKey && now - _lastRxUs < 150000) {
      return;
    }
    _lastRxKey = key;
    _lastRxUs = now;
    final hex = value
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    bylwLog('rx $characteristicUuid $hex');
    _trace('rx', characteristicUuid, value);
    unawaited(
      _onValue(characteristicUuid, value).catchError((Object error) {
        bylwLog('parse failed $error raw=$hex');
      }),
    );
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

  Future<void> _onValue(String characteristicUuid, List<int> value) async {
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
    final driver = _driver;
    if (driver == null) {
      bylwLog('rx dropped, no active driver');
      return;
    }
    final measurements = driver.parse(
      characteristicUuid,
      packet,
      now: DateTime.now().toUtc(),
    );
    if (driver is YawellRingDriver && !_ringNotices.isClosed) {
      final label = ringNoticeLabel(packet);
      if (label != null) {
        final hex = packet
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(' ');
        _ringNotices.add(
          RingNotice(at: DateTime.now(), hex: hex, label: label),
        );
      }
    }
    for (final measurement in measurements) {
      await _deliver(measurement);
    }
  }

  Future<void> _deliver(HealthMeasurement measurement) async {
    final callback = _onMeasurement;
    if (callback == null) return;
    await Future<void>.sync(() => callback(measurement));
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
          bylwLog(
            'stage ${command.label} skip missing ${command.characteristicUuid}',
          );
          cursor.skipCurrent();
          continue;
        }
        final hex = command.bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(' ');
        bylwLog('tx ${command.label} $hex');
        _trace('tx', command.characteristicUuid, command.bytes);
        try {
          await characteristic.write(
            command.bytes,
            withoutResponse: command.bytes.length <= 20,
            allowLongWrite: command.bytes.length > 20,
          );
        } catch (error) {
          bylwLog('tx ${command.label} retry $error');
          await characteristic.write(
            command.bytes,
            allowLongWrite: command.bytes.length > 20,
          );
        }
        final deadline = DateTime.now().add(const Duration(seconds: 8));
        var timedOut = false;
        while (cursor.awaitingMore && !timedOut) {
          final remaining = deadline.difference(DateTime.now());
          if (remaining.isNegative) {
            bylwLog('stage ${command.label} skip timeout');
            cursor.skipCurrent();
            timedOut = true;
            break;
          }
          try {
            final packet = await _nextPacket(remaining);
            final measurements = cursor.consume(packet);
            saved += measurements.length;
            for (final measurement in measurements) {
              await _deliver(measurement);
            }
          } on TimeoutException {
            bylwLog('stage ${command.label} skip timeout');
            cursor.skipCurrent();
            timedOut = true;
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
