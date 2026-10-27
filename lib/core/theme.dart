import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Token desain PawFinder (warna, radius, spasi).
class PF {
  PF._();
  static const primary = Color(0xFF1E6BFF);
  static const primaryDark = Color(0xFF0B4FD6);
  static const primaryLight = Color(0xFFE8F0FF);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const accent = Color(0xFF8B5CF6);

  static const rCard = 20.0;
  static const rButton = 16.0;
  static const rInput = 14.0;
  static const rChip = 999.0;

  static const margin = 20.0; // margin layar
  static const gutter = 16.0;

  static const shadowColor = Color(0x1A1E6BFF); // rgba(30,107,255,0.10)
}

/// Palet yang berubah antara mode Terang dan Gelap (Variable Modes).
class PFPalette extends ThemeExtension<PFPalette> {
  const PFPalette({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.text,
    required this.textSecondary,
    required this.border,
    required this.primaryLight,
    required this.primaryText,
    required this.successBg,
    required this.successFg,
    required this.dangerBg,
    required this.warningBg,
    required this.accentBg,
    required this.shadow,
  });

  final bool isDark;
  final Color background, surface, text, textSecondary, border, primaryLight, primaryText;
  final Color successBg, successFg, dangerBg, warningBg, accentBg, shadow;

  static const light = PFPalette(
    isDark: false,
    background: Color(0xFFF5F9FF),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF0F1B3D),
    // Sedikit lebih gelap dari #6B7A99 agar kontras teks kecil lolos WCAG AA.
    textSecondary: Color(0xFF5B6A8A),
    border: Color(0xFFE1E8F5),
    primaryLight: Color(0xFFE8F0FF),
    primaryText: Color(0xFF1E6BFF),
    successBg: Color(0xFFE7F8EE),
    successFg: Color(0xFF15803D),
    dangerBg: Color(0xFFFDECEC),
    warningBg: Color(0xFFFEF3DC),
    accentBg: Color(0xFFF0EAFE),
    shadow: Color(0x1A1E6BFF),
  );

  static const dark = PFPalette(
    isDark: true,
    background: Color(0xFF0B1226),
    surface: Color(0xFF131C36),
    text: Color(0xFFEAF0FF),
    textSecondary: Color(0xFF9AA8C7),
    border: Color(0xFF25304F),
    primaryLight: Color(0xFF17284F),
    primaryText: Color(0xFF6AA0FF),
    successBg: Color(0xFF12301F),
    successFg: Color(0xFF6EE7A0),
    dangerBg: Color(0xFF3B1717),
    warningBg: Color(0xFF3A2C0B),
    accentBg: Color(0xFF2A1F4D),
    shadow: Color(0x66000000),
  );

  @override
  PFPalette copyWith() => this;

  @override
  PFPalette lerp(ThemeExtension<PFPalette>? other, double t) {
    if (other is! PFPalette) return this;
    return t < 0.5 ? this : other;
  }
}

/// Text Styles: Display 32/Bold, H1 24/Bold, H2 20/SemiBold, H3 17/SemiBold,
/// Body 15/Regular, Caption 13/Regular, Micro 11/Medium.
class PFText {
  const PFText(this.p);
  final PFPalette p;

  TextStyle get display => TextStyle(fontSize: 32, fontWeight: FontWeight.w700, height: 1.18, letterSpacing: -0.6, color: p.text);
  TextStyle get h1 => TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.25, letterSpacing: -0.4, color: p.text);
  TextStyle get h2 => TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.3, letterSpacing: -0.2, color: p.text);
  TextStyle get h3 => TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.3, color: p.text);
  TextStyle get body => TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.4, color: p.text);
  TextStyle get bodyStrong => TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4, color: p.text);
  TextStyle get bodySecondary => TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.45, color: p.textSecondary);
  TextStyle get caption => TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.35, color: p.textSecondary);
  TextStyle get captionStrong => TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.35, color: p.text);
  TextStyle get micro => TextStyle(fontSize: 11, fontWeight: FontWeight.w500, height: 1.3, color: p.textSecondary);
}

extension PFContext on BuildContext {
  PFPalette get pf => Theme.of(this).extension<PFPalette>() ?? PFPalette.light;
  PFText get tx => PFText(pf);
  double get bottomInset => MediaQuery.of(this).padding.bottom;
  double get topInset => MediaQuery.of(this).padding.top;
}

extension ColorX on Color {
  /// Warna yang sama dengan opasitas tertentu (0..1), tanpa API yang berubah antar versi Flutter.
  Color o(double opacity) => withAlpha((opacity * 255).round().clamp(0, 255).toInt());
}

List<BoxShadow> softShadow(PFPalette p) => [
      BoxShadow(color: p.shadow, blurRadius: 24, offset: const Offset(0, 8)),
    ];

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? PFPalette.dark : PFPalette.light;
  final baseText = ThemeData(brightness: brightness).textTheme;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(seedColor: PF.primary, brightness: brightness).copyWith(primary: PF.primary, surface: p.surface),
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    textTheme: GoogleFonts.interTextTheme(baseText).apply(bodyColor: p.text, displayColor: p.text),
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    dividerColor: p.border,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      // Gunakan builder yang tersedia lintas versi Flutter dan platform.
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
    }),
    extensions: <ThemeExtension<dynamic>>[p],
  );
}
