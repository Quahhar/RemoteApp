import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/remote_controller.dart';
import '../models/remote_key.dart';
import '../state/active_device_provider.dart';
import '../state/discovery_provider.dart';
import '../state/navigation_provider.dart';

/// Sends [key] to the *active controller only* — the single brand-agnostic path
/// the UI uses. Adds haptic feedback and surfaces failures as a SnackBar with
/// the controller's own clear message ("TV not reachable", etc). When nothing
/// is connected, redirects to Devices and starts a scan via [promptNoDevice].
Future<void> pressKey(BuildContext context, WidgetRef ref, RemoteKey key) async {
  final controller = ref.read(activeControllerProvider);
  if (controller == null) {
    promptNoDevice(context, ref);
    return;
  }
  HapticFeedback.lightImpact();
  final messenger = ScaffoldMessenger.of(context);
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

/// No device is connected: tell the user, switch to the Devices tab, and kick
/// off a scan so a TV can be picked immediately.
void promptNoDevice(BuildContext context, WidgetRef ref) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('No device connected — scanning for TVs…')),
  );
  ref.read(selectedTabProvider.notifier).select(HomeTab.devices);
  ref.read(discoveryProvider.notifier).scan();
}
