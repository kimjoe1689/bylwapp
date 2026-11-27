import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/ble/driver_registry.dart';
import 'package:bylwapp/ble/ring/ring_sync.dart';
import 'package:bylwapp/data/health_repository.dart';
import 'package:bylwapp/models/health_record.dart';
import 'package:bylwapp/screens/device_detail_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    required this.repository,
    required this.ble,
    this.onJournal,
    this.embedded = false,
  });

  final HealthRepository repository;
  final BleClient ble;
  final Future<void> Function(HealthMeasurement measurement, BleScanHit hit)?
  onJournal;
  final bool embedded;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  List<BleScanHit> _hits = const [];
  StreamSubscription<List<BleScanHit>>? _sub;
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );
  bool _scanning = false;
  BleScanHit? _connected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.ble.scanHits.listen((hits) {
      if (mounted) {
        setState(() => _hits = hits);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _spin.dispose();
    super.dispose();
  }

  Future<void> _toggleScan() async {
    if (_scanning) {
      await widget.ble.stopScan();
      _spin.stop();
      setState(() => _scanning = false);
      return;
    }
    setState(() => _scanning = true);
    _spin.repeat();
    try {
      await widget.ble.startScan();
    } catch (error) {
      _message('扫描失败：$error');
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  Future<void> _connect(BleScanHit hit) async {
    final driver = driverById(hit.driverId);
    if (driver == null) {
      _message('这台设备不在支持的三种协议里');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.ble.stopScan();
      await widget.ble.connect(
        hit: hit,
        onMeasurement: (measurement) async {
          await widget.repository.upsertDevice(
            HealthDevice(
              name: hit.name,
              kind: driver.kind,
              address: hit.address,
              model: driver.targetModel,
            ),
          );
          await widget.repository.insertMeasurement(hit.address, measurement);
          await widget.onJournal?.call(measurement, hit);
        },
      );
      if (mounted) {
        setState(() {
          _scanning = false;
          _connected = hit;
        });
      }
      _message('已连接 ${hit.name}');
    } catch (error) {
      _message('连接失败：$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _sync() async {
    final hit = _connected;
    final driver = driverById(hit?.driverId);
    if (hit == null || driver == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final count = await widget.ble.syncConnected(
        temperatureLoggingEnabled: false,
      );
      _message(
        driver.id == 'heart_rate' ? '心率带只推送实时数据，没有历史通道' : '同步解析了 $count 条',
      );
    } catch (error) {
      _message('同步失败：$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _message(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final connected = _connected;
    final temperature =
        connected != null && ringNameSupportsTemperature(connected.name);
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('设备', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('1. 打开戒指、心率带或血压计的蓝牙。\n2. 点下面的扫描。\n3. 在卡片上连接，再进入详情看历史。'),
        const SizedBox(height: 12),
        Center(
          child: RotationTransition(
            turns: _spin,
            child: Icon(
              Icons.radar,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _toggleScan,
          child: Text(_scanning ? '停止扫描' : '开始扫描'),
        ),
        if (connected != null) ...[
          const SizedBox(height: 12),
          Text('已连接 ${connected.name}'),
          OutlinedButton(
            onPressed: _busy ? null : _sync,
            child: const Text('读取设备历史'),
          ),
          if (temperature) const Text('R09 / R05 会先尝试打开体温记录。没有实机时这里不会出现读数。'),
        ],
        const SizedBox(height: 12),
        if (_hits.isEmpty)
          const Card(
            child: ListTile(
              title: Text('附近还没有设备'),
              subtitle: Text('扫描后，戒指、心率带和血压计会以卡片出现。'),
            ),
          )
        else
          for (final hit in _hits)
            Card(
              child: ListTile(
                leading: const Icon(Icons.bluetooth_connected),
                title: Text(hit.name),
                subtitle: Text(
                  '${hit.address} · ${hit.rssi} dBm · ${driverById(hit.driverId)?.displayName ?? '未识别'}',
                ),
                trailing: FilledButton.tonal(
                  onPressed: _busy || hit.driverId == null
                      ? null
                      : () => _connect(hit),
                  child: const Text('连接'),
                ),
                onTap: () async {
                  final all = await widget.repository.listRecent();
                  final mine = all
                      .where((record) => record.device.address == hit.address)
                      .toList();
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          DeviceDetailScreen(title: hit.name, records: mine),
                    ),
                  );
                },
              ),
            ),
      ],
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('设备')),
      body: content,
    );
  }
}
