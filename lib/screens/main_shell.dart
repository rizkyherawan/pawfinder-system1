import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/common.dart';
import 'geofence/geofence_screen.dart';
import 'history/history_screen.dart';
import 'home/home_screen.dart';
import 'notifications/notifications_screen.dart';
import 'profile/profile_screen.dart';

/// Kerangka utama dengan Bottom Tab Bar 5 tab dan pembaruan live.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  final Set<int> _visited = {0};
  AppState? _app;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _app = context.read<AppState>();
      _app!.startLive();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final app = _app;
    if (app == null) return;
    if (state == AppLifecycleState.resumed) {
      app.startLive();
      app.refresh(silent: true);
    } else if (state == AppLifecycleState.paused) {
      app.stopLive();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _app?.stopLive();
    super.dispose();
  }

  Widget _tab(int i) {
    if (!_visited.contains(i)) return const SizedBox.shrink();
    switch (i) {
      case 0:
        return const HomeScreen();
      case 1:
        return const HistoryScreen();
      case 2:
        return const GeofenceScreen();
      case 3:
        return const NotificationsScreen();
      default:
        return const ProfileScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    _visited.add(s.tabIndex);
    return PopScope(
      canPop: s.tabIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) context.read<AppState>().setTab(0);
      },
      child: Scaffold(
        body: IndexedStack(index: s.tabIndex, children: List.generate(5, _tab)),
        bottomNavigationBar: PFTabBar(index: s.tabIndex, badge: s.unreadCount > 0, onTap: s.setTab),
      ),
    );
  }
}
