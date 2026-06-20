import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/remote_controller.dart';
import '../models/remote_key.dart';
import '../state/active_device_provider.dart';

/// Sends [key] to the *active controller only* — the single brand-agnostic path
/// the UI uses. Adds haptic feedback and surfaces failures as a SnackBar with
/// the controller's own clear message ("TV not reachable", etc).
Future<void> pressKey(BuildContext context, WidgetRef ref, RemoteKey key) async {
  final controller = ref.read(activeControllerProvider);
  final messenger = ScaffoldMessenger.of(context);
  if (controller == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No device selected — add one in Devices')),
    );
    return;
  }
  HapticFeedback.lightImpact();
  try {
    await controller.sendKey(key);
  } on RemoteException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Failed to send command')),
    );
  }
}
