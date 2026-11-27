import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/ble/driver_registry.dart';
import 'package:bylwapp/ble/ring/ring_sync.dart';
import 'package:bylwapp/data/health_repository.dart';
import 'package:bylwapp/models/health_record.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    required this.repository,
    required this.ble,
    this.onJournal,
  });

  final HealthRepository repository;
  final BleClient ble;
  final Future<void> Function(HealthMeasurement measurement, BleScanHit hit)?
  onJournal;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<BleScanHit> _hits = const [];
  StreamSubscription<List<BleScanHit>>? _sub;
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
    super.dispose();
  }

  Future<void> _toggleScan() async {
    if (_scanning) {
      await widget.ble.stopScan();
      setState(() => _scanning = false);
      return;
    }
    setState(() => _scanning = true);
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
    return Scaffold(
      appBar: AppBar(title: const Text('扫描设备')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '目标设备：鱼跃 YE680B 血压计、迈金 H303 心率带、Colmi R09 / Yawell R05 戒指。',
          ),
          const SizedBox(height: 8),
          const Text(
            '没有真机时无法完成蓝牙连接。血压 SFLOAT、心率标志位和戒指校验都由单元测试覆盖。体温记录必须先打开，而且只有 R09 / R05 支持。',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _toggleScan,
            child: Text(_scanning ? '停止扫描' : '开始扫描'),
          ),
          if (connected != null) ...[
            const SizedBox(height: 12),
            Text('已连接 ${connected.name}'),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _sync,
              child: const Text('同步'),
            ),
            if (temperature)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('同步会先写入体温记录开关。戒指开始记录之前，历史里不会有体温。这一步需要实机确认。'),
              ),
          ],
          const SizedBox(height: 16),
          if (_hits.isEmpty)
            const Text('尚未发现设备。')
          else
            for (final hit in _hits)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(hit.name),
                subtitle: Text(
                  '${hit.address} · ${hit.rssi} dBm · ${driverById(hit.driverId)?.displayName ?? '未识别'}',
                ),
                trailing: TextButton(
                  onPressed: _busy || hit.driverId == null
                      ? null
                      : () => _connect(hit),
                  child: const Text('连接'),
                ),
              ),
        ],
      ),
    );
  }
}
