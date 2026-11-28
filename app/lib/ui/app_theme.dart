import 'package:material_ui/material_ui.dart';

ThemeData buildBylwTheme({
  required Brightness brightness,
  required bool elder,
}) {
  final seed = elder ? const Color(0xFF08342C) : const Color(0xFF0E7C73);
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    primary: brightness == Brightness.light
        ? const Color(0xFF0E7C73)
        : const Color(0xFF8EE0D4),
    surface: brightness == Brightness.light
        ? const Color(0xFFF3F7F6)
        : const Color(0xFF101816),
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final factor = elder ? 1.28 : 1.0;
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: base.textTheme.apply(
      fontSizeFactor: factor,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    cardTheme: CardThemeData(
      elevation: elder ? 0 : 1,
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(elder ? 12 : 22),
        side: elder
            ? BorderSide(color: scheme.onSurface, width: 1.4)
            : BorderSide.none,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: elder ? 84 : 72,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: elder ? 14 : 12, fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: Size(64, elder ? 56 : 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size(64, elder ? 56 : 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}
