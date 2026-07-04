// Impersonates the Hisense/VIDAA TV on this PC so the app connects HERE and
// hands over its client certificate during the TLS handshake. Serves the UPnP
// descriptor (so the app accepts us as a real VIDAA TV) on 38400/18400 and a
// mutual-TLS catcher on 36669 that dumps the client cert.
//   dart run tool/tv_impersonator.dart [thisPcIp]
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

const usn = 'uuid:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

/// Responds to SSDP M-SEARCH so the app discovers this PC as a VIDAA TV.
Future<void> serveSsdp(String ip) async {
  try {
    final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 1900,
        reuseAddress: true);
    try {
      sock.joinMulticast(InternetAddress('239.255.255.250'));
    } catch (e) {
      print('  (mcast join failed: $e)');
    }
    print('SSDP responder on :1900');
    final loc = 'http://$ip:18400/MediaServer/rendererdevicedesc.xml';
    sock.listen((ev) {
      if (ev != RawSocketEvent.read) return;
      final dg = sock.receive();
      if (dg == null) return;
      final msg = String.fromCharCodes(dg.data);
      final first = msg.split('\r\n').first;
      print('SSDP <= ${dg.address.address}:${dg.port}  $first');
      if (msg.toUpperCase().contains('M-SEARCH')) {
        final resp = 'HTTP/1.1 200 OK\r\n'
            'CACHE-CONTROL: max-age=1800\r\n'
            'LOCATION: $loc\r\n'
            'SERVER: Linux/4.4 UPnP/1.0 SmartTV/1.0\r\n'
            'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
            'USN: $usn::urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
            'EXT:\r\n\r\n';
        sock.send(utf8.encode(resp), dg.address, dg.port);
        print('SSDP => responded with LOCATION $loc');
      }
    });
  } catch (e) {
    print('ssdp failed: $e');
  }
}

/// Logs (and echoes) Hisense UDP discovery probes so we can see the format.
Future<void> listenUdp(int port, String ip) async {
  try {
    final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port,
        reuseAddress: true);
    sock.broadcastEnabled = true;
    print('UDP discovery listener on :$port');
    sock.listen((ev) {
      if (ev != RawSocketEvent.read) return;
      final dg = sock.receive();
      if (dg == null) return;
      final txt = String.fromCharCodes(
          dg.data.map((b) => (b >= 32 && b < 127) ? b : 46));
      print('UDP :$port <= ${dg.address.address}:${dg.port} '
          '(${dg.data.length}b): $txt');
      // Echo back a simple reply advertising this PC (best-effort).
      sock.send(utf8.encode('{"ip":"$ip","brand":"ksj"}'), dg.address, dg.port);
    });
  } catch (e) {
    print('udp :$port failed: $e');
  }
}

const srvCert = 'C:/Users/x/AppData/Local/Temp/srv_cert.pem';
const srvKey = 'C:/Users/x/AppData/Local/Temp/srv_key.pem';
const remoteCa = 'C:/Users/x/AppData/Local/Temp/remoteca.pem';
const outPem = 'C:/Users/x/AppData/Local/Temp/captured_client_cert.pem';
// Our RemoteCA-signed client cert to authenticate to the REAL TV when proxying.
const rcmCert =
    'C:/Users/x/Documents/program/Flutter/Remote/remote/assets/certs/vidaa_client_cert.pem';
const rcmKey =
    'C:/Users/x/Documents/program/Flutter/Remote/remote/assets/certs/vidaa_client_key.pem';

String _dump(List<int> d) {
  final hex = d.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  final txt = String.fromCharCodes(d.map((b) => (b >= 32 && b < 127) ? b : 46));
  return 'hex: $hex\n        txt: $txt';
}

String descriptor(String ip) => '''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
    <specVersion><major>1</major><minor>0</minor></specVersion>
    <device>
        <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
        <dlna:X_DLNADOC xmlns:dlna="urn:schemas-dlna-org:device-1-0">DMR-1.50</dlna:X_DLNADOC>
        <friendlyName>PC TEST TV</friendlyName>
        <manufacturer>SmartTV</manufacturer>
        <manufacturerURL>http://www.smarttv.com</manufacturerURL>
        <modelDescription>#CAP#
mac=aabbccddeeff
macWifi=aabbccddeeff
macEthernet=aabbccddeeff
ip=$ip
region=5
transport_protocol=3290
platform=1
voice=2
brand=ksj
vidaa_support=1
</modelDescription>
        <modelName>Renderer</modelName>
        <modelNumber>1.0</modelNumber>
        <UDN>uuid:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee</UDN>
    </device>
    <URLBase>http://$ip:18400</URLBase>
</root>''';

Future<void> serveHttp(int port, String ip) async {
  try {
    final s = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('UPnP descriptor server on :$port');
    await for (final req in s) {
      print('  HTTP ${req.method} ${req.uri.path}  (from ${req.connectionInfo?.remoteAddress.address})');
      req.response.headers.contentType = ContentType('text', 'xml');
      req.response.write(descriptor(ip));
      await req.response.close();
    }
  } catch (e) {
    print('http :$port failed: $e');
  }
}

Future<void> serveTls(int port, String realTvIp) async {
  final ctx = SecurityContext()
    ..useCertificateChain(srvCert)
    ..usePrivateKey(srvKey)
    ..setTrustedCertificates(remoteCa);
  final server = await SecureServerSocket.bind(
    InternetAddress.anyIPv4, port, ctx,
    requestClientCertificate: true,
    requireClientCertificate: false,
  );
  final clientCtx = SecurityContext()
    ..useCertificateChain(rcmCert)
    ..usePrivateKey(rcmKey);
  print('TLS PROXY on :$port  ->  real TV $realTvIp:$port');
  server.listen((app) async {
    final from = app.remoteAddress.address;
    final cert = app.peerCertificate;
    if (cert != null) {
      try {
        File(outPem).writeAsStringSync(cert.pem);
      } catch (_) {}
      print('[$from] app cert: ${cert.subject}');
    }
    SecureSocket tv;
    try {
      tv = await SecureSocket.connect(realTvIp, port,
          context: clientCtx,
          onBadCertificate: (_) => true,
          timeout: const Duration(seconds: 8));
      print('[$from] proxied to REAL TV $realTvIp:$port');
    } catch (e) {
      print('[$from] proxy: real TV connect FAILED: $e');
      try {
        app.destroy();
      } catch (_) {}
      return;
    }
    app.listen((data) {
      print('[app->TV] ${data.length}b ${_dump(data)}');
      try {
        tv.add(data);
      } catch (_) {}
    }, onError: (_) {}, onDone: () {
      try {
        tv.destroy();
      } catch (_) {}
    });
    tv.listen((data) {
      print('[TV->app] ${data.length}b ${_dump(data)}');
      try {
        app.add(data);
      } catch (_) {}
    }, onError: (_) {}, onDone: () {
      try {
        app.destroy();
      } catch (_) {}
    });
  }, onError: (e) {
    print('handshake error (ignored): $e');
  }, cancelOnError: false);
}

void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart run tool/tv_impersonator.dart '
        '<impersonate-ip> <real-tv-ip>');
    exit(64); // EX_USAGE
  }
  final ip = args[0];
  final realTvIp = args[1];
  print('Impersonating VIDAA TV as $ip — point the app at this IP.');
  serveSsdp(ip);
  listenUdp(36671, ip);
  listenUdp(50000, ip);
  await Future.wait([
    serveHttp(38400, ip),
    serveHttp(18400, ip),
    serveTls(36669, realTvIp),
  ]);
}
