import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/app.dart';
import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/ble/device_manager.dart';
import 'package:bylwapp/data/memory_health_repository.dart';
import 'package:bylwapp/models/health_record.dart';
import 'package:bylwapp/settings/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bottom navigation reaches each section', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      BylwApp(
        repository: MemoryHealthRepository(),
        settings: MemorySettingsStore(),
        ble: FakeBleClient(),
        prefs: CollectorPrefs(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsWidgets);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('设备'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('开始扫描'), findsOneWidget);
    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();
    expect(find.text('提醒需要本地日志。从正常启动进入后即可使用。'), findsOneWidget);
    await tester.tap(find.text('研究'));
    await tester.pumpAndSettle();
    expect(find.text('SUS 问卷'), findsOneWidget);
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('演示数据'), findsOneWidget);
  });

  testWidgets('home keeps a connected strap after leaving the scan page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final devices = BleDeviceManager()
      ..applyLink(
        const BleLink(
          phase: BleLinkPhase.connected,
          address: 'AA:BB:CC:DD:EE:11',
          name: 'H303',
          driverId: 'heart_rate',
        ),
      )
      ..addReading(
        'heart_rate',
        'AA:BB:CC:DD:EE:11',
        HealthMeasurement(
          type: 'heart_rate',
          unit: 'bpm',
          recordedAt: DateTime.utc(2026, 11, 27, 8, 1, 2),
          values: const {'bpm': 72, 'sensor_contact': 'detected'},
        ),
      );
    await tester.pumpWidget(
      BylwApp(
        repository: MemoryHealthRepository(),
        settings: MemorySettingsStore(),
        ble: FakeBleClient(),
        prefs: CollectorPrefs(),
        devices: devices,
      ),
    );
    await tester.pump();
    expect(find.textContaining('已连接'), findsWidgets);
    expect(find.textContaining('72'), findsWidgets);
    expect(find.textContaining('已接触'), findsWidgets);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('设备'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('已连接'), findsWidgets);
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    expect(find.textContaining('72'), findsWidgets);
    await tester.tap(find.text('心率带 H303'));
    await tester.pumpAndSettle();
    expect(find.text('断开'), findsOneWidget);
    expect(find.textContaining('72 bpm'), findsOneWidget);
  });

  testWidgets('demo readings stay on screen and are labeled', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final prefs = CollectorPrefs()..showDemo = true;
    await tester.pumpWidget(
      BylwApp(
        repository: MemoryHealthRepository(),
        settings: MemorySettingsStore(),
        ble: FakeBleClient(),
        prefs: prefs,
      ),
    );
    await tester.pump();
    expect(find.textContaining('演示数据'), findsWidgets);
    expect(find.textContaining('118/76'), findsWidgets);
  });
}
