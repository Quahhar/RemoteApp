import 'dart:async';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

import '../models/device.dart';
import '../models/protocol_type.dart';

/// Known TCP ports that identify a *supported* TV platform, mapped to the
/// protocol that owns each one. Probing these across the LAN lets the app
/// auto-find any TV it can actually control, even when SSDP/multicast is blocked
/// (common on home Wi-Fi with AP isolation). We deliberately only list ports for
/// protocols that have a working controller — finding a TV we can't drive would
/// be a dead end.
/// Where a platform exposes two ports (ws/wss, remote/pairing) only one is
/// probed — any TV with the sibling port open has this one open too, and every
/// extra port multiplies the scan's concurrent sockets (which exhausted the
/// process fd limit on phones and made the whole scan silently find nothing).
const Map<int, ProtocolType> kTvDiscoveryPorts = {
  8060: ProtocolType.roku, // Roku ECP
  3000: ProtocolType.webos, // LG webOS SSAP (ws; wss 3001 implied)
  8001: ProtocolType.tizen, // Samsung Tizen (ws; open on all model years)
  8002: ProtocolType.tizen, // Samsung Tizen (wss — the connect port)
  6466: ProtocolType.androidtv, // Android TV remote v2 (pairing 6467 implied)
  36669: ProtocolType.vidaa, // Hisense / VIDAA MQTT
};

/// Active discovery for every supported TV by port: one pass over the /24 Wi-Fi
/// subnet probing all of [kTvDiscoveryPorts], emitting a [Device] for each
/// matched host. A short startup delay lets instant SSDP results (which carry
/// friendlier names) register first and win de-duplication.
Stream<Device> discoverTvsByPortScan({
  Duration timeout = const Duration(seconds: 8),
}) {
  return scanSubnetForAnyPort(
    kTvDiscoveryPorts.keys.toSet(),
    timeout: timeout,
  ).map((hit) {
    final protocol = kTvDiscoveryPorts[hit.port]!;
    return Device(
      id: '${protocol.name}-${hit.host}',
      name: '${protocol.label} (${hit.host})',
      host: hit.host,
      protocol: protocol,
    );
  });
}

/// Probes every host on the device's /24 Wi-Fi subnet for any of [ports],
/// emitting the first open `(host, port)` found per host.
///
/// Hosts are scanned in [batch]-sized groups to bound concurrent sockets; within
/// a host all ports are probed at once and the first to answer wins. The stream
/// closes once every host has been probed or [timeout] elapses.
Stream<({String host, int port})> scanSubnetForAnyPort(
  Set<int> ports, {
  Duration timeout = const Duration(seconds: 8),
  // Plenty for a same-subnet TCP connect; keeps 11 batches inside [timeout].
  Duration perHost = const Duration(milliseconds: 500),
  Duration startDelay = const Duration(milliseconds: 1200),
  // batch × ports = concurrent sockets. Keep well under the process fd limit
  // (256 on iOS): 64 hosts × 8 ports used to open ~512 sockets at once, which
  // made every probe fail with "too many open files" and the scan find nothing.
  int batch = 24,
}) {
  final out = StreamController<({String host, int port})>();
  var cancelled = false;
  out.onCancel = () => cancelled = true;

  Future<void> probeHost(String host) async {
    final done = Completer<int?>();
    var pending = ports.length;
    final sockets = <Socket>[];
    for (final port in ports) {
      unawaited(
        Socket.connect(host, port, timeout: perHost).then(
          (socket) {
            sockets.add(socket);
            if (!done.isCompleted) done.complete(port);
          },
          onError: (Object _) {
            pending -= 1;
            if (pending == 0 && !done.isCompleted) done.complete(null);
          },
        ),
      );
    }
    final port = await done.future;
    // Close all sockets — the winning one was used for detection only,
    // the losing ones were never completed and leak file descriptors.
    for (final s in sockets) {
      try {
        s.destroy();
      } catch (_) {}
    }
    if (port != null && !cancelled && !out.isClosed) {
      out.add((host: host, port: port));
    }
  }

  Future<void> run() async {
    // Resolve our subnet BEFORE any timer so this is a clean no-op off Wi-Fi
    // (and in tests where the plugin is absent).
    String? localIp;
    try {
      localIp = await NetworkInfo().getWifiIP();
    } catch (_) {
      localIp = null;
    }
    final parts = localIp?.split('.');
    if (parts == null || parts.length != 4 || cancelled) {
      await out.close();
      return;
    }
    final base = '${parts[0]}.${parts[1]}.${parts[2]}';

    await Future<void>.delayed(startDelay);
    if (cancelled) {
      await out.close();
      return;
    }

    final hosts = [
      for (var h = 1; h <= 254; h++)
        if ('$base.$h' != localIp) '$base.$h',
    ];
    final deadline = DateTime.now().add(timeout);
    for (var i = 0; i < hosts.length && !cancelled; i += batch) {
      if (DateTime.now().isAfter(deadline)) break;
      final end = (i + batch) > hosts.length ? hosts.length : i + batch;
      await Future.wait(hosts.sublist(i, end).map(probeHost));
    }
    if (!out.isClosed) await out.close();
  }

  out.onListen = run;
  return out.stream;
}
