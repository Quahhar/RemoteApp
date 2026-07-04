import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/lan_scan.dart';
import '../controllers/multicast_lock.dart';
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
  Timer? _watchdog;

  @override
  DiscoveryState build() {
    ref.onDispose(_cancelAll);
    return const DiscoveryState();
  }

  /// Start a fresh scan. Runs every protocol's own discovery (SSDP/multicast,
  /// which carries friendlier names) *and* a single cross-protocol LAN port scan
  /// that finds any supported TV by its known ports — more reliable on networks
  /// that block multicast. Devices appear incrementally and are de-duplicated by
  /// (protocol, host) so a TV found by both paths shows up once.
  /// [DiscoveryState.scanning] flips false once every source closes.
  Future<void> scan({Duration timeout = const Duration(seconds: 6)}) async {
    _cancelAll();
    final seen = <String>{};
    state = const DiscoveryState(scanning: true, devices: []);

    // Android drops multicast (mDNS) unless this lock is held — without it,
    // Android TV discovery finds nothing on real phones. Released whenever the
    // scan ends ([_cancelAll]/finish). Fire-and-forget: no-op off Android.
    unawaited(MulticastLock.acquire());

    final registry = ref.read(controllerRegistryProvider);
    final sources = <Stream<Device>>[
      for (final protocol in registry.protocols)
        registry.controllerFor(protocol).discover(timeout: timeout),
      discoverTvsByPortScan(),
    ];

    var remaining = sources.length;
    void finish() {
      _watchdog?.cancel();
      _watchdog = null;
      unawaited(MulticastLock.release());
      if (state.scanning) state = state.copyWith(scanning: false);
    }

    void onSourceDone() {
      remaining--;
      if (remaining == 0) finish();
    }

    for (final source in sources) {
      final sub = source.listen(
        (device) {
          if (seen.add('${device.protocol.name}@${device.host}')) {
            state = state.copyWith(devices: [...state.devices, device]);
          }
        },
        onError: (_) {}, // a single source failing shouldn't abort the scan
        onDone: onSourceDone,
        cancelOnError: false,
      );
      _subs.add(sub);
    }

    // Safety net: if a source hangs or errors without ever closing, the spinner
    // would spin forever — force the scan to end past the slowest source (the
    // LAN port scan runs ~8s: its own start delay plus the batched probes).
    _watchdog = Timer(timeout + const Duration(seconds: 4), () {
      _cancelAll();
      finish();
    });
  }

  /// Stop an in-progress scan immediately.
  void stop() {
    _cancelAll();
    state = state.copyWith(scanning: false);
  }

  void _cancelAll() {
    _watchdog?.cancel();
    _watchdog = null;
    unawaited(MulticastLock.release());
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
  }
}
