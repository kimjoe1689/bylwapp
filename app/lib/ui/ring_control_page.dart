import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/ble/device_manager.dart';
import 'package:bylwapp/ble/ring/ring_actions.dart';
import 'package:bylwapp/ui/app_theme.dart';
import 'package:bylwapp/ui/mini_chart.dart';

class RingPreviewData {
  const RingPreviewData({
    required this.name,
    required this.connected,
    required this.battery,
    required this.charging,
    required this.lastSync,
    required this.heartRate,
    required this.spo2,
    required this.hrv,
    required this.steps,
    required this.calories,
    required this.distanceMeters,
    required this.sleepMinutes,
    required this.heartSeries,
    required this.stressSeries,
    required this.notices,
    this.measuring = true,
  });

  final String name;
  final bool connected;
  final int battery;
  final bool charging;
  final DateTime lastSync;
  final int heartRate;
  final int spo2;
  final int hrv;
  final int steps;
  final int calories;
  final int distanceMeters;
  final int sleepMinutes;
  final List<double> heartSeries;
  final List<double> stressSeries;
  final List<RingNotice> notices;
  final bool measuring;

  static final sample = RingPreviewData(
    name: 'R12_0607',
    connected: true,
    battery: 78,
    charging: true,
    lastSync: DateTime.utc(2026, 11, 28, 6, 20),
    heartRate: 72,
    spo2: 98,
    hrv: 46,
    steps: 8432,
    calories: 356,
    distanceMeters: 6120,
    sleepMinutes: 372,
    heartSeries: const [62, 68, 74, 71, 80, 76, 72],
    stressSeries: const [18, 24, 35, 28, 22],
    measuring: true,
    notices: [
      RingNotice(
        at: DateTime.utc(2026, 11, 28, 6, 18),
        hex: '73 12 00 20 f4 00',
        label: '戒指通知',
      ),
      RingNotice(
        at: DateTime.utc(2026, 11, 28, 6, 12),
        hex: '10 01 00',
        label: '未识别',
      ),
    ],
  );
}

class RingControlPage extends StatefulWidget {
  const RingControlPage({super.key, this.ble, this.devices, this.preview});

  final BleClient? ble;
  final BleDeviceManager? devices;
  final RingPreviewData? preview;

  @override
  State<RingControlPage> createState() => _RingControlPageState();
}

class _RingControlPageState extends State<RingControlPage> {
  bool? _hrAuto;
  bool? _spo2Auto;
  bool? _stressAuto;
  int _hrEvery = 30;
  int _spo2Every = 60;
  int _stressEvery = 30;
  bool _hrUnsupported = false;
  bool _spo2Unsupported = false;
  bool _stressUnsupported = false;
  int? _battery;
  bool _charging = false;
  bool _measuring = false;
  final List<RingNotice> _notices = [];

  @override
  void initState() {
    super.initState();
    final preview = widget.preview;
    if (preview != null) {
      _battery = preview.battery;
      _charging = preview.charging;
      _measuring = preview.measuring;
      _hrAuto = true;
      _spo2Auto = false;
      _stressUnsupported = true;
      _notices.addAll(preview.notices);
    }
    widget.devices?.addListener(_rebuild);
    widget.ble?.ringNotices.listen((notice) {
      if (!mounted) return;
      setState(() {
        _notices.insert(0, notice);
        if (_notices.length > 8) _notices.removeLast();
      });
    });
  }

