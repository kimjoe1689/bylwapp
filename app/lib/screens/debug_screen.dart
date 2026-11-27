import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/settings/settings_store.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key, required this.ble, this.prefs});

  final BleClient ble;
  final CollectorPrefs? prefs;

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final List<BleTrace> _rows = [];
  StreamSubscription<BleTrace>? _sub;
  late final TextEditingController _id = TextEditingController(
    text: widget.prefs?.collectorId ?? '',
  );
  late final TextEditingController _token = TextEditingController(
    text: widget.prefs?.deviceToken ?? '',
  );

  @override
  void initState() {
    super.initState();
    _sub = widget.ble.traces.listen((trace) {
      if (!mounted) return;
      setState(() {
        _rows.insert(0, trace);
        if (_rows.length > 200) {
          _rows.removeLast();
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _id.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = widget.prefs;
    return Scaffold(
      appBar: AppBar(title: const Text('蓝牙调试')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('这里显示每个特征的原始收发字节，方便真机对接。没有硬件时列表为空。'),
          if (prefs != null) ...[
            TextField(
              controller: _id,
              decoration: const InputDecoration(labelText: '采集端 ID'),
              onChanged: (value) => prefs.collectorId = value,
            ),
            TextField(
              controller: _token,
              decoration: const InputDecoration(labelText: '设备令牌'),
              onChanged: (value) => prefs.deviceToken = value,
            ),
            SwitchListTile(
              title: const Text('模拟断网'),
              value: prefs.faultNetworkDown,
              onChanged: (value) =>
                  setState(() => prefs.faultNetworkDown = value),
            ),
            SwitchListTile(
              title: const Text('模拟提交后超时'),
              value: prefs.faultTimeoutAfterCommit,
              onChanged: (value) =>
                  setState(() => prefs.faultTimeoutAfterCommit = value),
            ),
            SwitchListTile(
              title: const Text('模拟时钟异常'),
              value: prefs.faultClockSkew,
              onChanged: (value) =>
                  setState(() => prefs.faultClockSkew = value),
            ),
          ],
          for (final row in _rows)
            ListTile(
              title: Text(
                '${row.direction.toUpperCase()} ${row.characteristicUuid}',
              ),
              subtitle: Text(row.hex),
            ),
        ],
      ),
    );
  }
}
