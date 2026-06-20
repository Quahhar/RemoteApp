import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Simple title header for the non-Remote tabs (which no longer sit under a
/// global AppBar). Placeholder styling until each screen's own mockup arrives.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 14, 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}
