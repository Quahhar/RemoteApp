import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/active_device_provider.dart';
import 'screens/devices_screen.dart';
import 'screens/remote_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/touchpad_screen.dart';
import 'widgets/connection_indicator.dart';

/// Top-level shell: a 3-tab NavigationBar (Remote / Devices / Touchpad) with a
/// persistent connection indicator and a Settings gear in the AppBar.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _titles = ['Remote', 'Devices', 'Touchpad'];

  @override
  void initState() {
    super.initState();
    // Reconnect to the previously-active device once the tree is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(activeDeviceProvider) != null) {
        unawaited(
          ref.read(activeDeviceProvider.notifier).connect().catchError((_) {
            // Status stream reflects the failure; nothing to surface on boot.
          }),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Center(child: ConnectionIndicator()),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          RemoteScreen(),
          DevicesScreen(),
          TouchpadScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.gamepad_outlined),
            selectedIcon: Icon(Icons.gamepad),
            label: 'Remote',
          ),
          NavigationDestination(
            icon: Icon(Icons.devices_outlined),
            selectedIcon: Icon(Icons.devices),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Icon(Icons.touch_app_outlined),
            selectedIcon: Icon(Icons.touch_app),
            label: 'Touchpad',
          ),
        ],
      ),
    );
  }
}
