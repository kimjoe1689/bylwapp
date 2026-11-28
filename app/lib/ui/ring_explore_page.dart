import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'package:bylwapp/ble/ring/ring_trace.dart';

class RingExplorePage extends StatefulWidget {
  const RingExplorePage({super.key, required this.traces});

  final RingTraceStore traces;

  @override
  State<RingExplorePage> createState() => _RingExplorePageState();
}

class _RingExplorePageState extends State<RingExplorePage> {
  List<RingTraceGroup> _groups = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final groups = await widget.traces.groups();
    if (mounted) setState(() => _groups = groups);
  }

  Future<void> _export(String kind) async {
    final rows = await widget.traces.recent();
    final text = kind == 'csv' ? ringTracesToCsv(rows) : ringTracesToJson(rows);
    final file = File(
      p.join(p.dirname(await getDatabasesPath()), 'ring-events.$kind'),
    );
    await file.writeAsString(text);
    await Share.shareXFiles([XFile(file.path)], subject: '戒指事件 $kind');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('事件探索'),
        actions: [
          IconButton(
            onPressed: () => _export('json'),
            icon: const Icon(Icons.data_object),
            tooltip: '导出 JSON',
          ),
          IconButton(
            onPressed: () => _export('csv'),
            icon: const Icon(Icons.table_chart_outlined),
            tooltip: '导出 CSV',
          ),
        ],
      ),
      body: _groups.isEmpty
          ? const Center(child: Text('还没有记下任何收发包。'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: _groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final group = _groups[index];
                final cmd =
                    group.cmd?.toRadixString(16).padLeft(2, '0') ?? '--';
                final sub =
                    group.sub?.toRadixString(16).padLeft(2, '0') ?? '--';
                return Card(
                  child: ListTile(
                    title: Text('0x$cmd / 0x$sub    ${group.count} 次'),
                    subtitle: Text(
                      '${group.label}\n${group.sampleHex}\n${_when(group.first)} → ${_when(group.last)}',
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }

  String _when(DateTime time) {
    final wall = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(wall.hour)}:${two(wall.minute)}:${two(wall.second)}';
  }
}
