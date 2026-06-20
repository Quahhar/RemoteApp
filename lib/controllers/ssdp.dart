import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One SSDP search response.
class SsdpResponse {
  SsdpResponse({required this.address, required this.raw});

  /// Source IP of the datagram.
  final String address;

  /// The full raw response text (headers).
  final String raw;

  /// Value of [name] header (case-insensitive), or null.
  String? header(String name) {
    final wanted = name.toUpperCase();
    for (final line in const LineSplitter().convert(raw)) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      if (line.substring(0, idx).trim().toUpperCase() == wanted) {
        return line.substring(idx + 1).trim();
      }
    }
    return null;
  }

  /// Host from the LOCATION header if parseable, else the datagram source IP.
  String get host {
    final location = header('LOCATION');
    final uri = location == null ? null : Uri.tryParse(location);
    return (uri != null && uri.host.isNotEmpty) ? uri.host : address;
  }
}

/// Generic SSDP M-SEARCH. Sends the search a few times over the discovery
/// window and yields every response. Callers filter/dedup as needed. Shared by
/// the WebOS and Tizen controllers (Roku keeps its own tuned implementation).
Stream<SsdpResponse> ssdpSearch({
  required String searchTarget,
  Duration timeout = const Duration(seconds: 5),
}) {
  const address = '239.255.255.250';
  const port = 1900;

  late final StreamController<SsdpResponse> out;
  RawDatagramSocket? socket;
  Timer? resend;
  Timer? stop;
  var cleanedUp = false;

  void cleanup() {
    if (cleanedUp) return;
    cleanedUp = true;
    resend?.cancel();
    stop?.cancel();
    socket?.close();
  }

  Future<void> start() async {
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } on SocketException catch (e) {
      out.addError(SocketException('SSDP bind failed: ${e.message}'));
      await out.close();
      return;
    }
    socket!.broadcastEnabled = true;
    final target = InternetAddress(address);
    final payload = utf8.encode(
      'M-SEARCH * HTTP/1.1\r\n'
      'HOST: $address:$port\r\n'
      'MAN: "ssdp:discover"\r\n'
      'ST: $searchTarget\r\n'
      'MX: 2\r\n\r\n',
    );

    socket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket!.receive();
      if (datagram == null) return;
      out.add(SsdpResponse(
        address: datagram.address.address,
        raw: utf8.decode(datagram.data, allowMalformed: true),
      ));
    });

    void send() {
      try {
        socket!.send(payload, target, port);
      } catch (_) {
        // Transient; resend timer retries within the window.
      }
    }

    send();
    resend = Timer.periodic(const Duration(seconds: 1), (_) => send());
    stop = Timer(timeout, () {
      cleanup();
      out.close();
    });
  }

  out = StreamController<SsdpResponse>(onListen: start, onCancel: cleanup);
  return out.stream;
}
