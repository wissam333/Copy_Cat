// lib/screens/splash_screen.dart — branded entry, then auto-enters home.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../i18n.dart';
import '../stage_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) context.go('/home');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StageBlack.background(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: StageBlack.panel,
                    shape: BoxShape.circle,
                    border: Border.all(color: StageBlack.gold, width: 1.5),
                  ),
                  child:
                      Icon(Icons.pets, size: 48, color: StageBlack.gold),
                ),
                const SizedBox(height: 24),
                Text(
                  'Copy Cat',
                  style: TextStyle(
                    fontFamily: StageBlack.displayFont,
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    color: StageBlack.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t('قلّد الصوت… واجمع النقاط!'),
                  style: TextStyle(fontSize: 16, color: StageBlack.muted),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: StageBlack.gold, strokeWidth: 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
