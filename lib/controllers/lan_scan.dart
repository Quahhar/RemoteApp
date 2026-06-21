import 'dart:async';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

/// Probes every host on the device's /24 Wi-Fi subnet for an open TCP [port],
/// emitting the IP of each host that accepts a connection.
///
/// Used by protocols that aren't multicast-discoverable (e.g. Hisense/VIDAA,
/// whose MQTT broker on 36669 is the cleanest "is this that kind of TV?" probe).
/// Hosts are probed concurrently and results stream in as they answer; the
/// stream closes once every host has answered or [timeout] elapses.
Stream<String> scanSubnetForOpenPort(
  int port, {
  Duration timeout = const Duration(seconds: 6),
  Duration perHost = const Duration(milliseconds: 700),
}) {
  final out = StreamController<String>();
  var cancelled = false;
  out.onCancel = () => cancelled = true;

  Future<void> run() async {
    String? localIp;
    try {
      localIp = await NetworkInfo().getWifiIP();
    } catch (_) {
      localIp = null;
    }
    final parts = localIp?.split('.');
    if (parts == null || parts.length != 4) {
      await out.close();
      return;
    }
    final base = '${parts[0]}.${parts[1]}.${parts[2]}';

    Future<void> probe(int host) async {
      final ip = '$base.$host';
      if (ip == localIp) return;
      try {
        final socket = await Socket.connect(ip, port, timeout: perHost);
        socket.destroy();
        if (!cancelled && !out.isClosed) out.add(ip);
      } catch (_) {
        // closed/filtered/unreachable — not this kind of TV.
      }
    }

    final probes = [for (var h = 1; h <= 254; h++) probe(h)];
    await Future.wait(probes).timeout(timeout, onTimeout: () => const []);
    if (!out.isClosed) await out.close();
  }

  out.onListen = run;
  return out.stream;
}
