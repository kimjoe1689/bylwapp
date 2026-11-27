import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/api/server_client.dart';
import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/ble/device_manager.dart';
import 'package:bylwapp/data/health_repository.dart';
import 'package:bylwapp/screens/study_screens.dart';
import 'package:bylwapp/settings/settings_store.dart';
import 'package:bylwapp/ui/app_shell.dart';
import 'package:bylwapp/ui/app_theme.dart';

class BylwApp extends StatelessWidget {
  const BylwApp({
    super.key,
    required this.repository,
    required this.settings,
    required this.ble,
    this.clientFactory,
    this.study,
    this.prefs,
    this.devices,
    this.autoRegister = false,
  });

  final HealthRepository repository;
  final SettingsStore settings;
  final BleClient ble;
  final ServerClient Function(String baseUrl)? clientFactory;
  final StudyBundle? study;
  final CollectorPrefs? prefs;
  final BleDeviceManager? devices;

  /// Production turns this on. Tests leave it off so they do not call the network.
  final bool autoRegister;

  @override
  Widget build(BuildContext context) {
    final elder = prefs?.elderMode ?? false;
    return MaterialApp(
      title: 'bylwapp',
      theme: buildBylwTheme(brightness: Brightness.light, elder: elder),
      darkTheme: buildBylwTheme(brightness: Brightness.dark, elder: elder),
      home: AppShell(
        repository: repository,
        settings: settings,
        ble: ble,
        clientFactory: clientFactory,
        study: study,
        prefs: prefs,
        devices: devices,
        autoRegister: autoRegister,
      ),
    );
  }
}
