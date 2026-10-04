import 'app_motion.dart';
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

  Color get onAccent =>
      accent.computeLuminance() > .179 ? const Color(0xFF211D17) : Colors.white;

  static const emerald = AppPalette(
    id: 'emerald',
    name: 'Ivory',
    scaffold: Color(0xFFF4F0E8),
    surface: Color(0xFFF4F0E8),
    surfaceRaised: Color(0xFFFCFAF5),
    accent: Color(0xFF80643B),
    accentSoft: Color(0xFFEBE2D2),
    text: Color(0xFF302B26),
    muted: Color(0xFF7A7267),
    surfaceText: Color(0xFF302B26),
    surfaceMuted: Color(0xFF7A7267),
    border: Color(0xFFDED5C4),
    shadow: Color(0x292C2416),
    readerBar: Color(0xFFF4F0E8),
    readerIcon: Color(0xFF80643B),
  );

  static const darkEmerald = AppPalette(
    id: 'dark_emerald',
    name: 'Charcoal',
    scaffold: Color(0xFF24211E),
    surface: Color(0xFFF4F0E8),
    surfaceRaised: Color(0xFFFCFAF5),
    accent: Color(0xFF80643B),
    accentSoft: Color(0xFFEBE2D2),
    text: Color(0xFFFAF6EF),
    muted: Color(0xCDDCD3C6),
    surfaceText: Color(0xFF302B26),
    surfaceMuted: Color(0xFF7A7267),
    border: Color(0xFFDED5C4),
    shadow: Color(0x66000000),
    readerBar: Color(0xFF24211E),
    readerIcon: Color(0xFFFAF6EF),
  );

  static const blackDark = AppPalette(
    id: 'black_dark',
    name: 'Dark',
    scaffold: Color(0xFF171615),
    surface: Color(0xFF23211F),
    surfaceRaised: Color(0xFF302D29),
    accent: Color(0xFFC2A574),
    accentSoft: Color(0xFF3B3225),
    text: Color(0xFFEEEEEE),
    muted: Color(0xFFBDB4A7),
    surfaceText: Color(0xFFDDDDDD),
    surfaceMuted: Color(0xFFB8AFA2),
    border: Color(0xFF333333),
    shadow: Color(0x88000000),
    readerBar: Color(0xFF23211F),
    readerIcon: Color(0xFFBDB4A7),
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
          onPrimary: onAccent,
          surface: surface,
          onSurface: surfaceText,
        );

    return ThemeData(
      colorScheme: scheme,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PremiumPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: PremiumPageTransitionsBuilder(),
          TargetPlatform.windows: PremiumPageTransitionsBuilder(),
          TargetPlatform.linux: PremiumPageTransitionsBuilder(),
        },
      ),
      fontFamily: 'Inter',
      scaffoldBackgroundColor: scaffold,
      dialogTheme: DialogThemeData(backgroundColor: surface),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: text,
        elevation: 0,
      ),
      textTheme:
          ThemeData(
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
