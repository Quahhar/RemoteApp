import 'dart:io';

import 'package:flutter/services.dart';

/// Android-only Wi-Fi multicast lock (see `MainActivity.kt`).
///
/// Android's Wi-Fi driver filters out multicast packets by default, which
/// silently kills mDNS discovery (Android TV's `_androidtvremote2._tcp`
/// responses arrive as multicast) on real phones — emulators don't filter, so
/// the bug only shows on-device. Holding the lock during a scan lets those
/// datagrams through. SSDP M-SEARCH replies are unicast and never needed it.
///
/// No-ops everywhere but Android, and swallows channel errors so a missing
/// platform side (tests, hot-restart races) can never break a scan.
class MulticastLock {
  static const _channel = MethodChannel('remote/multicast_lock');

  static Future<void> acquire() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('acquire');
    } catch (_) {}
  }

  static Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('release');
    } catch (_) {}
  }
}
