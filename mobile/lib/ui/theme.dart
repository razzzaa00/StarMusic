import 'package:flutter/material.dart';

class StarColors {
  static const background = Color(0xFF0B0B0C);
  static const surface = Color(0xFF151517);
  static const surfaceHigh = Color(0xFF1E1F22);
  static const line = Color(0x14FFFFFF);
  static const text = Color(0xFFEDEDEE);
  static const textDim = Color(0xFF9A9AA0);
  static const accent = Color(0xFF5AA9FF);
  static const onAccent = Color(0xFF04111F);
}

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  final scheme = const ColorScheme.dark(
    primary: StarColors.accent,
    onPrimary: StarColors.onAccent,
    secondary: StarColors.accent,
    surface: StarColors.background,
    onSurface: StarColors.text,
    surfaceContainerHighest: StarColors.surfaceHigh,
    outlineVariant: StarColors.line,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: StarColors.background,
    splashFactory: NoSplash.splashFactory,
    appBarTheme: const AppBarTheme(backgroundColor: StarColors.background, surfaceTintColor: Colors.transparent, elevation: 0, centerTitle: false),
    dividerTheme: const DividerThemeData(color: StarColors.line, thickness: 1, space: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: StarColors.background,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: 60,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(fontSize: 11, color: s.contains(WidgetState.selected) ? StarColors.text : StarColors.textDim)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? StarColors.accent : StarColors.textDim)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: StarColors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: StarColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: StarColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: StarColors.accent)),
      hintStyle: const TextStyle(color: StarColors.textDim),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      activeTrackColor: StarColors.accent,
      inactiveTrackColor: Color(0x29FFFFFF),
      thumbColor: StarColors.text,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: StarColors.surface, surfaceTintColor: Colors.transparent, showDragHandle: true),
    snackBarTheme: const SnackBarThemeData(backgroundColor: StarColors.surfaceHigh, contentTextStyle: TextStyle(color: StarColors.text), behavior: SnackBarBehavior.floating),
  );
}
