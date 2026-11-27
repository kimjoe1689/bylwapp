import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/api/server_client.dart';
import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/data/health_repository.dart';
import 'package:bylwapp/screens/home_screen.dart';
import 'package:bylwapp/screens/study_screens.dart';
import 'package:bylwapp/settings/settings_store.dart';

class BylwApp extends StatelessWidget {
  const BylwApp({
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
  Widget build(BuildContext context) {
    final elder = prefs?.elderMode ?? false;
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F6E56)),
    );
    return MaterialApp(
      title: 'bylwapp',
      theme: elder
          ? base.copyWith(
              colorScheme: const ColorScheme.highContrastLight(
                primary: Color(0xFF0B3D2E),
                onPrimary: Colors.white,
              ),
              textTheme: base.textTheme.apply(fontSizeFactor: 1.35),
              visualDensity: VisualDensity.standard,
            )
          : base,
      home: HomeScreen(
        repository: repository,
        settings: settings,
        ble: ble,
        clientFactory: clientFactory,
        study: study,
        prefs: prefs,
      ),
    );
  }
}
