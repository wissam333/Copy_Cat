import 'package:flutter/material.dart';

/// Notifies GoRouter to rebuild every route when global UI state (language,
/// theme) changes, so existing screens pick up new colors/text without
/// needing a push/pop.
class AppRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final appRefresh = AppRefreshNotifier();
