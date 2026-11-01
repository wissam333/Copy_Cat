// lib/stage_theme.dart — Stage Black design tokens + ThemeData (design.md).
import 'package:flutter/material.dart';

/// Stage Black: near-black stage, one voltage (gold), cream on dark.
/// Spec lives in design.md — restyle from tokens here, not hex per screen.
class StageBlack {
  StageBlack._();

  static const bg = Color(0xFF0A0A0F);
  static const panel = Color(0xFF14141B);
  static const elev = Color(0xFF1C1C26);
  static const line = Color(0x14FFFFFF);
  static const lineStrong = Color(0x3DFFFFFF);
  static const gold = Color(0xFFE8B44C);
  static const onGold = Color(0xFF14110A);
  static const text = Color(0xFFF5F2EA);
  static const muted = Color(0xFFA3A3B2);
  static const ok = Color(0xFF3ECF8E);
  static const bad = Color(0xFFE15D5D);

  static const displayFont = 'ReemKufi';
  static const uiFont = 'PlexArabic';

  static ThemeData get theme {
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
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
      fontFamily: StageBlack.uiFont,
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: text),
        titleTextStyle: const TextStyle(
          fontFamily: StageBlack.uiFont,
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
          textStyle: const TextStyle(
            fontFamily: StageBlack.uiFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: const BorderSide(color: StageBlack.lineStrong),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: StageBlack.uiFont,
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
          borderSide: const BorderSide(color: StageBlack.gold),
        ),
        labelStyle: TextStyle(fontFamily: StageBlack.uiFont, fontSize: 14, color: StageBlack.muted),
        hintStyle: TextStyle(fontFamily: StageBlack.uiFont, fontSize: 14, color: StageBlack.muted),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: StageBlack.elev,
        labelStyle: const TextStyle(fontFamily: StageBlack.uiFont, fontSize: 14, color: StageBlack.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: const BorderSide(color: StageBlack.line),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: StageBlack.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(
          fontFamily: StageBlack.uiFont,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: StageBlack.text,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: StageBlack.uiFont,
          fontSize: 14,
          color: StageBlack.text,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: StageBlack.elev,
        contentTextStyle: const TextStyle(
          fontFamily: StageBlack.uiFont,
          fontSize: 14,
          color: StageBlack.text,
        ),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: StageBlack.gold),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? StageBlack.gold
                  : StageBlack.elev),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? StageBlack.onGold
                  : StageBlack.text),
          side: WidgetStatePropertyAll(
              BorderSide(color: StageBlack.lineStrong)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: StageBlack.line),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontFamily: StageBlack.displayFont, fontSize: 40, fontWeight: FontWeight.w700, color: StageBlack.text, height: 1.0),
        headlineMedium: TextStyle(fontFamily: StageBlack.uiFont, fontSize: 22, fontWeight: FontWeight.w700, color: StageBlack.text),
        titleLarge: TextStyle(fontFamily: StageBlack.uiFont, fontSize: 18, fontWeight: FontWeight.w700, color: StageBlack.text),
        titleMedium: TextStyle(fontFamily: StageBlack.uiFont, fontSize: 16, fontWeight: FontWeight.w600, color: StageBlack.text),
        bodyLarge: TextStyle(fontFamily: StageBlack.uiFont, fontSize: 15, fontWeight: FontWeight.w400, color: StageBlack.text),
        bodyMedium: TextStyle(fontFamily: StageBlack.uiFont, fontSize: 14, fontWeight: FontWeight.w400, color: StageBlack.text),
        labelLarge: TextStyle(fontFamily: StageBlack.uiFont, fontSize: 14, fontWeight: FontWeight.w600, color: StageBlack.text),
        labelSmall: TextStyle(fontFamily: StageBlack.uiFont, fontSize: 12, fontWeight: FontWeight.w500, color: StageBlack.muted),
      ),
    );
  }

  /// Soft gold glow behind the top of the stage (design.md page shell).
  static Widget background({required Widget child}) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.0, -0.7),
                  radius: 1.1,
                  colors: [
                    Color(0x29E8B44C), // gold at 16%
                    Color(0x000A0A0F),
                  ],
                ),
              ),
              child: SizedBox.expand(),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
