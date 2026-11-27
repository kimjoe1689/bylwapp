import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/app.dart';
import 'package:bylwapp/ble/ble_client.dart';
import 'package:bylwapp/data/memory_health_repository.dart';
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
    expect(find.textContaining('118/76'), findsOneWidget);
  });
}
