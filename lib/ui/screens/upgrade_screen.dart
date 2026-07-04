import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../purchases/purchase_controller.dart';
import '../../theme/app_colors.dart';

/// The single paid tier ("Pro") — a gold paywall reached from the Upgrade
/// buttons and from a free user touching the trackpad. One-time purchase that
/// removes ads and unlocks the trackpad (and the future More button).
class UpgradeScreen extends ConsumerWidget {
  const UpgradeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchase = ref.watch(purchaseProvider);
    final notifier = ref.read(purchaseProvider.notifier);
    final owned = purchase.pro;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Omnix Pro')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
          children: [
            // Crest.
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: AppColors.goldSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.workspace_premium,
                    size: 40, color: AppColors.gold),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              owned ? 'You’re Pro' : 'Unlock Omnix Pro',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              owned
                  ? 'Thanks for supporting the app.'
                  : 'A one-time purchase. Yours forever on this account.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
            const SizedBox(height: 22),

            // Benefits (non-const: they read AppColors in build).
            _Benefit(
              icon: Icons.block,
              title: 'No ads',
              subtitle: 'Remove every ad, for good.',
            ),
            _Benefit(
              icon: Icons.mouse,
              title: 'Trackpad / mouse control',
              subtitle: 'Use the touchpad to move the pointer on your TV.',
            ),
            _Benefit(
              icon: Icons.keyboard,
              title: 'Keyboard',
              subtitle: 'Type on your TV straight from your phone.',
            ),
            _Benefit(
              icon: Icons.more_horiz,
              title: 'More features',
              subtitle: 'Unlocks upcoming extras as they ship.',
            ),
            const SizedBox(height: 22),

            if (purchase.error != null) ...[
              Text(
                purchase.error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.powerRed, fontSize: 13),
              ),
              const SizedBox(height: 12),
            ],

            if (owned)
              _OwnedPill()
            else
              _BuyButton(
                price: purchase.proPrice,
                pending: purchase.pending,
                available: purchase.available && purchase.proProduct != null,
                onTap: notifier.buyPro,
              ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: purchase.pending ? null : notifier.restore,
                child: Text(
                  'Restore purchases',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Payment is charged to your Google Play or App Store account.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.goldSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 21, color: AppColors.gold),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BuyButton extends StatelessWidget {
  const _BuyButton({
    required this.price,
    required this.pending,
    required this.available,
    required this.onTap,
  });
  final String? price;
  final bool pending;
  final bool available;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = !available
        ? 'Upgrade unavailable'
        : price == null
            ? 'Upgrade'
            : 'Upgrade · $price';
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: available ? AppColors.gold : AppColors.hintFaint,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: (pending || !available) ? null : onTap,
          borderRadius: BorderRadius.circular(15),
          child: Center(
            child: pending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _OwnedPill extends StatelessWidget {
  const _OwnedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.goldSoft,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: AppColors.gold, size: 20),
          const SizedBox(width: 8),
          Text(
            'Pro is active',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.goldText,
            ),
          ),
        ],
      ),
    );
  }
}
