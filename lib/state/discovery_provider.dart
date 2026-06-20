import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import 'app_providers.dart';

/// Result of a network scan: the devices found so far plus whether a scan is
/// still in progress.
@immutable
class DiscoveryState {
  const DiscoveryState({this.scanning = false, this.devices = const []});

  final bool scanning;
  final List<Device> devices;

  DiscoveryState copyWith({bool? scanning, List<Device>? devices}) =>
      DiscoveryState(
        scanning: scanning ?? this.scanning,
        devices: devices ?? this.devices,
      );
}

/// Fans discovery out across every registered protocol and accumulates the
/// de-duplicated results. The UI calls [DiscoveryNotifier.scan].
final discoveryProvider =
    NotifierProvider<DiscoveryNotifier, DiscoveryState>(DiscoveryNotifier.new);

class DiscoveryNotifier extends Notifier<DiscoveryState> {
  final List<StreamSubscription<Device>> _subs = [];

  @override
  DiscoveryState build() {
    ref.onDispose(_cancelAll);
    return const DiscoveryState();
  }

  /// Start a fresh scan across all protocols. Devices appear incrementally;
  /// [DiscoveryState.scanning] flips false once every protocol's scan window
  /// closes.
  Future<void> scan({Duration timeout = const Duration(seconds: 6)}) async {
    _cancelAll();
    final seen = <String>{};
    state = const DiscoveryState(scanning: true, devices: []);

    final registry = ref.read(controllerRegistryProvider);
    final protocols = registry.protocols;
    if (protocols.isEmpty) {
      state = state.copyWith(scanning: false);
      return;
    }

    var remaining = protocols.length;
    void onProtocolDone() {
      remaining--;
      if (remaining == 0) state = state.copyWith(scanning: false);
    }

    for (final protocol in protocols) {
      final controller = registry.controllerFor(protocol);
      final sub = controller.discover(timeout: timeout).listen(
        (device) {
          if (seen.add(device.id)) {
            state = state.copyWith(devices: [...state.devices, device]);
          }
        },
        onError: (_) {}, // a single protocol failing shouldn't abort the scan
        onDone: onProtocolDone,
        cancelOnError: false,
      );
      _subs.add(sub);
    }
  }

  /// Stop an in-progress scan immediately.
  void stop() {
    _cancelAll();
    state = state.copyWith(scanning: false);
  }

  void _cancelAll() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
  }
}