  @override
  void dispose() {
    widget.devices?.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  bool get _connected {
    final preview = widget.preview;
    if (preview != null) return preview.connected;
    return widget.devices?.phaseLabel('ring') == '已连接';
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final scheme = Theme.of(context).colorScheme;
    final hr = preview?.heartRate ?? _live('heart_rate', 'bpm');
    final spo2 = preview?.spo2 ?? _live('spo2', 'spo2');
    final hrv = preview?.hrv ?? _live('hrv', 'hrv_ms');
    final steps = preview?.steps ?? _live('steps', 'steps');
    final calories = preview?.calories ?? _live('steps', 'calories');
    final distance = preview?.distanceMeters ?? _live('steps', 'distance_m');
    final sleep = preview?.sleepMinutes ?? _live('sleep', 'duration_min');
    final battery = _battery ?? preview?.battery;
    return Scaffold(
      appBar: AppBar(title: const Text('戒指')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _Hero(
            name: preview?.name ?? widget.devices?.device?.name ?? 'Colmi R',
            connected: _connected,
            battery: battery,
            charging: _charging || (preview?.charging ?? false),
            lastSync: preview?.lastSync,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _LiveCard(
                  label: '心率',
                  value: hr,
                  unit: 'bpm',
                  icon: Icons.favorite,
                  live: _measuring && _connected,
                  onStart: () => _act(RingAction.startHeart),
                  onStop: () => _act(RingAction.stopHeart),
                  measuring: _measuring,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _LiveCard(
                  label: '血氧',
                  value: spo2,
                  unit: '%',
                  icon: Icons.water_drop_outlined,
                  live: false,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _LiveCard(
                  label: 'HRV',
                  value: hrv,
                  unit: 'ms',
                  icon: Icons.monitor_heart_outlined,
                  live: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('今天', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _TodayCard(
            steps: steps,
            calories: calories,
            distanceMeters: distance,
            sleepMinutes: sleep,
            heart: preview?.heartSeries ?? const [72],
            stress: preview?.stressSeries ?? const [22],
            color: scheme.primary,
          ),
          const SizedBox(height: 16),
          Text('自动测量', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _AutoCard(
            title: '心率',
            enabled: _hrAuto,
            unsupported: _hrUnsupported,
            minutes: _hrEvery,
            onChanged: (value) => setState(() => _hrAuto = value),
            onMinutes: (value) => setState(() => _hrEvery = value),
            onRead: () => _readAuto('heart_rate'),
            onSave: () => _writeAuto('heart_rate', _hrAuto, _hrEvery),
          ),
          _AutoCard(
            title: '血氧',
            enabled: _spo2Auto,
            unsupported: _spo2Unsupported,
            minutes: _spo2Every,
            onChanged: (value) => setState(() => _spo2Auto = value),
            onMinutes: (value) => setState(() => _spo2Every = value),
            onRead: () => _readAuto('spo2'),
            onSave: () => _writeAuto('spo2', _spo2Auto, _spo2Every),
          ),
          _AutoCard(
            title: '压力',
            enabled: _stressAuto,
            unsupported: _stressUnsupported,
            minutes: _stressEvery,
            onChanged: (value) => setState(() => _stressAuto = value),
            onMinutes: (value) => setState(() => _stressEvery = value),
            onRead: () => _readAuto('stress'),
            onSave: () => _writeAuto('stress', _stressAuto, _stressEvery),
          ),
          const SizedBox(height: 8),
          Text('工具', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Tool(
                icon: Icons.wifi_tethering,
                label: '找戒指',
                onTap: () => _act(RingAction.find),
              ),
              _Tool(
                icon: Icons.schedule,
                label: '同步时间',
                onTap: () => _act(RingAction.syncTime),
              ),
              _Tool(
                icon: Icons.sync,
                label: '立即同步',
                onTap: () => _act(RingAction.syncHistory),
              ),
              _Tool(
                icon: Icons.battery_charging_full,
                label: '读取电量',
                onTap: () => _act(RingAction.battery),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('戒指事件', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_notices.isEmpty)
            Text(
              '还没有戒指主动发来的通知。',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else
            for (final notice in _notices.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_shanghai(notice.at)}  ${notice.label}  ${notice.hex}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          const SizedBox(height: 8),
          Card(
            color: scheme.errorContainer.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '危险操作',
                    style: TextStyle(
                      color: scheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton(
                        onPressed: () => _confirm(
                          '关机',
                          '戒指会关闭，直到放回充电座。',
                          RingAction.powerOff,
                        ),
                        child: const Text('关机'),
                      ),
                      OutlinedButton(
                        onPressed: () => _confirm(
                          '恢复出厂',
                          '戒指里的记录会被清除。',
                          RingAction.factoryReset,
                        ),
                        child: const Text('恢复出厂'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int? _live(String type, String key) {
    final value = widget.devices?.latestByType[type]?.values[key];
    if (value is num) return value.round();
    return null;
  }

  Future<void> _act(RingAction action) async {
    final ble = widget.ble;
    if (widget.preview != null || ble == null) {
      if (action.id == 'live-start') setState(() => _measuring = true);
      if (action.id == 'live-stop') setState(() => _measuring = false);
      return;
    }
    final result = await ble.performRingAction(action);
    if (!mounted) return;
    if (action.id == 'battery' && result.batteryPercent != null) {
      setState(() {
        _battery = result.batteryPercent;
        _charging = result.charging ?? false;
      });
    }
    if (action.id == 'live-start' && result.supported) {
      setState(() => _measuring = true);
    }
    if (action.id == 'live-stop' && result.supported) {
      setState(() => _measuring = false);
    }
    _toast(result.supported ? result.message : '不支持');
  }

  Future<void> _readAuto(String metric) async {
    final ble = widget.ble;
    if (widget.preview != null || ble == null) return;
    final result = await ble.performRingAction(RingAction.readAuto(metric));
    if (!mounted) return;
    setState(() {
      if (!result.supported) {
        if (metric == 'heart_rate') _hrUnsupported = true;
        if (metric == 'spo2') _spo2Unsupported = true;
        if (metric == 'stress') _stressUnsupported = true;
      } else {
        if (metric == 'heart_rate') {
          _hrUnsupported = false;
          _hrAuto = result.enabled;
          _hrEvery = result.minutes ?? _hrEvery;
        }
        if (metric == 'spo2') {
          _spo2Unsupported = false;
          _spo2Auto = result.enabled;
          _spo2Every = result.minutes ?? _spo2Every;
        }
        if (metric == 'stress') {
          _stressUnsupported = false;
          _stressAuto = result.enabled;
          _stressEvery = result.minutes ?? _stressEvery;
        }
      }
    });
    _toast(result.supported ? '已读取$metric' : '不支持');
  }

  Future<void> _writeAuto(String metric, bool? enabled, int minutes) async {
    if (enabled == null) return;
    final ble = widget.ble;
    if (widget.preview != null || ble == null) return;
    final result = await ble.performRingAction(
      RingAction.writeAuto(metric, enabled: enabled, minutes: minutes),
    );
    if (!mounted) return;
    if (!result.supported) {
      setState(() {
        if (metric == 'heart_rate') _hrUnsupported = true;
        if (metric == 'spo2') _spo2Unsupported = true;
        if (metric == 'stress') _stressUnsupported = true;
      });
    }
    _toast(result.supported ? result.message : '不支持');
  }

  Future<void> _confirm(String title, String body, RingAction action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (ok == true) await _act(action);
  }

  void _toast(String message) {
    if (!mounted || message.isEmpty) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.name,
    required this.connected,
    required this.battery,
    required this.charging,
    required this.lastSync,
  });

  final String name;
  final bool connected;
  final int? battery;
  final bool charging;
  final DateTime? lastSync;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 132,
              height: 132,
              child: CustomPaint(
                painter: _RingPainter(
                  glow: scheme.primary,
                  metal: scheme.brightness == Brightness.dark
                      ? const Color(0xFFD7E4E1)
                      : const Color(0xFFE7F3F1),
                  battery: (battery ?? 0) / 100,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    _seriesLabel(name),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Pill(
                    text: connected ? '已连接' : '未连接',
                    color: connected
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        battery == null ? '电量 --' : '电量 $battery%',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (charging) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.bolt, size: 18, color: scheme.primary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lastSync == null ? '尚未同步' : '上次同步 ${_shanghai(lastSync!)}',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.glow,
    required this.metal,
    required this.battery,
  });

  final Color glow;
  final Color metal;
  final double battery;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.38;
    canvas.drawCircle(
      center,
      radius + 10,
      Paint()
        ..color = glow.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    final ring = Paint()
      ..shader = SweepGradient(
        colors: [
          metal,
          const Color(0xFF8AA8A3),
          metal,
          const Color(0xFFF7FFFE),
          metal,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18;
    canvas.drawCircle(center, radius, ring);
    canvas.drawCircle(
      center,
      radius - 16,
      Paint()..color = glow.withValues(alpha: 0.08),
    );
    final arc = Paint()
      ..color = glow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius + 14),
      -math.pi / 2,
      math.pi * 2 * battery.clamp(0, 1),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.battery != battery || oldDelegate.glow != glow;
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.live,
    this.onStart,
    this.onStop,
    this.measuring = false,
  });

  final String label;
  final int? value;
  final String unit;
  final IconData icon;
  final bool live;
  final VoidCallback? onStart;
  final VoidCallback? onStop;
  final bool measuring;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: live ? scheme.primary : scheme.outline,
                ),
                const Spacer(),
                if (onStart != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: measuring ? onStop : onStart,
                    icon: Icon(
                      measuring
                          ? Icons.stop_circle_outlined
                          : Icons.play_circle_outline,
                      size: 20,
                    ),
                  ),
              ],
            ),
            Text(label, style: const TextStyle(fontSize: 12)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value == null ? '--' : '$value',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Text(
              unit,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.steps,
    required this.calories,
    required this.distanceMeters,
    required this.sleepMinutes,
    required this.heart,
    required this.stress,
    required this.color,
  });

  final int? steps;
  final int? calories;
  final int? distanceMeters;
  final int? sleepMinutes;
  final List<double> heart;
  final List<double> stress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final km = distanceMeters == null
        ? '--'
        : (distanceMeters! / 1000).toStringAsFixed(1);
    final sleep = sleepMinutes == null
        ? '--'
        : '${sleepMinutes! ~/ 60} 小时 ${sleepMinutes! % 60} 分';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('步数 ${steps ?? '--'}    热量 ${calories ?? '--'} 千卡    $km 公里'),
            const SizedBox(height: 8),
            Text('昨夜睡眠 $sleep'),
            const SizedBox(height: 12),
            const Text('今日心率'),
            MiniChart(values: heart, color: color),
            const SizedBox(height: 8),
            const Text('压力'),
            MiniChart(values: stress, color: color.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}

class _AutoCard extends StatelessWidget {
  const _AutoCard({
    required this.title,
    required this.enabled,
    required this.unsupported,
    required this.minutes,
    required this.onChanged,
    required this.onMinutes,
    required this.onRead,
    required this.onSave,
  });

  final String title;
  final bool? enabled;
  final bool unsupported;
  final int minutes;
  final ValueChanged<bool> onChanged;
  final ValueChanged<int> onMinutes;
  final VoidCallback onRead;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title)),
                if (unsupported)
                  const Text('不支持')
                else
                  Switch(value: enabled ?? false, onChanged: onChanged),
              ],
            ),
            if (!unsupported)
              Wrap(
                spacing: 8,
                children: [
                  for (final option in const [10, 30, 60])
                    ChoiceChip(
                      label: Text('$option 分钟'),
                      selected: minutes == option,
                      onSelected: (_) => onMinutes(option),
                    ),
                  TextButton(onPressed: onRead, child: const Text('读取')),
                  TextButton(onPressed: onSave, child: const Text('保存')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      child: FilledButton.tonalIcon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

String _seriesLabel(String name) {
  final model = name.split('_').first;
  if (model.isEmpty) return 'Colmi R 系列';
  final temp = RegExp(r'^R0[59]$').hasMatch(model);
  return temp ? 'Colmi $model · 含体温' : 'Colmi $model';
}

String _shanghai(DateTime time) {
  final wall = time.toUtc().add(const Duration(hours: 8));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${wall.month}月${wall.day}日 ${two(wall.hour)}:${two(wall.minute)}';
}

/// Used by the screenshot harness so the page is themed without a device.
Widget ringPreviewApp({required bool dark}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildBylwTheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      elder: false,
    ),
    home: RingControlPage(preview: RingPreviewData.sample),
  );
}
