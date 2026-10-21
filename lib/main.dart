// Mimic Party — Copy Cat (PLAN.md, flutter-patterns skill).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'services/identity_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final saved = await IdentityStore.load();
  IdentityStore.initialName = saved.$1;
  IdentityStore.initialRoom = saved.$2;
  runApp(const ProviderScope(child: MimicPartyApp()));
}

class MimicPartyApp extends StatelessWidget {
  const MimicPartyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Copy Cat',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
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
