import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/api/server_client.dart';
import 'package:bylwapp/ble/device_manager.dart';
import 'package:bylwapp/models/health_record.dart';
import 'package:bylwapp/screens/study_screens.dart';
import 'package:bylwapp/settings/settings_store.dart';
import 'package:bylwapp/sync/sync_worker.dart';
import 'package:bylwapp/ui/mini_chart.dart';

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({
    super.key,
    required this.records,
    required this.demo,
    required this.settings,
    this.study,
    this.prefs,
    this.clientFactory,
    this.onChanged,
    this.devices,
  });

  final List<LocalRecord> records;
  final bool demo;
  final SettingsStore settings;
  final StudyBundle? study;
  final CollectorPrefs? prefs;
  final ServerClient Function(String baseUrl)? clientFactory;
  final VoidCallback? onChanged;
  final BleDeviceManager? devices;

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  int _pending = 0;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
    final study = widget.study;
    if (study == null || widget.demo) {
      if (mounted) setState(() => _pending = 0);
      return;
    }
    final rows = await study.journal.pending();
    if (mounted) setState(() => _pending = rows.length);
  }

  Future<void> _sync() async {
    final study = widget.study;
    final prefs = widget.prefs;
    if (widget.demo) {
      _snack('演示数据只在屏幕上，不会同步');
      return;
    }
    if (study == null || prefs == null || prefs.deviceToken.isEmpty) {
      _snack('请先在「我的」里填写设备令牌');
      return;
    }
    setState(() => _syncing = true);
    final base = await widget.settings.getServerBaseUrl();
    final worker = SyncWorker(
      journal: study.journal,
      baseUrl: base,
      token: prefs.deviceToken,
      faults: SyncFaults(
        networkDown: prefs.faultNetworkDown,
        timeoutAfterCommit: prefs.faultTimeoutAfterCommit,
        clockSkew: prefs.faultClockSkew,
      ),
    );
    final count = await worker.syncOnce();
    await _loadPending();
    if (mounted) setState(() => _syncing = false);
    _snack('本轮同步完成 $count 条');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final hello = now.hour < 11 ? '早上好' : (now.hour < 18 ? '下午好' : '晚上好');
    final items = widget.study?.engine.items ?? const [];
    final done = items
        .where(
          (item) =>
              item.disposition == 'ACK_TIMELY' ||
              item.disposition == 'ACK_DELAYED',
        )
        .length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(hello, style: Theme.of(context).textTheme.headlineMedium),
        Text(
          '${now.year}年${now.month}月${now.day}日',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        if (widget.demo)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Material(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('正在查看演示数据。这些数字不会写入日志，也不会上传或进入导出。'),
              ),
            ),
          ),
        const SizedBox(height: 14),
        _SyncBar(
          pending: widget.demo ? 0 : _pending,
          syncing: _syncing,
          onSync: _sync,
        ),
        const SizedBox(height: 14),
        Text('设备状态', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _DeviceCard(
                title: '戒指 R09',
                icon: Icons.circle_outlined,
                kind: 'ring',
                record: _latestKind('ring'),
                devices: widget.demo ? null : widget.devices,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DeviceCard(
                title: '心率带 H303',
                icon: Icons.monitor_heart_outlined,
                kind: 'heart_rate',
                record: _latestKind('heart_rate'),
                devices: widget.demo ? null : widget.devices,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DeviceCard(
                title: '血压计 YE680B',
                icon: Icons.bloodtype_outlined,
                kind: 'blood_pressure',
                record: _latestKind('blood_pressure'),
                devices: widget.demo ? null : widget.devices,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('今日指标', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_visibleMetrics().isEmpty)
          const _EmptyState()
        else
          Wrap(spacing: 8, runSpacing: 8, children: _visibleMetrics()),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(
                    value: items.isEmpty ? 0 : done / items.length,
                    strokeWidth: 8,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    items.isEmpty
                        ? '今天还没有提醒。到「提醒」页添加服药或喝水。'
                        : '已确认 $done / ${items.length} 条提醒',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  LocalRecord? _latestKind(String kind) {
    for (final record in widget.records) {
      if (record.device.kind == kind ||
          record.device.name.toUpperCase().contains(
            kind == 'ring'
                ? 'R09'
                : kind == 'heart_rate'
                ? 'H303'
                : 'YE680',
          )) {
        return record;
      }
    }
    return null;
  }

  List<Widget> _visibleMetrics() {
    Widget? card(
      String type,
      String label,
      String unit,
      IconData icon,
      double Function(Map<String, Object?>) pick,
    ) {
      final rows = widget.records
          .where((record) => record.measurement.type == type)
          .toList();
      final live = widget.demo ? null : widget.devices?.latestByType[type];
      if (rows.isEmpty && live == null) return null;
      final latest = live?.values ?? rows.first.measurement.values;
      final series = [
        ...rows.reversed.map((record) => pick(record.measurement.values)),
        if (live != null) pick(live.values),
      ];
      return SizedBox(
        width: 160,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20),
                const SizedBox(height: 6),
                Text(label),
                Text(
                  type == 'blood_pressure'
                      ? '${_num(_asDouble(latest['systolic']))}/${_num(_asDouble(latest['diastolic']))} $unit'
                      : '${_num(pick(latest))} $unit',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                MiniChart(
                  values: series,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final cards = [
      card(
        'heart_rate',
        '心率',
        'bpm',
        Icons.favorite_outline,
        (v) => _asDouble(v['bpm']),
      ),
      card(
        'blood_pressure',
        '血压',
        'mmHg',
        Icons.bloodtype_outlined,
        (v) => _asDouble(v['systolic']),
      ),
      card(
        'spo2',
        '血氧',
        '%',
        Icons.water_drop_outlined,
        (v) => _asDouble(v['spo2']),
      ),
      card(
        'temperature',
        '体温',
        '°C',
        Icons.thermostat_outlined,
        (v) => _asDouble(v['celsius']),
      ),
      card(
        'steps',
        '步数',
        '步',
        Icons.directions_walk,
        (v) => _asDouble(v['steps']),
      ),
      card(
        'sleep',
        '睡眠',
        '分钟',
        Icons.bedtime_outlined,
        (v) => _asDouble(v['duration_min']),
      ),
    ];
    return [for (final item in cards) ?item];
  }
}

class _SyncBar extends StatelessWidget {
  const _SyncBar({
    required this.pending,
    required this.syncing,
    required this.onSync,
  });

  final int pending;
  final bool syncing;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.cloud_upload_outlined),
        title: Text(pending == 0 ? '日志已同步' : '待上传 $pending 条'),
        subtitle: const Text('最近同步时间以服务器回执为准'),
        trailing: FilledButton(
          onPressed: syncing ? null : onSync,
          child: Text(syncing ? '同步中' : '同步'),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.title,
    required this.icon,
    required this.kind,
    required this.record,
    required this.devices,
  });

  final String title;
  final IconData icon;
  final String kind;
  final LocalRecord? record;
  final BleDeviceManager? devices;

  @override
  Widget build(BuildContext context) {
    final live = devices?.latestByKind[kind];
    final measurement = live ?? record?.measurement;
    final when = measurement?.recordedAt.toLocal();
    final contact = measurement?.values['sensor_contact'];
    final worn = switch (contact) {
      'detected' => '已接触',
      'not_detected' => '未接触',
      _ => null,
    };
    final status =
        devices?.phaseLabel(kind) ?? (record == null ? '未连接' : '有读数');
    final reading = measurement == null
        ? null
        : measurement.type == 'heart_rate'
        ? '${_num(_asDouble(measurement.values['bpm']))} bpm'
        : measurement.type == 'blood_pressure'
        ? '${_num(_asDouble(measurement.values['systolic']))}/${_num(_asDouble(measurement.values['diastolic']))}'
        : summarize(measurement);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 6),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 12,
              ),
            ),
            if (reading != null)
              Text(
                worn == null ? reading : '$reading · $worn',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            if (when != null)
              Text(
                '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}:${when.second.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.spa_outlined, size: 56, color: scheme.primary),
            const SizedBox(height: 8),
            const Text(
              '还没有今天的读数',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              '连接戒指、心率带或血压计后，心率、血压、血氧、体温、步数和睡眠会显示在这里。也可以在「我的」打开演示数据，先看看版式。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

String _num(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return 0;
}
