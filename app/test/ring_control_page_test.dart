import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:bylwapp/ui/ring_control_page.dart';

void main() {
  testWidgets('ring page shows live values, tools, and unsupported stress', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ringPreviewApp(dark: false));
    await tester.pump();
    expect(find.text('R12_0607'), findsOneWidget);
    expect(find.text('Colmi R12'), findsOneWidget);
    expect(find.textContaining('体温'), findsNothing);
    expect(find.text('已连接'), findsOneWidget);
    expect(find.textContaining('电量 78%'), findsWidgets);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scroll.position.pixels, 0);
    expect(find.textContaining('14:20'), findsOneWidget);
    expect(find.text('72'), findsWidgets);
    expect(find.text('事件探索'), findsOneWidget);
    expect(find.text('每5分钟测30秒'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('找戒指'), 400);
    expect(find.text('找戒指'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('恢复出厂'), 300);
    expect(find.text('恢复出厂'), findsOneWidget);
    expect(find.text('不支持'), findsOneWidget);
    expect(find.textContaining('6.1 公里'), findsOneWidget);
    expect(find.textContaining('昨夜睡眠'), findsOneWidget);
    expect(find.textContaining('unknown 0x55'), findsOneWidget);
    expect(find.textContaining('55 00'), findsNothing);
    expect(find.text('开发者信息'), findsOneWidget);
    await tester.tap(find.text('开发者信息'));
    await tester.pump();
    expect(find.textContaining('55 00'), findsOneWidget);
  });
}
