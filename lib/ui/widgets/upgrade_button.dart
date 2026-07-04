import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../purchases/purchase_controller.dart';
import '../../state/preferences_provider.dart';
import '../../theme/app_colors.dart';
import '../screens/upgrade_screen.dart';

/// Small gold "Upgrade" pill that opens the [UpgradeScreen]. Renders nothing
/// once Pro is owned. Drop it next to a page's settings/header actions.
class UpgradeButton extends ConsumerWidget {
  const UpgradeButton({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UpgradeScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isProProvider)) return const SizedBox.shrink();
    // Headers instantiate this button const, so watch the palette flip here to
    // repaint after a dark-mode toggle.
    ref.watch(effectiveDarkModeProvider);
    return Material(
      color: AppColors.goldSoft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => open(context),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium, size: 16, color: AppColors.gold),
              const SizedBox(width: 5),
              Text(
                'Upgrade',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.goldText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
