import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/ble/device_manager.dart';
import 'package:bylwapp/models/health_record.dart';
import 'package:bylwapp/ui/mini_chart.dart';

class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({
    super.key,
    required this.title,
    required this.records,
    this.address,
    this.devices,
  });

  final String title;
  final String? address;
  final List<LocalRecord> records;
  final BleDeviceManager? devices;

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  @override
  void initState() {
    super.initState();
    widget.devices?.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.devices?.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final devices = widget.devices;
    final address = widget.address;
    final live = address == null
        ? const <HealthMeasurement>[]
        : (devices?.recentByAddress[address] ?? const <HealthMeasurement>[]);
    final current = live.isEmpty ? null : live.first;
    final linked =
        address != null &&
        devices?.device?.address.toUpperCase() == address.toUpperCase();
    final phase = linked ? _phaseText(devices!.phase) : '未连接';
    final chart = [
      for (final measurement in live.reversed) _primary(measurement),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(phase, style: Theme.of(context).textTheme.titleMedium),
          if (current != null) ...[
            const SizedBox(height: 8),
            Text(
              summarize(current),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(_detailLine(current)),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(live.isEmpty ? '还没有这次连接的读数' : '最近 ${live.length} 条实时读数'),
                  MiniChart(
                    values: chart,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
          for (final measurement in live)
            ListTile(
              title: Text(summarize(measurement)),
              subtitle: Text(_clock(measurement.recordedAt)),
            ),
          if (widget.records.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('已保存的历史'),
            for (final record in widget.records)
              ListTile(
                title: Text(summarize(record.measurement)),
                subtitle: Text(_clock(record.measurement.recordedAt)),
              ),
          ],
        ],
      ),
    );
  }
}

String _phaseText(BleLinkPhase phase) {
  switch (phase) {
    case BleLinkPhase.connecting:
      return '连接中';
    case BleLinkPhase.connected:
      return '已连接';
    case BleLinkPhase.disconnected:
      return '已断开';
  }
}

String _detailLine(HealthMeasurement measurement) {
  final contact = measurement.values['sensor_contact'];
  final worn = switch (contact) {
    'detected' => '已接触',
    'not_detected' => '未接触',
    _ => null,
  };
  final clock = _clock(measurement.recordedAt);
  return worn == null ? clock : '$worn · $clock';
}

String _clock(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

double _primary(HealthMeasurement measurement) {
  final values = measurement.values;
  for (final key in [
    'systolic',
    'bpm',
    'spo2',
    'celsius',
    'steps',
    'duration_min',
    'stress',
    'hrv_ms',
  ]) {
    final value = values[key];
    if (value is num) return value.toDouble();
  }
  return 0;
}
