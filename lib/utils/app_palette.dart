import 'package:flutter/material.dart';

class AppPalette extends ThemeExtension<AppPalette> {
  final String id;
  final String name;
  final Color scaffold;
  final Color surface;
  final Color surfaceRaised;
  final Color accent;
  final Color accentSoft;
  final Color text;
  final Color muted;
  final Color surfaceText;
  final Color surfaceMuted;
  final Color border;
  final Color shadow;
  final Color readerBar;
  final Color readerIcon;

  const AppPalette({
    required this.id,
    required this.name,
    required this.scaffold,
    required this.surface,
    required this.surfaceRaised,
    required this.accent,
    required this.accentSoft,
    required this.text,
    required this.muted,
    required this.surfaceText,
    required this.surfaceMuted,
    required this.border,
    required this.shadow,
    required this.readerBar,
    required this.readerIcon,
  });

  bool get isDark =>
      ThemeData.estimateBrightnessForColor(scaffold) == Brightness.dark;

  static const emerald = AppPalette(
    id: 'emerald',
    name: 'Emerald',
    scaffold: Color(0xFFEBF3EC),
    surface: Color(0xFFEBF3EC),
    surfaceRaised: Color(0xFFF6FBF5),
    accent: Color(0xFF025C32),
    accentSoft: Color(0xFFD9EBDD),
    text: Color(0xFF13251A),
    muted: Color(0xFF5F6F64),
    surfaceText: Color(0xFF13251A),
    surfaceMuted: Color(0xFF5F6F64),
    border: Color(0xFFC9D9CC),
    shadow: Color(0x22000000),
    readerBar: Color(0xFFEBF3EC),
    readerIcon: Color(0xFF025C32),
  );

  static const darkEmerald = AppPalette(
    id: 'dark_emerald',
    name: 'Dark Emerald',
    scaffold: Color(0xFF112608),
    surface: Color(0xFFEBF3EC),
    surfaceRaised: Color(0xFFF6FBF5),
    accent: Color(0xFF025C32),
    accentSoft: Color(0xFFD9EBDD),
    text: Color(0xFFF7FBF7),
    muted: Color(0xCDDDE8D0),
    surfaceText: Color(0xFF13251A),
    surfaceMuted: Color(0xFF5F6F64),
    border: Color(0xFFC9D9CC),
    shadow: Color(0x66000000),
    readerBar: Color(0xFF112608),
    readerIcon: Color(0xFFF7FBF7),
  );

  static const blackDark = AppPalette(
    id: 'black_dark',
    name: 'Dark',
    scaffold: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    surfaceRaised: Color(0xFF2A2A2A),
    accent: Color(0xFF4CAF7D),
    accentSoft: Color(0xFF163326),
    text: Color(0xFFEEEEEE),
    muted: Color(0xFF888888),
    surfaceText: Color(0xFFDDDDDD),
    surfaceMuted: Color(0xFF666666),
    border: Color(0xFF333333),
    shadow: Color(0x88000000),
    readerBar: Color(0xFF1E1E1E),
    readerIcon: Color(0xFF888888),
  );

  static AppPalette forDarkMode(bool darkMode) {
    return darkMode ? darkEmerald : emerald;
  }

  static AppPalette forTheme({bool mushafDark = false, bool appDark = false}) {
    if (appDark) return blackDark;
    return emerald;
  }

  static AppPalette of(BuildContext context) {
    return Theme.of(context).extension<AppPalette>() ?? emerald;
  }

  ThemeData toThemeData() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: isDark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: accent,
          onPrimary: Colors.white,
          surface: surface,
          onSurface: surfaceText,
        );

    return ThemeData(
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: Colors.black,
      dialogTheme: DialogThemeData(backgroundColor: surface),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: text,
        elevation: 0,
      ),
      textTheme: ThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
      ).textTheme.apply(
        bodyColor: surfaceText,
        displayColor: surfaceText,
        fontFamily: 'Inter',
      ),
      extensions: [this],
      useMaterial3: true,
    );
  }

  @override
  AppPalette copyWith({
    String? id,
    String? name,
    Color? scaffold,
    Color? surface,
    Color? surfaceRaised,
    Color? accent,
    Color? accentSoft,
    Color? text,
    Color? muted,
    Color? surfaceText,
    Color? surfaceMuted,
    Color? border,
    Color? shadow,
    Color? readerBar,
    Color? readerIcon,
  }) {
    return AppPalette(
      id: id ?? this.id,
      name: name ?? this.name,
      scaffold: scaffold ?? this.scaffold,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      surfaceText: surfaceText ?? this.surfaceText,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      shadow: shadow ?? this.shadow,
      readerBar: readerBar ?? this.readerBar,
      readerIcon: readerIcon ?? this.readerIcon,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;

    return copyWith(
      scaffold: Color.lerp(scaffold, other.scaffold, t),
      surface: Color.lerp(surface, other.surface, t),
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t),
      accent: Color.lerp(accent, other.accent, t),
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t),
      text: Color.lerp(text, other.text, t),
      muted: Color.lerp(muted, other.muted, t),
      surfaceText: Color.lerp(surfaceText, other.surfaceText, t),
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t),
      border: Color.lerp(border, other.border, t),
      shadow: Color.lerp(shadow, other.shadow, t),
      readerBar: Color.lerp(readerBar, other.readerBar, t),
      readerIcon: Color.lerp(readerIcon, other.readerIcon, t),
    );
  }
}
