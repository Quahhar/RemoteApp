import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/active_device_provider.dart';
import '../state/navigation_provider.dart';
import '../theme/app_colors.dart';
import 'screens/devices_screen.dart';
import 'screens/remote_screen.dart';
import 'screens/touchpad_screen.dart';

/// Top-level shell. Each tab owns its own top area (the mockup has no shared
/// header); a flat, translucent bottom nav switches between Remote / Trackpad /
/// Devices over the `#f4f4f6` background.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final device = ref.read(activeDeviceProvider);
      if (device == null) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        await ref.read(activeDeviceProvider.notifier).connect();
      } catch (_) {
        // Don't fail silently: tell the user why the saved TV isn't connected.
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Couldn’t reconnect to ${device.name} — it may be off or on '
              'another network.',
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(selectedTabProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        // Render only the active page. (An IndexedStack keeps all three mounted;
        // if any inactive page ever stays hit-testable, its buttons fire
        // "through" the page on top — so we mount just the current tab.)
        child: switch (tab) {
          HomeTab.remote => const RemoteScreen(),
          HomeTab.touchpad => const TouchpadScreen(),
          HomeTab.devices => const DevicesScreen(),
        },
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: tab.index,
        onSelect: (i) =>
            ref.read(selectedTabProvider.notifier).select(HomeTab.values[i]),
        items: const [
          _NavItem(Icons.settings_remote, 'Remote'),
          _NavItem(Icons.touch_app, 'Trackpad'),
          _NavItem(Icons.tv, 'Devices'),
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

class _BottomNav extends StatelessWidget {
  const _BottomNav({
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
        border: Border(top: BorderSide(color: AppColors.navBorder)),
      ),
      padding: EdgeInsets.only(top: 10, bottom: 8 + bottomInset),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: _NavButton(
                item: items[i],
                selected: i == currentIndex,
                onTap: () => onSelect(i),
              ),
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
    final color = selected ? AppColors.accent : AppColors.navInactive;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: 26, color: color),
            const SizedBox(height: 5),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
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
