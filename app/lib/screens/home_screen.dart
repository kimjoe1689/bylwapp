import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/api/server_client.dart';
import 'package:bylwapp/data/health_repository.dart';
import 'package:bylwapp/models/health_record.dart';
import 'package:bylwapp/screens/scan_screen.dart';
import 'package:bylwapp/screens/settings_screen.dart';
import 'package:bylwapp/settings/settings_store.dart';
import 'package:bylwapp/ble/ble_client.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.settings,
    required this.ble,
    this.clientFactory,
  });

  final HealthRepository repository;
  final SettingsStore settings;
  final BleClient ble;
  final ServerClient Function(String baseUrl)? clientFactory;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<LocalRecord> _records = const [];
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final records = await widget.repository.listRecent();
    if (mounted) {
      setState(() => _records = records);
    }
  }

  Future<void> _upload() async {
    setState(() => _uploading = true);
    try {
      final pending = await widget.repository.listUnsynced();
      if (pending.isEmpty) {
        _snack('没有待上传的记录');
        return;
      }
      final baseUrl = await widget.settings.getServerBaseUrl();
      final client =
          (widget.clientFactory ?? (url) => ServerClient(baseUrl: url))(
            baseUrl,
          );
      final groups = <String, List<LocalRecord>>{};
      for (final record in pending) {
        groups.putIfAbsent(record.device.address, () => []).add(record);
      }
      var inserted = 0;
      for (final group in groups.values) {
        final ack = await client.upload(
          device: group.first.device,
          measurements: group.map((record) => record.measurement).toList(),
        );
        inserted += ack.inserted;
        await widget.repository.markSynced(
          group.map((record) => record.id!).toList(),
        );
      }
      await _reload();
      _snack('已上传 $inserted 条');
    } catch (error) {
      _snack('上传失败：$error');
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  void _snack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('bylwapp'),
        actions: [
          IconButton(
            tooltip: '扫描设备',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => ScanScreen(
                    repository: widget.repository,
                    ble: widget.ble,
                  ),
                ),
              );
              await _reload();
            },
            icon: const Icon(Icons.bluetooth_searching),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) =>
                      SettingsScreen(settings: widget.settings),
                ),
              );
            },
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: _records.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '还没有测量记录。连接血压计、心率带或戒指后，数据会记在这台设备上。',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              itemCount: _records.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final record = _records[index];
                final when = record.measurement.recordedAt.toLocal();
                final stamp =
                    '${when.year}-${_two(when.month)}-${_two(when.day)} ${_two(when.hour)}:${_two(when.minute)}';
                return ListTile(
                  title: Text(
                    '${measurementLabel(record.measurement.type)}  ${summarize(record.measurement)}',
                  ),
                  subtitle: Text(
                    '${record.device.name} · $stamp${record.synced ? ' · 已上传' : ''}',
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _uploading ? null : _upload,
            child: Text(_uploading ? '上传中…' : '上传到服务器'),
          ),
        ),
      ),
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');
