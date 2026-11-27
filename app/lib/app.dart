import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/api/server_client.dart';
import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/data/health_repository.dart';
import 'package:bylwapp/screens/home_screen.dart';
import 'package:bylwapp/settings/settings_store.dart';

class BylwApp extends StatelessWidget {
  const BylwApp({
    super.key,
    required this.repository,
    required this.settings,
    required this.ble,
    this.clientFactory,
  });

  final HealthRepository repository;
  final SettingsStore settings;
  final BleClient ble;
  final ServerClient Function(String baseUrl)? clientFactory;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'bylwapp',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F6E56)),
      ),
      home: HomeScreen(
        repository: repository,
        settings: settings,
        ble: ble,
        clientFactory: clientFactory,
      ),
    );
  }
}
