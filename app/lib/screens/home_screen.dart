import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/api/server_client.dart';
import 'package:bylwapp/data/health_repository.dart';
import 'package:bylwapp/models/health_record.dart';
import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/journal/canonical_event.dart';
import 'package:bylwapp/screens/debug_screen.dart';
import 'package:bylwapp/screens/scan_screen.dart';
import 'package:bylwapp/screens/settings_screen.dart';
import 'package:bylwapp/screens/study_screens.dart';
import 'package:bylwapp/settings/settings_store.dart';
import 'package:bylwapp/sync/sync_worker.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.settings,
    required this.ble,
    this.clientFactory,
    this.study,
    this.prefs,
  });

  final HealthRepository repository;
  final SettingsStore settings;
  final BleClient ble;
  final ServerClient Function(String baseUrl)? clientFactory;
  final StudyBundle? study;
  final CollectorPrefs? prefs;

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
                    onReading: _journalMeasurement,
                  ),
                ),
              );
              await _reload();
            },
            icon: const Icon(Icons.bluetooth_searching),
          ),
          IconButton(
            tooltip: '调试',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) =>
                      DebugScreen(ble: widget.ble, prefs: widget.prefs),
                ),
              );
            },
            icon: const Icon(Icons.bug_report_outlined),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => SettingsScreen(
                    settings: widget.settings,
                    prefs: widget.prefs,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.prefs != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _syncJournal,
                    child: const Text('立即同步'),
                  ),
                  FilledButton(
                    onPressed: _openReminders,
                    child: const Text('提醒'),
                  ),
                  FilledButton(
                    onPressed: _openLedger,
                    child: const Text('对照账'),
                  ),
                  FilledButton(onPressed: _openSus, child: const Text('SUS')),
                  FilledButton(
                    onPressed: _openTasks,
                    child: const Text('任务计时'),
                  ),
                  Text(_statusLine()),
                ],
              ),
            ),
          Expanded(child: _measurementBody()),
        ],
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

  Widget _measurementBody() {
    if (_records.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '还没有测量记录。连接血压计、心率带或戒指后，数据会先写入本机日志。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
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
    );
  }

  String _statusLine() {
    final prefs = widget.prefs;
    if (prefs == null) {
      return '';
    }
    final faults = <String>[
      if (prefs.faultNetworkDown) '断网',
      if (prefs.faultTimeoutAfterCommit) '超时',
      if (prefs.faultClockSkew) '时钟',
      if (!prefs.autoSync) '手动同步',
    ];
    return faults.isEmpty ? '运行正常' : '降级：${faults.join('、')}';
  }

  Future<void> _journalMeasurement(
    HealthMeasurement measurement,
    BleScanHit hit,
  ) async {
    final study = widget.study;
    final prefs = widget.prefs;
    if (study == null || prefs == null) {
      return;
    }
    study.lastMeasurementAt = measurement.recordedAt.toUtc();
    final worn = measurement.values['sensor_contact'];
    await study.journal.append(
      CanonicalEvent(
        eventId: pathToken(
          '${hit.address}-${measurement.type}-${measurement.recordedAt.microsecondsSinceEpoch}',
        ),
        deviceId: pathToken(prefs.collectorId),
        sessionId: study.sessionId,
        sensorAddress: pathToken(hit.address),
        sensorKind: hit.driverId == 'yawell_ring'
            ? 'ring'
            : (hit.driverId ?? 'collector'),
        sensorModel: hit.name,
        measurementType: measurement.type,
        unit: measurement.unit.isEmpty ? 'unit' : measurement.unit,
        monotonicUs: measurement.recordedAt.microsecondsSinceEpoch,
        wallTimeUtc: prefs.faultClockSkew ? null : zulu(measurement.recordedAt),
        clockState: prefs.faultClockSkew ? 'INVALID' : 'NTP_SYNCED',
        operatingState: prefs.faultClockSkew ? 'CLOCK_DEGRADED' : 'NOMINAL',
        values: {
          ...measurement.values,
          'match_key': pathToken('${hit.address}-${measurement.type}'),
          if (worn == 'detected') 'worn': true,
          if (worn == 'not_detected') 'worn': false,
        },
      ),
    );
    if (worn == 'detected' || worn == 'not_detected') {
      await study.journal.append(
        CanonicalEvent(
          eventId: pathToken(
            'worn-${hit.address}-${measurement.recordedAt.microsecondsSinceEpoch}',
          ),
          deviceId: pathToken(prefs.collectorId),
          sessionId: study.sessionId,
          sensorAddress: pathToken(hit.address),
          sensorKind: 'heart_rate',
          sensorModel: hit.name,
          measurementType: 'worn_state',
          unit: 'state',
          monotonicUs: measurement.recordedAt.microsecondsSinceEpoch,
          wallTimeUtc: zulu(measurement.recordedAt),
          clockState: 'NTP_SYNCED',
          operatingState: 'NOMINAL',
          values: {
            'worn': worn == 'detected',
            'match_key': pathToken(hit.address),
          },
        ),
      );
    }
  }

  Future<void> _syncJournal() async {
    final study = widget.study;
    final prefs = widget.prefs;
    if (study == null || prefs == null || prefs.deviceToken.isEmpty) {
      _snack('先在设置里填写采集端令牌');
      return;
    }
    final base = await widget.settings.getServerBaseUrl();
    final worker = SyncWorker(
      journal: study.journal,
      baseUrl: base,
      token: prefs.deviceToken,
      client: widget.clientFactory?.call(base) == null ? null : null,
      faults: SyncFaults(
        networkDown: prefs.faultNetworkDown,
        timeoutAfterCommit: prefs.faultTimeoutAfterCommit,
        clockSkew: prefs.faultClockSkew,
      ),
    );
    final n = await worker.syncOnce();
    _snack('本轮同步完成 $n 条');
  }

  void _openReminders() {
    final study = widget.study;
    if (study == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReminderScreen(study: study),
      ),
    );
  }

  void _openLedger() {
    final study = widget.study;
    if (study == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => LedgerScreen(study: study)),
    );
  }

  void _openSus() {
    final study = widget.study;
    if (study == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => SusScreen(study: study)),
    );
  }

  void _openTasks() {
    final study = widget.study;
    if (study == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TaskLogScreen(study: study),
      ),
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');
