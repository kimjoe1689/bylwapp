import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/api/server_client.dart';
import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/ble/device_manager.dart';
import 'package:bylwapp/ble/driver_registry.dart';
import 'package:bylwapp/data/health_repository.dart';
import 'package:bylwapp/journal/canonical_event.dart';
import 'package:bylwapp/models/health_record.dart';
import 'package:bylwapp/screens/debug_screen.dart';
import 'package:bylwapp/screens/device_detail_screen.dart';
import 'package:bylwapp/screens/scan_screen.dart';
import 'package:bylwapp/screens/settings_screen.dart';
import 'package:bylwapp/screens/study_screens.dart';
import 'package:bylwapp/settings/settings_store.dart';
import 'package:bylwapp/ui/demo_catalog.dart';
import 'package:bylwapp/ui/home_dashboard.dart';
import 'package:bylwapp/ui/research_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.repository,
    required this.settings,
    required this.ble,
    this.clientFactory,
    this.study,
    this.prefs,
    this.devices,
  });

  final HealthRepository repository;
  final SettingsStore settings;
  final BleClient ble;
  final ServerClient Function(String baseUrl)? clientFactory;
  final StudyBundle? study;
  final CollectorPrefs? prefs;
  final BleDeviceManager? devices;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  List<LocalRecord> _records = const [];
  late final BleDeviceManager _devices = widget.devices ?? BleDeviceManager();
  StreamSubscription<BleLink>? _links;

  @override
  void initState() {
    super.initState();
    _devices.addListener(_onDevices);
    _links = widget.ble.links.listen(_devices.applyLink);
    _reload();
  }

  @override
  void dispose() {
    _links?.cancel();
    _devices.removeListener(_onDevices);
    if (widget.devices == null) {
      _devices.dispose();
    }
    super.dispose();
  }

  void _onDevices() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    final records = await widget.repository.listRecent();
    if (mounted) setState(() => _records = records);
  }

  List<LocalRecord> get _visible {
    if (widget.prefs?.showDemo == true) return DemoCatalog.records();
    return _records;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeDashboard(
        records: _visible,
        demo: widget.prefs?.showDemo == true,
        study: widget.study,
        prefs: widget.prefs,
        settings: widget.settings,
        clientFactory: widget.clientFactory,
        onChanged: () => setState(() {}),
        devices: _devices,
        onOpenReminders: () => setState(() => _index = 2),
        onOpenDevice: _openInsight,
      ),
      ScanScreen(
        repository: widget.repository,
        ble: widget.ble,
        embedded: true,
        devices: _devices,
        onReading: _onReading,
        onOpenKind: _openInsight,
      ),
      widget.study == null
          ? const _NeedStudy(text: '提醒需要本地日志。从正常启动进入后即可使用。')
          : ReminderScreen(study: widget.study!, embedded: true),
      ResearchPage(study: widget.study),
      SettingsScreen(
        settings: widget.settings,
        prefs: widget.prefs,
        clientFactory: widget.clientFactory,
        embedded: true,
        onOpenDebug: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) =>
                  DebugScreen(ble: widget.ble, prefs: widget.prefs),
            ),
          );
        },
        onChanged: () => setState(() {}),
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.bluetooth_outlined),
            selectedIcon: Icon(Icons.bluetooth),
            label: '设备',
          ),
          NavigationDestination(
            icon: Icon(Icons.medication_outlined),
            selectedIcon: Icon(Icons.medication),
            label: '提醒',
          ),
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: '研究',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }

  void _openInsight(String kind) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => DeviceDetailScreen(
          kind: kind,
          devices: _devices,
          journal: widget.study?.journal,
          demo: widget.prefs?.showDemo == true,
          ble: widget.ble,
          onReading: _onReading,
          onRequestScan: () => setState(() => _index = 1),
        ),
      ),
    );
  }

  Future<void> _onReading(HealthMeasurement measurement, BleScanHit hit) async {
    final kind = driverById(hit.driverId)?.kind ?? measurement.type;
    _devices.addReading(kind, hit.address, measurement);
    if (widget.prefs?.showDemo == true) {
      return;
    }
    if (!_devices.gate.shouldPersist(
      '${hit.address}|${measurement.type}',
      DateTime.now(),
    )) {
      return;
    }
    final driver = driverById(hit.driverId);
    await widget.repository.upsertDevice(
      HealthDevice(
        name: hit.name,
        kind: kind,
        address: hit.address,
        model: driver?.targetModel ?? hit.name,
      ),
    );
    await widget.repository.insertMeasurement(hit.address, measurement);
    await _journalMeasurement(measurement, hit);
    await _reload();
  }

  Future<void> _journalMeasurement(
    HealthMeasurement measurement,
    BleScanHit hit,
  ) async {
    final study = widget.study;
    final prefs = widget.prefs;
    if (study == null || prefs == null || prefs.showDemo) return;
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
    await _reload();
  }
}

class _NeedStudy extends StatelessWidget {
  const _NeedStudy({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
