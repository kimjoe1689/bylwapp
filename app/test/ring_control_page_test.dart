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
    expect(find.textContaining('电量 78%'), findsOneWidget);
    expect(find.textContaining('14:20'), findsOneWidget);
    expect(find.text('72'), findsWidgets);
    expect(find.text('找戒指'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('恢复出厂'), 300);
    expect(find.text('恢复出厂'), findsOneWidget);
    expect(find.text('不支持'), findsOneWidget);
    expect(find.textContaining('73 12'), findsOneWidget);
  });
}
