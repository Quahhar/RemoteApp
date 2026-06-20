import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// The persistent top bar from the mockups: a Settings gear on the left and the
/// centered "Remote Control" title. Shown on every tab by the shell.
class AppHeader extends StatelessWidget {
  const AppHeader({super.key, required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: InkResponse(
              onTap: onSettings,
              radius: 26,
              child: const SizedBox(
                width: 46,
                height: 46,
                child: Icon(Icons.settings_outlined,
                    size: 24, color: AppColors.textPrimary),
              ),
            ),
          ),
          const Text(
            'Remote Control',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
