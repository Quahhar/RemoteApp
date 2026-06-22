// TLS server that impersonates the TV's MQTT port, requests a client cert, and
// dumps whatever client certificate the peer presents. Used to capture the
// VIDAA app's hidden RemoteCA-signed client cert (the app hands it over during
// the handshake; as the server we see it in plaintext).
//   dart run tool/cert_catcher.dart [port]
// ignore_for_file: avoid_print
import 'dart:io';

const srvCert = 'C:/Users/x/AppData/Local/Temp/srv_cert.pem';
const srvKey = 'C:/Users/x/AppData/Local/Temp/srv_key.pem';
const remoteCa = 'C:/Users/x/AppData/Local/Temp/remoteca.pem';
const outPem = 'C:/Users/x/AppData/Local/Temp/captured_client_cert.pem';

void main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args[0]) : 36669;
  final ctx = SecurityContext()
    ..useCertificateChain(srvCert)
    ..usePrivateKey(srvKey)
    // Trust RemoteCA so the app's RemoteCA-signed client cert verifies and the
    // handshake completes, exposing peerCertificate.
    ..setTrustedCertificates(remoteCa);

  final server = await SecureServerSocket.bind(
    InternetAddress.anyIPv4,
    port,
    ctx,
    requestClientCertificate: true,
    requireClientCertificate: false,
  );
  print('cert-catcher listening on 0.0.0.0:$port — point the app here.');

  await for (final socket in server) {
    final cert = socket.peerCertificate;
    final from = socket.remoteAddress.address;
    if (cert == null) {
      print('[$from] connected but presented NO client certificate');
    } else {
      print('=== [$from] CLIENT CERTIFICATE CAPTURED ===');
      print('subject: ${cert.subject}');
      print('issuer : ${cert.issuer}');
      try {
        File(outPem).writeAsStringSync(cert.pem);
        print('saved PEM -> $outPem');
      } catch (e) {
        print('save failed: $e');
      }
      print(cert.pem);
    }
    socket.listen((_) {}, onError: (_) {}, onDone: () {});
    try {
      await socket.close();
    } catch (_) {}
  }
}
