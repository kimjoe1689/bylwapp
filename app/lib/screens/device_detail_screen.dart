import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/ble/device_manager.dart';
import 'package:bylwapp/journal/journal_store.dart';
import 'package:bylwapp/models/health_record.dart';
import 'package:bylwapp/ui/demo_catalog.dart';
import 'package:bylwapp/ui/device_profile.dart';

class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({
    super.key,
    required this.kind,
    this.devices,
    this.journal,
    this.demo = false,
    this.ble,
    this.onReading,
    this.onRequestScan,
  });

  final String kind;
  final BleDeviceManager? devices;
  final JournalStore? journal;
  final bool demo;
  final BleClient? ble;
  final Future<void> Function(HealthMeasurement measurement, BleScanHit hit)?
  onReading;
  final VoidCallback? onRequestScan;

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  static const _pageSize = 20;
  String _range = 'live';
  List<JournalRecord> _history = const [];
  List<JournalRecord> _chartRows = const [];
  bool _loading = true;
  bool _more = false;
  bool _busy = false;

  DeviceProfile get _profile =>
      DeviceProfile.ofKind(widget.kind) ?? DeviceProfile.heart;

  @override
  void initState() {
    super.initState();
    widget.devices?.addListener(_refresh);
    _reload(reset: true);
  }

  @override
  void dispose() {
    widget.devices?.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _reload({required bool reset}) async {
    if (widget.demo || widget.journal == null) {
      if (mounted) {
        setState(() {
          _history = const [];
          _chartRows = const [];
          _loading = false;
          _more = false;
        });
      }
      return;
    }
    final offset = reset ? 0 : _history.length;
    final page = await widget.journal!.matching(
      match: (row) => sameDevice(row, _profile),
      limit: _pageSize,
      offset: offset,
    );
    final chart = await _chartQuery();
    if (!mounted) return;
    setState(() {
      _history = reset ? page : [..._history, ...page];
      _chartRows = chart;
      _more = page.length == _pageSize;
      _loading = false;
    });
  }

  Future<void> _reloadChart() async {
    if (widget.demo || widget.journal == null) return;
    final chart = await _chartQuery();
    if (!mounted) return;
    setState(() => _chartRows = chart);
  }

  Future<List<JournalRecord>> _chartQuery() {
    final since = _since();
    return widget.journal!.matching(
      match: (row) {
        if (!sameDevice(row, _profile)) return false;
        final at = eventTime(row.event).toLocal();
        return since == null || !at.isBefore(since);
      },
      limit: 240,
    );
  }

  DateTime? _since() {
    final now = DateTime.now();
    return switch (_range) {
      'today' => DateTime(now.year, now.month, now.day),
      'week' => now.subtract(const Duration(days: 7)),
      _ => now.subtract(const Duration(minutes: 15)),
    };
  }

  List<_Point> get _points {
    if (widget.demo) {
      final demo = [
        for (final record in DemoCatalog.records())
          if (record.device.kind == widget.kind)
            _Point(
              at: record.measurement.recordedAt,
              type: record.measurement.type,
              values: record.measurement.values,
              eventId: null,
              syncState: null,
            ),
      ];
      if (_range == 'live') return demo;
      final since = _since();
      return [
        for (final point in demo)
          if (since == null || !point.at.toLocal().isBefore(since)) point,
      ];
    }
    final live = <_Point>[
      for (final entry
          in widget.devices?.recentByAddress.entries ??
              const <MapEntry<String, List<HealthMeasurement>>>[])
        for (final measurement in entry.value)
          if (_profile.types.contains(measurement.type) &&
              _addressMatches(entry.key))
            _Point(
              at: measurement.recordedAt,
              type: measurement.type,
              values: measurement.values,
              eventId: null,
              syncState: null,
            ),
    ];
    final saved = [
      for (final row in _chartRows)
        _Point(
          at: eventTime(row.event),
          type: row.event.measurementType,
          values: row.event.values,
          eventId: row.event.eventId,
          syncState: row.syncState,
        ),
    ];
    final since = _since();
    final all = [...saved, ...live]..sort((a, b) => a.at.compareTo(b.at));
    if (widget.demo) return all;
    return [
      for (final point in all)
        if (since == null || !point.at.toLocal().isBefore(since)) point,
    ];
  }

  bool _addressMatches(String address) {
    final current = widget.devices?.device?.address;
    if (current == null || !widget.devices!.tracksKind(widget.kind)) {
      return true;
    }
    return current.toUpperCase() == address.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final points = _points;
    final latest = _headline(points);
    final primary = _primarySeries(points);
    final secondary = widget.kind == 'blood_pressure'
        ? _series(points, 'blood_pressure', 'diastolic')
        : const <_Spot>[];
    final stats = seriesStats(primary.map((spot) => spot.y));
    final when = _latestTime(points);
    final battery = _battery(latest);
    return Scaffold(
      appBar: AppBar(title: Text(_profile.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (widget.demo)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('正在查看演示数据。这些数字不会写入日志，也不会上传。'),
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _profile.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Chip(
                        label: widget.devices?.phaseLabel(widget.kind) ?? '未连接',
                      ),
                      if (when != null) _Chip(label: '更新 ${_clock(when)}'),
                      if (battery != null) _Chip(label: '电量 $battery%'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: _linkButton()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (points.isEmpty && latest.isEmpty)
            _Empty(guide: _profile.guide, onScan: _goScan)
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _LiveValues(kind: widget.kind, latest: latest),
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'live', label: Text('实时')),
                ButtonSegment(value: 'today', label: Text('今天')),
                ButtonSegment(value: 'week', label: Text('7 天')),
              ],
              selected: {_range},
              onSelectionChanged: (value) {
                setState(() => _range = value.first);
                _reloadChart();
              },
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _Trend(
                  primary: primary,
                  secondary: secondary,
                  pressure: widget.kind == 'blood_pressure',
                ),
              ),
            ),
            if (stats != null) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '最大 ${_fmt(stats.max)}　最小 ${_fmt(stats.min)}　平均 ${_fmt(stats.average)}　${stats.count} 条',
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),
          Text('历史记录', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_loading)
            const LinearProgressIndicator()
          else if (widget.demo)
            for (final point in points.reversed)
              _HistoryTile(point: point, demo: true)
          else if (_history.isEmpty)
            const Text('日志里还没有这台设备的记录。')
          else ...[
            for (final row in _history) _JournalTile(row: row),
            if (_more)
              Align(
                child: TextButton(
                  onPressed: () => _reload(reset: false),
                  child: const Text('加载更多'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _linkButton() {
    final phase = widget.devices?.phaseLabel(widget.kind) ?? '未连接';
    if (phase == '已连接') {
      return FilledButton.tonal(
        onPressed: _busy ? null : _disconnect,
        child: const Text('断开'),
      );
    }
    if (phase == '连接中') {
      return const FilledButton.tonal(onPressed: null, child: Text('连接中'));
    }
    return FilledButton.tonal(
      onPressed: _busy ? null : _connect,
      child: const Text('连接'),
    );
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await widget.ble?.disconnect();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final address = _knownAddress();
    final ble = widget.ble;
    final onReading = widget.onReading;
    if (address == null || ble == null || onReading == null) {
      _goScan();
      return;
    }
    setState(() => _busy = true);
    try {
      await ble.connect(
        hit: BleScanHit(
          name: _profile.title,
          address: address,
          rssi: 0,
          driverId: _profile.driverId,
        ),
        onMeasurement: (measurement) => onReading(
          measurement,
          BleScanHit(
            name: _profile.title,
            address: address,
            rssi: 0,
            driverId: _profile.driverId,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, _Point> _headline(List<_Point> points) {
    final latest = _latestByType(points);
    final manager = widget.devices;
    final address = manager != null && manager.tracksKind(widget.kind)
        ? manager.device?.address
        : null;
    final recent = address == null
        ? const <HealthMeasurement>[]
        : manager!.recentByAddress[address] ?? const <HealthMeasurement>[];
    for (final measurement in recent) {
      if (!_profile.types.contains(measurement.type)) continue;
      final point = _Point(
        at: measurement.recordedAt,
        type: measurement.type,
        values: measurement.values,
        eventId: null,
        syncState: null,
      );
      final previous = latest[measurement.type];
      if (previous == null || point.at.isAfter(previous.at)) {
        latest[measurement.type] = point;
      }
    }
    return latest;
  }

  String? _knownAddress() {
    final manager = widget.devices;
    if (manager != null && manager.tracksKind(widget.kind)) {
      return manager.device?.address;
    }
    return null;
  }

  void _goScan() {
    widget.onRequestScan?.call();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}

class _Point {
  const _Point({
    required this.at,
    required this.type,
    required this.values,
    required this.eventId,
    required this.syncState,
  });

  final DateTime at;
  final String type;
  final Map<String, Object?> values;
  final String? eventId;
  final String? syncState;
}

class _Spot {
  const _Spot(this.x, this.y);
  final double x;
  final double y;
}

class _LiveValues extends StatelessWidget {
  const _LiveValues({required this.kind, required this.latest});

  final String kind;
  final Map<String, _Point> latest;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineMedium;
    if (kind == 'heart_rate') {
      final point = latest['heart_rate'];
      final rr = point?.values['rr_intervals_ms'];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            point == null ? '-- bpm' : '${_fmt(_num(point.values['bpm']))} bpm',
            style: style,
          ),
          const SizedBox(height: 4),
          Text(_contact(point?.values['sensor_contact'])),
          if (rr != null) Text('RR ${_rr(rr)}'),
        ],
      );
    }
    if (kind == 'blood_pressure') {
      final point = latest['blood_pressure'];
      final sys = point == null ? '--' : _fmt(_num(point.values['systolic']));
      final dia = point == null ? '--' : _fmt(_num(point.values['diastolic']));
      final pulse = point?.values['pulse'];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$sys / $dia', style: style),
          const SizedBox(height: 4),
          Text(pulse == null ? '脉搏 --' : '脉搏 ${_fmt(_num(pulse))}'),
        ],
      );
    }
    String cell(String type, String label, String unit, String key) {
      final point = latest[type];
      if (point == null) return '$label --';
      return '$label ${_fmt(_num(point.values[key]))} $unit';
    }

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        Text(cell('heart_rate', '心率', 'bpm', 'bpm'), style: style),
        Text(cell('spo2', '血氧', '%', 'spo2')),
        Text(cell('temperature', '体温', '°C', 'celsius')),
        Text(cell('steps', '步数', '步', 'steps')),
        Text(cell('sleep', '睡眠', '分钟', 'duration_min')),
      ],
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend({
    required this.primary,
    required this.secondary,
    required this.pressure,
  });

  final List<_Spot> primary;
  final List<_Spot> secondary;
  final bool pressure;

  @override
  Widget build(BuildContext context) {
    if (primary.length < 2 && secondary.length < 2) {
      return const Text('这个时间范围里还画不出趋势。');
    }
    final scheme = Theme.of(context).colorScheme;
    final spots = [
      ...primary.map((spot) => spot.y),
      ...secondary.map((spot) => spot.y),
    ];
    final low = spots.reduce((a, b) => a < b ? a : b);
    final high = spots.reduce((a, b) => a > b ? a : b);
    final pad = high == low ? 1.0 : 0.0;
    return SizedBox(
      height: 160,
      child: LineChart(
        duration: Duration.zero,
        LineChartData(
          minY: low - pad,
          maxY: high + pad,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            if (primary.length >= 2) _bar(primary, scheme.primary),
            if (pressure && secondary.length >= 2)
              _bar(secondary, scheme.tertiary),
          ],
        ),
      ),
    );
  }
}

LineChartBarData _bar(List<_Spot> spots, Color color) {
  return LineChartBarData(
    spots: [for (final spot in spots) FlSpot(spot.x, spot.y)],
    isCurved: spots.length > 2,
    color: color,
    barWidth: 2.4,
    dotData: FlDotData(show: spots.length < 8),
    belowBarData: BarAreaData(show: false),
  );
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.point, required this.demo});

  final _Point point;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(_summary(point)),
      subtitle: Text('${_clock(point.at)} · ${demo ? '演示' : '实时'}'),
      onTap: () => _showRaw(
        context,
        point.eventId,
        point.values['raw']?.toString(),
        demo ? '演示' : null,
      ),
    );
  }
}

