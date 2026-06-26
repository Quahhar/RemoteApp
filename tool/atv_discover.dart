// Standalone Android TV mDNS discovery probe — browses _androidtvremote2._tcp
// on the local network and prints each TV's friendly name, host and port.
// Run on a machine on the same Wi-Fi as a real Android TV:
//   dart run tool/atv_discover.dart [seconds]
// NOTE: an Android TV *emulator* won't be found — the emulator NATs its network
// and multicast/mDNS doesn't traverse host<->guest. Use a physical Android TV.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

const service = '_androidtvremote2._tcp';

MDnsClient buildClient() => MDnsClient(
      rawDatagramSocketFactory: (
        dynamic host,
        int port, {
        bool reuseAddress = true,
        bool reusePort = true,
        int ttl = 1,
      }) =>
          RawDatagramSocket.bind(InternetAddress.anyIPv4, port,
              reuseAddress: true, reusePort: false),
    );

void main(List<String> args) async {
  final seconds = args.isNotEmpty ? int.tryParse(args.first) ?? 6 : 6;
  final timeout = Duration(seconds: seconds);
  final client = buildClient();
  final found = <String>{};

  print('Browsing $service for ${seconds}s ...');
  try {
    await client.start();
  } catch (e) {
    print('mDNS could not start on this machine: $e');
    print('(Known multicast_dns limitation on Windows desktop — errno 10042. '
        'The in-app discovery runs on Android/iOS where mDNS works; verify '
        'with a physical Android TV and the app on a phone. macOS/Linux desktop '
        'can also run this probe.)');
    exit(0);
  }

  try {
    await for (final ptr in client.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer('$service.local'),
      timeout: timeout,
    )) {
      final name = ptr.domainName;
      await for (final srv in client.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(ptr.domainName),
        timeout: timeout,
      )) {
        await for (final ip in client.lookup<IPAddressResourceRecord>(
          ResourceRecordQuery.addressIPv4(srv.target),
          timeout: timeout,
        )) {
          final key = '${ip.address.address}:${srv.port}';
          if (found.add(key)) {
            print('FOUND  name="$name"  host=${ip.address.address}  '
                'port=${srv.port}  target=${srv.target}');
          }
        }
      }
    }
  } catch (e) {
    print('lookup error: $e');
  } finally {
    client.stop();
  }

  print(found.isEmpty
      ? 'No Android TVs found (need a physical TV on this Wi-Fi).'
      : 'Done — ${found.length} found.');
  exit(0);
}
