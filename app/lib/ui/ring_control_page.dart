import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/ble/device_manager.dart';
import 'package:bylwapp/ble/ring/ring_actions.dart';
import 'package:bylwapp/ble/ring/ring_parser.dart';
import 'package:bylwapp/ble/ring/ring_trace.dart';
import 'package:bylwapp/settings/settings_store.dart';
import 'package:bylwapp/ui/ring_explore_page.dart';
import 'package:bylwapp/journal/journal_store.dart';
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
        hex: '03 4e 01',
        label: '电量 78%',
      ),
      RingNotice(
        at: DateTime.utc(2026, 11, 28, 6, 12),
        hex: '55 00',
        label: 'unknown 0x55',
      ),
    ],
  );
}

class RingControlPage extends StatefulWidget {
  const RingControlPage({
    super.key,
    this.ble,
    this.devices,
    this.preview,
    this.journal,
    this.settings,
    this.traces,
  });

  final BleClient? ble;
  final BleDeviceManager? devices;
  final RingPreviewData? preview;
  final JournalStore? journal;
  final SettingsStore? settings;
  final RingTraceStore? traces;

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
  bool _showHex = false;
  DateTime? _historyAt;
  DateTime? _journalLoadedAt;
  List<double> _heartSeries = const [];
  List<double> _stressSeries = const [];
  final List<RingNotice> _notices = [];
  final ScrollController _scroll = ScrollController();
  StreamSubscription<RingNotice>? _noticeSub;
  StreamSubscription<RingSnapshot>? _snapshotSub;

  @override
  void initState() {
    super.initState();
    final preview = widget.preview;
    final snap = widget.ble?.ringSnapshot;
    if (preview != null) {
      _battery = preview.battery;
      _charging = preview.charging;
      _measuring = preview.measuring;
      _historyAt = preview.lastSync;
      _hrAuto = true;
      _spo2Auto = false;
      _stressUnsupported = true;
      for (final notice in preview.notices) {
        _pushNotice(notice);
      }
    } else if (snap != null) {
      _battery = snap.batteryPercent;
      _charging = snap.charging;
      _measuring = snap.measuring;
      _historyAt = snap.historySyncedAt;
    }
    widget.devices?.addListener(_rebuild);
    widget.ble?.setRingPageOpen(true);
    _loadRingPrefs();
    _noticeSub = widget.ble?.ringNotices.listen((notice) {
      if (!mounted || notice.label.isEmpty) return;
      setState(() => _pushNotice(notice));
    });
    _snapshotSub = widget.ble?.ringSnapshots.listen((snap) {
      if (!mounted) return;
      setState(() {
        if (snap.batteryPercent != null) _battery = snap.batteryPercent;
        _charging = snap.charging;
        _measuring = snap.measuring;
        if (snap.historySyncedAt != null) _historyAt = snap.historySyncedAt;
        if (snap.temperatureC != null) _temperatureC = snap.temperatureC;
        _temperatureChecked = snap.temperatureChecked;
        if (snap.info != null) _info = snap.info;
      });
      _loadJournal();
    });
    _loadJournal();
  }

  @override
  void dispose() {
    widget.ble?.setRingPageOpen(false);
    _noticeSub?.cancel();
    _snapshotSub?.cancel();
    _gestureTick?.cancel();
    _gestureSub?.cancel();
    _scroll.dispose();
    widget.devices?.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (!mounted) return;
    setState(() {});
    final now = DateTime.now();
    if (_journalLoadedAt == null ||
        now.difference(_journalLoadedAt!) > const Duration(seconds: 5)) {
      _loadJournal();
    }
  }

