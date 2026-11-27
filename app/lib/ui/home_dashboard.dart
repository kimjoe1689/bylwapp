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
    this.onOpenReminders,
  });

  final List<LocalRecord> records;
  final bool demo;
  final SettingsStore settings;
  final StudyBundle? study;
  final CollectorPrefs? prefs;
  final ServerClient Function(String baseUrl)? clientFactory;
  final VoidCallback? onChanged;
  final BleDeviceManager? devices;
  final VoidCallback? onOpenReminders;

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  int _pending = 0;
  String? _lastSync;
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
    final syncedAt = await study.journal.latestSyncedAt();
    if (mounted) {
      setState(() {
        _pending = rows.length;
        _lastSync = syncedAt;
      });
    }
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
          lastSync: widget.demo ? null : _lastSync,
          syncing: _syncing,
          onSync: _sync,
        ),
        const SizedBox(height: 16),
        Text('设备状态', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              _DeviceRow(
                title: '戒指 R09',
                icon: Icons.circle_outlined,
                kind: 'ring',
                record: _latestKind('ring'),
                devices: widget.demo ? null : widget.devices,
              ),
              const Divider(height: 1),
              _DeviceRow(
                title: '心率带 H303',
                icon: Icons.monitor_heart_outlined,
                kind: 'heart_rate',
                record: _latestKind('heart_rate'),
                devices: widget.demo ? null : widget.devices,
              ),
              const Divider(height: 1),
              _DeviceRow(
                title: '血压计 YE680B',
                icon: Icons.bloodtype_outlined,
                kind: 'blood_pressure',
                record: _latestKind('blood_pressure'),
                devices: widget.demo ? null : widget.devices,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('今日指标', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _MetricGrid(
          records: widget.records,
          devices: widget.demo ? null : widget.devices,
        ),
        const SizedBox(height: 16),
        _ReminderCard(
          empty: items.isEmpty,
          done: done,
          total: items.length,
          onOpen: widget.onOpenReminders,
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
}

class _MetricSpec {
  const _MetricSpec(this.type, this.label, this.unit, this.icon, this.pick);

  final String type;
  final String label;
  final String unit;
  final IconData icon;
  final double Function(Map<String, Object?> values) pick;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.records, required this.devices});

  final List<LocalRecord> records;
  final BleDeviceManager? devices;

  static const _specs = [
    _MetricSpec('heart_rate', '心率', 'bpm', Icons.favorite_outline, _bpm),
    _MetricSpec(
      'blood_pressure',
      '血压',
      'mmHg',
      Icons.bloodtype_outlined,
      _systolic,
    ),
    _MetricSpec('spo2', '血氧', '%', Icons.water_drop_outlined, _spo2),
    _MetricSpec('temperature', '体温', '°C', Icons.thermostat_outlined, _temp),
    _MetricSpec('steps', '步数', '步', Icons.directions_walk, _steps),
    _MetricSpec('sleep', '睡眠', '分钟', Icons.bedtime_outlined, _sleep),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final spec in _specs)
              SizedBox(
                width: width,
                child: _MetricCard(
                  spec: spec,
                  records: records,
                  devices: devices,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.spec,
    required this.records,
    required this.devices,
  });

  final _MetricSpec spec;
  final List<LocalRecord> records;
  final BleDeviceManager? devices;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = records
        .where((record) => record.measurement.type == spec.type)
        .toList();
    final live = devices?.latestByType[spec.type];
    final hasValue = live != null || rows.isNotEmpty;
    final latest =
        live?.values ?? (rows.isEmpty ? null : rows.first.measurement.values);
    final series = [
      ...rows.reversed.map((record) => spec.pick(record.measurement.values)),
      if (live != null) spec.pick(live.values),
    ];
    final value = !hasValue || latest == null
        ? '--'
        : spec.type == 'blood_pressure'
        ? '${_num(_asDouble(latest['systolic']))}/${_num(_asDouble(latest['diastolic']))}'
        : _num(spec.pick(latest));
    final color = hasValue ? scheme.onSurface : scheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              spec.icon,
              size: 20,
              color: hasValue ? scheme.primary : scheme.outline,
            ),
            const SizedBox(height: 8),
            Text(spec.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              hasValue ? '$value ${spec.unit}' : '--',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: color),
            ),
            MiniChart(
              values: hasValue ? series : const [],
              color: hasValue ? scheme.primary : scheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}

double _bpm(Map<String, Object?> values) => _asDouble(values['bpm']);
double _systolic(Map<String, Object?> values) => _asDouble(values['systolic']);
double _spo2(Map<String, Object?> values) => _asDouble(values['spo2']);
double _temp(Map<String, Object?> values) => _asDouble(values['celsius']);
double _steps(Map<String, Object?> values) => _asDouble(values['steps']);
double _sleep(Map<String, Object?> values) => _asDouble(values['duration_min']);

class _SyncBar extends StatelessWidget {
  const _SyncBar({
    required this.pending,
    required this.lastSync,
    required this.syncing,
    required this.onSync,
  });

  final int pending;
  final String? lastSync;
  final bool syncing;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.cloud_upload_outlined),
        title: Text(pending == 0 ? '没有待上传' : '待上传 $pending 条'),
        subtitle: Text(_syncLabel(lastSync)),
        trailing: FilledButton.tonal(
          onPressed: syncing ? null : onSync,
          child: Text(syncing ? '同步中' : '同步'),
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
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
    final scheme = Theme.of(context).colorScheme;
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
        ? '--'
        : measurement.type == 'heart_rate'
        ? _num(_asDouble(measurement.values['bpm']))
        : measurement.type == 'blood_pressure'
        ? '${_num(_asDouble(measurement.values['systolic']))}/${_num(_asDouble(measurement.values['diastolic']))}'
        : summarize(measurement);
    final clock = when == null
        ? ''
        : '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusChip(label: status),
                    if (worn != null)
                      Text(
                        worn,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(reading, style: Theme.of(context).textTheme.titleMedium),
              if (clock.isNotEmpty)
                Text(
                  clock,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: scheme.onSecondaryContainer),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.empty,
    required this.done,
    required this.total,
    required this.onOpen,
  });

  final bool empty;
  final int done;
  final int total;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = total == 0 ? 0.0 : done / total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (empty)
              Icon(Icons.notifications_none, size: 40, color: scheme.primary)
            else
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              empty ? '今天还没有提醒' : '已确认 $done / $total 条提醒',
              textAlign: TextAlign.center,
            ),
            if (empty) ...[
              const SizedBox(height: 4),
              Text(
                '可以添加服药或喝水提醒',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onOpen, child: const Text('去添加提醒')),
            ],
          ],
        ),
      ),
    );
  }
}

String _syncLabel(String? raw) {
  if (raw == null || raw.isEmpty) {
    return '最近同步：还没有';
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return '最近同步：$raw';
  }
  final local = parsed.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '最近同步：${local.month}月${local.day}日 ${two(local.hour)}:${two(local.minute)}';
}

String _num(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return 0;
}
