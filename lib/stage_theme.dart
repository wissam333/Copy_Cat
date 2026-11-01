// lib/stage_theme.dart — Stage Black design tokens + ThemeData (design.md).
import 'package:flutter/material.dart';

/// Stage Black: near-black stage, one voltage (gold), cream on dark.
/// Stage Paper: its light sibling — warm paper, ink text, same gold.
/// Tokens are mutable statics so the light/dark toggle can flip the whole
/// app at runtime (same pattern as the language switch); call sites read
/// them inside build, and the root rebuild repaints everything.
/// Spec lives in design.md — restyle from tokens here, not hex per screen.
class StageBlack {
  StageBlack._();

  static bool isLight = false;

  static Color bg = const Color(0xFF0A0A0F);
  static Color panel = const Color(0xFF14141B);
  static Color elev = const Color(0xFF1C1C26);
  static Color line = const Color(0x14FFFFFF);
  static Color lineStrong = const Color(0x3DFFFFFF);
  static Color gold = const Color(0xFFE8B44C);
  static Color onGold = const Color(0xFF14110A);
  static Color text = const Color(0xFFF5F2EA);
  static Color muted = const Color(0xFFA3A3B2);
  static Color ok = const Color(0xFF3ECF8E);
  static Color bad = const Color(0xFFE15D5D);

  static const displayFont = 'ReemKufi';
  static const uiFont = 'PlexArabic';

  /// Flip every token between the dark stage and the light paper palette.
  static void setLight(bool light) {
    isLight = light;
    bg = light ? const Color(0xFFF6F1E7) : const Color(0xFF0A0A0F);
    panel = light ? const Color(0xFFFFFFFF) : const Color(0xFF14141B);
    elev = light ? const Color(0xFFECE5D6) : const Color(0xFF1C1C26);
    line = light ? const Color(0x14101010) : const Color(0x14FFFFFF);
    lineStrong = light ? const Color(0x3D101010) : const Color(0x3DFFFFFF);
    gold = light ? const Color(0xFFB8860B) : const Color(0xFFE8B44C);
    onGold = light ? const Color(0xFFFFFBF0) : const Color(0xFF14110A);
    text = light ? const Color(0xFF201D15) : const Color(0xFFF5F2EA);
    muted = light ? const Color(0xFF6E695C) : const Color(0xFFA3A3B2);
    ok = light ? const Color(0xFF1F8F63) : const Color(0xFF3ECF8E);
    bad = light ? const Color(0xFFC44545) : const Color(0xFFE15D5D);
  }

  static ThemeData get theme {
    final colorScheme = ColorScheme(
      brightness: isLight ? Brightness.light : Brightness.dark,
      primary: gold,
      onPrimary: onGold,
      secondary: gold,
      onSecondary: onGold,
      secondaryContainer: elev,
      onSecondaryContainer: text,
      error: bad,
      onError: text,
      surface: panel,
      surfaceContainerHighest: elev,
      onSurface: text,
      onSurfaceVariant: muted,
      outline: lineStrong,
      outlineVariant: line,
      shadow: Colors.black,
      scrim: Colors.black,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: uiFont,
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: text),
        titleTextStyle: TextStyle(
          fontFamily: uiFont,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: onGold,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: TextStyle(
            fontFamily: uiFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: lineStrong),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: TextStyle(
            fontFamily: uiFont,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size.fromHeight(48),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: gold),
        ),
        labelStyle: TextStyle(fontFamily: uiFont, fontSize: 14, color: muted),
        hintStyle: TextStyle(fontFamily: uiFont, fontSize: 14, color: muted),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: elev,
        labelStyle: TextStyle(fontFamily: uiFont, fontSize: 14, color: text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: line),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(
          fontFamily: uiFont,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: text,
        ),
        contentTextStyle: TextStyle(
          fontFamily: uiFont,
          fontSize: 14,
          color: text,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: elev,
        contentTextStyle: TextStyle(
          fontFamily: uiFont,
          fontSize: 14,
          color: text,
        ),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: gold),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? gold : elev),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? onGold : text),
          side: WidgetStatePropertyAll(BorderSide(color: lineStrong)),
        ),
      ),
      dividerTheme: DividerThemeData(color: line),
      textTheme: TextTheme(
        displayLarge: TextStyle(fontFamily: displayFont, fontSize: 40, fontWeight: FontWeight.w700, color: text, height: 1.0),
        headlineMedium: TextStyle(fontFamily: uiFont, fontSize: 22, fontWeight: FontWeight.w700, color: text),
        titleLarge: TextStyle(fontFamily: uiFont, fontSize: 18, fontWeight: FontWeight.w700, color: text),
        titleMedium: TextStyle(fontFamily: uiFont, fontSize: 16, fontWeight: FontWeight.w600, color: text),
        bodyLarge: TextStyle(fontFamily: uiFont, fontSize: 15, fontWeight: FontWeight.w400, color: text),
        bodyMedium: TextStyle(fontFamily: uiFont, fontSize: 14, fontWeight: FontWeight.w400, color: text),
        labelLarge: TextStyle(fontFamily: uiFont, fontSize: 14, fontWeight: FontWeight.w600, color: text),
        labelSmall: TextStyle(fontFamily: uiFont, fontSize: 12, fontWeight: FontWeight.w500, color: muted),
      ),
    );
  }

  /// Soft gold glow behind the top of the stage (design.md page shell).
  static Widget background({required Widget child}) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.7),
                  radius: 1.1,
                  colors: [gold.withValues(alpha: 0.16), bg.withValues(alpha: 0.0)],
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        child,
      ],
    );
  }

  /// The AppBar-strip slice of the page glow, so AppBar pages don't show
  /// a dead black band above the glowing body (design.md page shell).
  /// Drop into `AppBar(flexibleSpace: StageBlack.appBarGlow())`.
  static Widget appBarGlow() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.0, -1.2),
            radius: 1.6,
            colors: [gold.withValues(alpha: 0.16), bg.withValues(alpha: 0.0)],
          ),
        ),
        child: const SizedBox.expand(),
      );
}