  Future<void> _loadJournal() async {
    final journal = widget.journal;
    if (journal == null || widget.preview != null) return;
    _journalLoadedAt = DateTime.now();
    final rows = await journal.recent(limit: 800);
    if (!mounted) return;
    final start = shanghaiDayStart(DateTime.now());
    final hearts = <double>[];
    final stress = <double>[];
    int? steps;
    int? calories;
    int? distance;
    var sleep = 0;
    var sawSleep = false;
    double? temperature;
    for (final row in rows) {
      final event = row.event;
      if (event.sensorKind != 'ring') continue;
      final when = DateTime.tryParse(event.wallTimeUtc ?? '');
      if (when == null || when.isBefore(start)) continue;
      final value = switch (event.measurementType) {
        'heart_rate' => event.values['bpm'],
        'stress' => event.values['stress'],
        _ => null,
      };
      if (event.measurementType == 'heart_rate' && value is num) {
        hearts.add(value.toDouble());
      } else if (event.measurementType == 'stress' && value is num) {
        stress.add(value.toDouble());
      } else if (event.measurementType == 'steps') {
        steps ??= _asInt(event.values['steps']);
        calories ??= _asInt(event.values['calories']);
        distance ??= _asInt(event.values['distance_m']);
      } else if (event.measurementType == 'temperature') {
        final celsius = event.values['celsius'];
        if (celsius is num) temperature ??= celsius.toDouble();
      } else if (event.measurementType == 'sleep') {
        final minutes = _asInt(event.values['duration_min']);
        if (minutes != null) {
          sleep += minutes;
          sawSleep = true;
        }
      }
    }
    setState(() {
      _heartSeries = hearts.take(48).toList().reversed.toList();
      _stressSeries = stress.take(48).toList().reversed.toList();
      _journalSteps = steps;
      _journalCalories = calories;
      _journalDistance = distance;
      _journalSleep = sawSleep ? sleep : null;
      _journalTemp = temperature;
    });
  }

  int? _journalSteps;
  int? _journalCalories;
  int? _journalDistance;
  int? _journalSleep;
  double? _journalTemp;
  double? _temperatureC;
  bool _temperatureChecked = false;
  bool _explore = true;
  bool _intervalHr = true;
  bool _gestureMark = false;
  RingDeviceInfo? _info;
  int? _gestureLeft;
  final List<String> _gestureLog = [];
  Timer? _gestureTick;
  StreamSubscription<String>? _gestureSub;

  Future<void> _setHeartSchedule(bool interval) async {
    setState(() => _intervalHr = interval);
    final mode = interval ? 'interval' : 'continuous';
    widget.ble?.setHeartSchedule(mode);
    await widget.settings?.setHeartSchedule(mode);
  }

  Future<void> _loadRingPrefs() async {
    final settings = widget.settings;
    if (settings == null) return;
    final explore = await settings.getExploreEvents();
    final schedule = await settings.getHeartSchedule();
    final mark = await settings.getGestureMark();
    widget.ble?.setExploreEvents(explore);
    widget.ble?.setHeartSchedule(schedule);
    widget.ble?.setGestureMark(mark);
    if (!mounted) return;
    setState(() {
      _explore = explore;
      _intervalHr = schedule != 'continuous';
      _gestureMark = mark;
    });
  }