class _JournalTile extends StatelessWidget {
  const _JournalTile({required this.row});

  final JournalRecord row;

  @override
  Widget build(BuildContext context) {
    final point = _Point(
      at: eventTime(row.event),
      type: row.event.measurementType,
      values: row.event.values,
      eventId: row.event.eventId,
      syncState: row.syncState,
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(_summary(point)),
      subtitle: Text('${_clock(point.at)} · ${syncLabel(row.syncState)}'),
      onTap: () => _showRaw(
        context,
        row.event.eventId,
        row.event.values['raw']?.toString(),
        syncLabel(row.syncState),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.guide, required this.onScan});

  final String guide;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.monitor_heart_outlined, size: 40, color: scheme.primary),
            const SizedBox(height: 8),
            const Text('还没有读数', textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(guide, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onScan, child: const Text('去连接')),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 12),
      ),
    );
  }
}

Map<String, _Point> _latestByType(List<_Point> points) {
  final latest = <String, _Point>{};
  for (final point in points) {
    final previous = latest[point.type];
    if (previous == null || point.at.isAfter(previous.at)) {
      latest[point.type] = point;
    }
  }
  return latest;
}

List<_Spot> _primarySeries(List<_Point> points) {
  if (points.any((point) => point.type == 'heart_rate')) {
    return _series(points, 'heart_rate', 'bpm');
  }
  if (points.any((point) => point.type == 'blood_pressure')) {
    return _series(points, 'blood_pressure', 'systolic');
  }
  if (points.any((point) => point.type == 'spo2')) {
    return _series(points, 'spo2', 'spo2');
  }
  return const [];
}

