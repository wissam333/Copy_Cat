// Mimic Party — Copy Cat (PLAN.md, flutter-patterns skill).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_router.dart';
import 'services/identity_store.dart';
import 'state/language.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final saved = await IdentityStore.load();
  IdentityStore.initialName = saved.$1;
  IdentityStore.initialRoom = saved.$2;
  try {
    // Before runApp: the t() helper reads sync state, not the provider.
    // No saved choice yet → follow the phone's language (ar fallback).
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('copycat.lang');
    currentLanguage = saved == 'en'
        ? AppLanguage.english
        : saved == 'ar'
            ? AppLanguage.arabic
            : WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'en'
                ? AppLanguage.english
                : AppLanguage.arabic;
  } catch (_) {}
  runApp(const ProviderScope(child: MimicPartyApp()));
}

class MimicPartyApp extends ConsumerWidget {
  const MimicPartyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(languageProvider);
    return MaterialApp.router(
      title: 'Copy Cat',
      debugShowCheckedModeBanner: false,
      locale: appLocale(),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      routerConfig: appRouter,
    );
  }
}