  void _pushNotice(RingNotice notice) {
    if (_notices.isNotEmpty &&
        _notices.first.label == notice.label &&
        _notices.first.developerOnly == notice.developerOnly) {
      final previous = _notices.first;
      _notices[0] = RingNotice(
        at: notice.at,
        hex: notice.hex.isEmpty ? previous.hex : notice.hex,
        label: notice.label,
        count: previous.count + 1,
        developerOnly: notice.developerOnly,
      );
      return;
    }
    _notices.insert(0, notice);
    if (_notices.length > 12) _notices.removeLast();
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
    final steps = preview?.steps ?? _live('steps', 'steps') ?? _journalSteps;
    final calories =
        preview?.calories ?? _live('steps', 'calories') ?? _journalCalories;
    final distance =
        preview?.distanceMeters ??
        _live('steps', 'distance_m') ??
        _journalDistance;
    final sleep =
        preview?.sleepMinutes ??
        _live('sleep', 'duration_min') ??
        _journalSleep;
    final battery = _battery ?? preview?.battery;
    final temperature = _temperatureC ?? _journalTemp;
    return Scaffold(
      appBar: AppBar(
        title: const Text('戒指'),
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface,
        scrolledUnderElevation: 0,
        notificationPredicate: (_) => false,
      ),
      body: ListView(
        controller: _scroll,
        primary: false,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _Hero(
            name: preview?.name ?? widget.devices?.device?.name ?? 'Colmi R',
            connected: _connected,
            battery: battery,
            charging: _charging || (preview?.charging ?? false),
            lastSync: _historyAt,
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
          if (preview == null && _info != null) ...[
            const SizedBox(height: 8),
            _DeviceInfoCard(info: _info!),
          ],
          if (preview == null) ...[
            const SizedBox(height: 8),
            _TemperatureCard(
              celsius: temperature,
              checked: _temperatureChecked || _journalTemp != null,
            ),
          ],
          const SizedBox(height: 16),
          Text('今天', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _TodayCard(
            steps: steps,
            calories: calories,
            distanceMeters: distance,
            sleepMinutes: sleep,
            heart: preview?.heartSeries ?? _heartSeries,
            stress: preview?.stressSeries ?? _stressSeries,
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
          Text('采集', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('事件探索'),
                    subtitle: const Text('记下每一个收发包。主动上报和未知包会上传。'),
                    value: _explore,
                    onChanged: (value) async {
                      setState(() => _explore = value);
                      widget.ble?.setExploreEvents(value);
                      await widget.settings?.setExploreEvents(value);
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: widget.traces == null
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (context) =>
                                      RingExplorePage(traces: widget.traces!),
                                ),
                              );
                            },
                      child: const Text('查看并导出'),
                    ),
                  ),
                  const Text('实时心率'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        showCheckmark: false,
                        label: const Text('连续'),
                        selected: !_intervalHr,
                        onSelected: (_) => _setHeartSchedule(false),
                      ),
                      ChoiceChip(
                        showCheckmark: false,
                        label: const Text('每5分钟测30秒'),
                        selected: _intervalHr,
                        onSelected: (_) => _setHeartSchedule(true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '打开本页时会一直测。固件大约 30 秒会停，应用会重新开始。',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('挥手打标记'),
                    subtitle: const Text('保持手势模式，每次挥手记一条，不做其他动作。'),
                    value: _gestureMark,
                    onChanged: (value) async {
                      setState(() => _gestureMark = value);
                      widget.ble?.setGestureMark(value);
                      await widget.settings?.setGestureMark(value);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
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
              _Tool(
                icon: Icons.waving_hand_outlined,
                label: '测试手势',
                onTap: _testGesture,
              ),
            ],
          ),
          if (_gestureLog.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_gestureLeft == null ? '手势测试结束' : '请挥手 $_gestureLeft 秒'),
            for (final line in _gestureLog.take(8))
              Text(line, style: const TextStyle(fontSize: 12)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Text('戒指事件', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _showHex = !_showHex),
                child: Text(_showHex ? '隐藏开发者信息' : '开发者信息'),
              ),
            ],
          ),
          if (_visibleNotices.isEmpty)
            Text(
              '还没有戒指主动发来的通知。',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else
            for (final notice in _visibleNotices.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_shanghai(notice.at)}  ${notice.count > 1 ? '${notice.label} ×${notice.count}' : notice.label}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (_showHex && notice.hex.isNotEmpty)
                      Text(
                        notice.hex,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
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
                          '重启/关机（0x08）',
                          '不同固件上，这条指令可能是重启，也可能是关机。',
                          RingAction.powerOff,
                        ),
                        child: const Text('重启/关机（0x08）'),
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

  List<RingNotice> get _visibleNotices => _showHex
      ? _notices
      : _notices.where((notice) => !notice.developerOnly).toList();

  Future<void> _testGesture() async {
    final ble = widget.ble;
    if (ble == null || _gestureLeft != null || widget.preview != null) return;
    setState(() {
      _gestureLeft = 30;
      _gestureLog
        ..clear()
        ..add('已发送 02 04、02 05。请在 30 秒内挥手。');
    });
    await _gestureSub?.cancel();
    _gestureSub = ble.gestureRx.listen((line) {
      if (!mounted) return;
      setState(() {
        _gestureLog.insert(0, line);
        if (_gestureLog.length > 12) _gestureLog.removeLast();
      });
    });
    await ble.performRingAction(RingAction.gestureOn);
    await ble.performRingAction(RingAction.gestureWait);
    _gestureTick?.cancel();
    _gestureTick = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final left = (_gestureLeft ?? 1) - 1;
      if (left <= 0) {
        _finishGesture();
      } else {
        setState(() => _gestureLeft = left);
      }
    });
  }

  Future<void> _finishGesture() async {
    _gestureTick?.cancel();
    _gestureTick = null;
    final keep = widget.settings == null
        ? _gestureMark
        : await widget.settings!.getGestureMark();
    if (!keep) {
      await widget.ble?.performRingAction(RingAction.gestureOff);
    }
    await _gestureSub?.cancel();
    _gestureSub = null;
    if (!mounted) return;
    setState(() {
      _gestureLeft = null;
      _gestureLog.insert(0, '已发送关闭手势 02 06。');
    });
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
  const _RingPainter({required this.glow, required this.battery});

  final Color glow;
  final double battery;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.34;
    const band = 16.0;
    canvas.drawCircle(
      center,
      radius + 6,
      Paint()
        ..color = glow.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    final track = Rect.fromCircle(
      center: center,
      radius: radius + band / 2 + 8,
    );
    canvas.drawArc(
      track,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = const Color(0xFFD5E3E0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawArc(
      track,
      -math.pi / 2,
      math.pi * 2 * battery.clamp(0, 1),
      false,
      Paint()
        ..color = glow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    final ringRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Color(0xFF9AABA6),
            Color(0xFF3A4845),
            Color(0xFFD5E4E0),
            Color(0xFF546561),
            Color(0xFFF7FFFD),
            Color(0xFF6A7C78),
            Color(0xFF9AABA6),
          ],
        ).createShader(ringRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = band,
    );
    canvas.drawCircle(
      center,
      radius - band / 2 + 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF1C2926).withValues(alpha: 0.55),
    );
    canvas.drawArc(
      ringRect,
      -2.5,
      1.05,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9),
    );
    for (final angle in const [0.55, 1.1, 1.65]) {
      final orbit = radius - band / 2 - 1;
      final bump = Offset(
        center.dx + orbit * math.cos(angle),
        center.dy + orbit * math.sin(angle),
      );
      canvas.drawCircle(bump, 3.3, Paint()..color = const Color(0xFF1A2623));
      canvas.drawCircle(
        bump.translate(-0.7, -0.7),
        1.1,
        Paint()..color = const Color(0xFFB7C9C4),
      );
    }
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

class _DeviceInfoCard extends StatelessWidget {
  const _DeviceInfoCard({required this.info});

  final RingDeviceInfo info;

  @override
  Widget build(BuildContext context) {
    String yesNo(bool? value) => switch (value) {
      true => '支持',
      false => '不支持',
      null => '未知',
    };
    final lines = <String>[
      if (info.model != null) '型号 ${info.model}',
      if (info.firmware != null) '固件 ${info.firmware}',
      if (info.hardware != null) '硬件 ${info.hardware}',
      '体温 ${yesNo(info.temperature)}',
      '血氧 ${yesNo(info.spo2)}',
      '压力 ${yesNo(info.stress)}',
      'HRV ${yesNo(info.hrv)}',
      if (info.screenWidth != null && info.screenHeight != null)
        '屏幕 ${info.screenWidth}×${info.screenHeight}',
      if (info.maxPacket != null) '最大包长 ${info.maxPacket} 字节',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('设备信息'),
            const SizedBox(height: 8),
            for (final line in lines)
              Text(line, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _TemperatureCard extends StatelessWidget {
  const _TemperatureCard({required this.celsius, required this.checked});

  final double? celsius;
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = celsius != null
        ? '${celsius!.toStringAsFixed(1)} °C'
        : checked
        ? '该戒指未返回体温'
        : '正在读取体温';
    return Card(
      child: ListTile(
        leading: Icon(Icons.thermostat, color: scheme.primary),
        title: const Text('体温'),
        subtitle: Text(text),
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
    final distance = formatRingDistance(distanceMeters);
    final sleep = formatRingSleep(sleepMinutes);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '步数 ${steps ?? '--'}    热量 ${calories ?? '--'} 千卡    $distance',
            ),
            const SizedBox(height: 8),
            Text(sleep),
            const SizedBox(height: 12),
            const Text('今日心率'),
            _Series(values: heart, color: color, empty: '今天还没有心率'),
            const SizedBox(height: 8),
            const Text('压力'),
            _Series(
              values: stress,
              color: color.withValues(alpha: 0.7),
              empty: '今天还没有压力记录',
            ),
          ],
        ),
      ),
    );
  }
}

class _Series extends StatelessWidget {
  const _Series({
    required this.values,
    required this.color,
    required this.empty,
  });

  final List<double> values;
  final Color color;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          empty,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return MiniChart(values: values, color: color);
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
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final option in const [10, 30, 60])
                    SizedBox(
                      width: 96,
                      child: ChoiceChip(
                        showCheckmark: false,
                        label: Center(child: Text('$option 分钟')),
                        selected: minutes == option,
                        onSelected: (_) => onMinutes(option),
                      ),
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

int? _asInt(Object? value) => value is num ? value.round() : null;

String formatRingDistance(int? meters) {
  if (meters == null) return '--';
  if (meters < 1000) return '$meters 米';
  final km = meters / 1000;
  final text = km >= 10 ? km.toStringAsFixed(0) : km.toStringAsFixed(1);
  return '$text 公里';
}

String formatRingSleep(int? minutes) {
  if (minutes == null || minutes <= 0) return '还没有睡眠记录';
  return '昨夜睡眠 ${minutes ~/ 60} 小时 ${minutes % 60} 分';
}

DateTime shanghaiDayStart(DateTime now) {
  final wall = now.toUtc().add(const Duration(hours: 8));
  return DateTime.utc(
    wall.year,
    wall.month,
    wall.day,
  ).subtract(const Duration(hours: 8));
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