List<_Spot> _series(List<_Point> points, String type, String key) {
  final rows = points.where((point) => point.type == type).toList()
    ..sort((a, b) => a.at.compareTo(b.at));
  if (rows.isEmpty) return const [];
  final start = rows.first.at;
  return [
    for (final row in rows)
      _Spot(
        row.at.difference(start).inSeconds.toDouble(),
        _num(row.values[key]),
      ),
  ];
}

DateTime? _latestTime(List<_Point> points) {
  DateTime? latest;
  for (final point in points) {
    if (latest == null || point.at.isAfter(latest)) latest = point.at;
  }
  return latest;
}

int? _battery(Map<String, _Point> latest) {
  for (final point in latest.values) {
    for (final key in ['battery', 'battery_percent']) {
      final value = point.values[key];
      if (value is num) return value.round();
    }
  }
  return null;
}

String _summary(_Point point) {
  return summarize(
    HealthMeasurement(
      type: point.type,
      unit: '',
      recordedAt: point.at,
      values: point.values,
    ),
  );
}

void _showRaw(
  BuildContext context,
  String? eventId,
  String? raw,
  String? sync,
) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('记录详情'),
      content: Text(
        'event_id：${eventId ?? '演示，无事件'}\n同步：${sync ?? '演示'}\n原始字节：${raw == null || raw.isEmpty ? '无' : raw}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

String _contact(Object? value) {
  return switch (value) {
    'detected' => '已接触',
    'not_detected' => '未接触',
    _ => '接触未知',
  };
}

String _rr(Object? value) {
  if (value is List && value.isNotEmpty) {
    final first = value.first;
    if (first is num) return '${_fmt(first.toDouble())} ms';
  }
  return '--';
}

String _clock(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

double _num(Object? value) => value is num ? value.toDouble() : 0;

String _fmt(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);
