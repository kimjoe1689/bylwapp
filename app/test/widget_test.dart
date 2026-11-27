import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/app.dart';
import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/data/memory_health_repository.dart';
import 'package:bylwapp/models/health_record.dart';
import 'package:bylwapp/screens/settings_screen.dart';
import 'package:bylwapp/settings/settings_store.dart';

void main() {
  testWidgets('home lists a stored blood pressure measurement', (tester) async {
    final repository = MemoryHealthRepository();
    await repository.upsertDevice(
      const HealthDevice(
        name: 'YE680B',
        kind: 'blood_pressure',
        address: 'AA:BB',
        model: 'Yuwell YE680B',
      ),
    );
    await repository.insertMeasurement(
      'AA:BB',
      HealthMeasurement(
        type: 'blood_pressure',
        unit: 'mmHg',
        recordedAt: DateTime.utc(2026, 11, 27, 8, 15, 9),
        values: const {'systolic': 120, 'diastolic': 80, 'pulse': 72},
      ),
    );

    await tester.pumpWidget(
      BylwApp(
        repository: repository,
        settings: MemorySettingsStore(),
        ble: FakeBleClient(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('120/80'), findsOneWidget);
    expect(find.textContaining('YE680B'), findsOneWidget);
  });

  testWidgets('settings saves the server base url', (tester) async {
    final settings = MemorySettingsStore();
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settings: settings)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'http://10.0.0.8:8080');
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(await settings.getServerBaseUrl(), 'http://10.0.0.8:8080');
  });
}
