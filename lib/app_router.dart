// lib/app_router.dart — GoRouter (skill: named routes).
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'screens/download_screen.dart';
import 'screens/gameplay_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/shop_screen.dart';
import 'screens/party_setup_screen.dart';
import 'screens/results_screen.dart';
import 'screens/splash_screen.dart';

/// System back goes [route] instead of closing the app. (In-app back
/// buttons navigate directly and are unaffected.)
class _BackTo extends StatelessWidget {
  final String route;
  final Widget child;
  const _BackTo(this.route, {required this.child});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(route);
      },
      child: child,
    );
  }
}

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/library',
      builder: (context, state) =>
          const _BackTo('/home', child: LibraryScreen()),
    ),
    GoRoute(
      path: '/download',
      builder: (context, state) =>
          const _BackTo('/library', child: DownloadScreen()),
    ),
    GoRoute(
      path: '/lobby',
      builder: (context, state) {
        final host = state.uri.queryParameters['host'] != '0';
        return _BackTo('/home',
            child: LobbyScreen(startAsHost: host));
      },
    ),
    GoRoute(
      path: '/party',
      builder: (context, state) =>
          const _BackTo('/home', child: PartySetupScreen()),
    ),
    GoRoute(
      path: '/game',
      builder: (context, state) => GameplayScreen(
        solo: state.uri.queryParameters['solo'] == '1',
      ),
    ),
    GoRoute(
      path: '/results',
      builder: (context, state) =>
          const _BackTo('/home', child: ResultsScreen()),
    ),
    GoRoute(
      path: '/shop',
      builder: (context, state) =>
          const _BackTo('/home', child: ShopScreen()),
    ),
  ],
);
