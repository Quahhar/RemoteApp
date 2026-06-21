import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/active_device_provider.dart';
import '../state/navigation_provider.dart';
import '../theme/app_colors.dart';
import 'screens/devices_screen.dart';
import 'screens/remote_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/touchpad_screen.dart';
import 'widgets/app_header.dart';

/// Top-level shell. Shared "Remote Control" header + a frosted bottom nav
/// (Remote / Touchpad / Devices) over the app-wide gradient, matching the
/// mockups. The keyboard lives inline on the Touchpad screen.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(activeDeviceProvider) != null) {
        unawaited(
          ref.read(activeDeviceProvider.notifier).connect().catchError((_) {}),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(selectedTabProvider).index;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppHeader(
              onSettings: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: index,
                children: const [
                  RemoteScreen(),
                  TouchpadScreen(),
                  DevicesScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _FrostedNavBar(
        currentIndex: index,
        onSelect: (i) =>
            ref.read(selectedTabProvider.notifier).select(HomeTab.values[i]),
        items: const [
          _NavItem(Icons.settings_remote, 'Remote'),
          _NavItem(Icons.touch_app, 'Touchpad'),
          _NavItem(Icons.devices, 'Devices'),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

class _FrostedNavBar extends StatelessWidget {
  const _FrostedNavBar({
    required this.items,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<_NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.navBar,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F463778),
            blurRadius: 28,
            offset: Offset(0, -8),
          ),
        ],
      ),
      padding:
          EdgeInsets.only(top: 14, bottom: 12 + bottomInset, left: 10, right: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            _NavButton(
              item: items[i],
              selected: i == currentIndex,
              onTap: () => onSelect(i),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: 28, color: color),
            const SizedBox(height: 5),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
