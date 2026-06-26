import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote/controllers/dlna_controller.dart';
import 'package:remote/controllers/remote_controller.dart';
import 'package:remote/models/connection_status.dart';
import 'package:remote/models/device.dart';
import 'package:remote/models/protocol_type.dart';
import 'package:remote/models/remote_key.dart';

const _device = Device(
  id: 'test-dlna',
  name: 'Test TV',
  host: '192.168.1.60',
  protocol: ProtocolType.dlna,
);

// A realistic VIDAA-style MediaRenderer descriptor: three services with
// absolute control paths and a URLBase that pins host:port.
const _descriptorXml = '''
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion><major>1</major><minor>0</minor></specVersion>
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>Living Room TV</friendlyName>
    <UDN>uuid:abc-123-def</UDN>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
        <controlURL>/upnp/control/minguscmr</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>/upnp/control/mingusavtr</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <controlURL>/upnp/control/mingusrcr</controlURL>
      </service>
    </serviceList>
  </device>
  <URLBase>http://192.168.1.60:18400</URLBase>
</root>
''';

String _rcResponse(String action, String inner) =>
    '<?xml version="1.0"?><s:Envelope '
    'xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
    '<s:Body><u:${action}Response '
    'xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">'
    '$inner</u:${action}Response></s:Body></s:Envelope>';

String _emptyResponse(String action) =>
    '<?xml version="1.0"?><s:Envelope '
    'xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
    '<s:Body><u:${action}Response xmlns:u="x"></u:${action}Response>'
    '</s:Body></s:Envelope>';

String _soapAction(http.Request req) =>
    (req.headers['soapaction'] ?? '').replaceAll('"', '');

/// MockClient that serves the descriptor for GETs and canned SOAP responses for
/// the read actions, recording every request for assertions.
http.Client _mock(
  List<http.Request> log, {
  int volume = 9,
  int mute = 0,
}) {
  return MockClient((req) async {
    log.add(req);
    if (req.method == 'GET') return http.Response(_descriptorXml, 200);
    final action = _soapAction(req);
    if (action.endsWith('#GetVolume')) {
      return http.Response(
        _rcResponse('GetVolume', '<CurrentVolume>$volume</CurrentVolume>'),
        200,
      );
    }
    if (action.endsWith('#GetMute')) {
      return http.Response(
        _rcResponse('GetMute', '<CurrentMute>$mute</CurrentMute>'),
        200,
      );
    }
    return http.Response(_emptyResponse(action.split('#').last), 200);
  });
}

Future<DlnaController> _connected(List<http.Request> log,
    {int volume = 9, int mute = 0}) async {
  final controller = DlnaController(client: _mock(log, volume: volume, mute: mute));
  await controller.connect(_device);
  log.clear(); // discard the descriptor GET
  return controller;
}

void main() {
  group('metadata', () {
    test('protocol + capabilities', () {
      final c = DlnaController(client: _mock([]));
      expect(c.protocol, ProtocolType.dlna);
      expect(c.capabilities.channelButtons, isFalse);
      expect(c.capabilities.supportsPointer, isFalse);
      c.dispose();
    });
  });

  group('connect()', () {
    test('resolves control URLs from the descriptor -> connected', () async {
      final log = <http.Request>[];
      final controller = DlnaController(client: _mock(log));
      await controller.connect(_device);
      expect(controller.status, ConnectionStatus.connected);
      controller.dispose();
    });

    test('descriptor without renderer services -> NotReachable + error', () async {
      final controller = DlnaController(
        client: MockClient((req) async => http.Response('<root>nope</root>', 200)),
      );
      await expectLater(
        controller.connect(_device),
        throwsA(isA<NotReachableException>()),
      );
      expect(controller.status, ConnectionStatus.error);
      controller.dispose();
    });

    test('socket failure -> NotReachableException', () async {
      final controller = DlnaController(
        client: MockClient((req) async => throw const SocketException('down')),
      );
      await expectLater(
        controller.connect(_device),
        throwsA(isA<NotReachableException>()),
      );
      controller.dispose();
    });

    test('heartbeat flips status to error when the renderer goes offline',
        () async {
      var online = true;
      final controller = DlnaController(
        client: MockClient((req) async {
          if (!online) throw const SocketException('offline');
          if (req.method == 'GET') return http.Response(_descriptorXml, 200);
          return http.Response('', 200);
        }),
        heartbeatInterval: const Duration(milliseconds: 20),
      );
      await controller.connect(_device);
      expect(controller.status, ConnectionStatus.connected);

      online = false; // TV drops off the network
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(controller.status, ConnectionStatus.error);
      controller.dispose();
    });
  });

  group('sendKey()', () {
    test('volumeUp reads then writes current+step to RenderingControl', () async {
      final log = <http.Request>[];
      final controller = await _connected(log, volume: 9);
      await controller.sendKey(RemoteKey.volumeUp);
      controller.dispose();

      expect(log, hasLength(2));
      expect(_soapAction(log[0]), endsWith('#GetVolume'));
      final set = log[1];
      expect(_soapAction(set), endsWith('#SetVolume'));
      expect(set.method, 'POST');
      expect(set.url.toString(),
          'http://192.168.1.60:18400/upnp/control/mingusrcr');
      expect(set.body, contains('<DesiredVolume>11</DesiredVolume>'));
    });

    test('volumeDown clamps at 0', () async {
      final log = <http.Request>[];
      final controller = await _connected(log, volume: 1);
      await controller.sendKey(RemoteKey.volumeDown);
      controller.dispose();
      expect(log[1].body, contains('<DesiredVolume>0</DesiredVolume>'));
    });

    test('mute toggles based on current state (unmuted -> 1)', () async {
      final log = <http.Request>[];
      final controller = await _connected(log, mute: 0);
      await controller.sendKey(RemoteKey.mute);
      controller.dispose();
      expect(_soapAction(log[0]), endsWith('#GetMute'));
      expect(_soapAction(log[1]), endsWith('#SetMute'));
      expect(log[1].body, contains('<DesiredMute>1</DesiredMute>'));
    });

    test('play posts AVTransport Play to the avtr control URL', () async {
      final log = <http.Request>[];
      final controller = await _connected(log);
      await controller.sendKey(RemoteKey.play);
      controller.dispose();
      expect(log, hasLength(1));
      expect(_soapAction(log.single), endsWith('#Play'));
      expect(log.single.url.path, '/upnp/control/mingusavtr');
    });

    test('navigation keys are rejected with a clear message', () async {
      final controller = await _connected(<http.Request>[]);
      for (final key in [
        RemoteKey.up,
        RemoteKey.down,
        RemoteKey.ok,
        RemoteKey.home,
        RemoteKey.power,
        RemoteKey.channelUp,
      ]) {
        await expectLater(
          controller.sendKey(key),
          throwsA(isA<RemoteException>()),
          reason: '${key.name} should not be claimed as supported',
        );
      }
      controller.dispose();
    });

    test('without an active device throws', () async {
      final controller = DlnaController(client: _mock([]));
      await expectLater(
        controller.sendKey(RemoteKey.volumeUp),
        throwsA(isA<RemoteException>()),
      );
      controller.dispose();
    });
  });

  group('castUrl()', () {
    test('sets the AV transport URI (with escaped DIDL) then plays', () async {
      final log = <http.Request>[];
      final controller = await _connected(log);
      await controller.castUrl('http://192.168.1.5:8080/clip.mp4', title: 'Clip');
      controller.dispose();

      expect(log, hasLength(2));
      expect(_soapAction(log[0]), endsWith('#SetAVTransportURI'));
      expect(log[0].body, contains('clip.mp4'));
      // DIDL is nested + escaped inside the metadata argument.
      expect(log[0].body, contains('&lt;DIDL-Lite'));
      expect(log[0].body, contains('object.item.videoItem'));
      expect(_soapAction(log[1]), endsWith('#Play'));
    });
  });

  group('pure helpers', () {
    test('parseControlUrls resolves against URLBase', () {
      final urls = DlnaController.parseControlUrls(
        _descriptorXml,
        Uri.parse('http://192.168.1.60:18400/MediaServer/rendererdevicedesc.xml'),
      );
      expect(urls[DlnaController.renderingControlType].toString(),
          'http://192.168.1.60:18400/upnp/control/mingusrcr');
      expect(urls[DlnaController.avTransportType].toString(),
          'http://192.168.1.60:18400/upnp/control/mingusavtr');
    });

    test('parseControlUrls falls back to the descriptor URL when no URLBase', () {
      const xml = '<root><device><serviceList><service>'
          '<serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>'
          '<controlURL>/ctrl/rc</controlURL>'
          '</service></serviceList></device></root>';
      final urls = DlnaController.parseControlUrls(
        xml,
        Uri.parse('http://10.0.0.5:49152/desc.xml'),
      );
      expect(urls[DlnaController.renderingControlType].toString(),
          'http://10.0.0.5:49152/ctrl/rc');
    });

    test('buildSoapBody wraps the action and escapes args', () {
      final body = DlnaController.buildSoapBody(
        DlnaController.renderingControlType,
        'SetVolume',
        {'DesiredVolume': '11', 'Note': 'a<b&c'},
      );
      expect(body, contains('<u:SetVolume '
          'xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">'));
      expect(body, contains('<DesiredVolume>11</DesiredVolume>'));
      expect(body, contains('a&lt;b&amp;c'));
    });

    test('intTag parses numeric tags, null otherwise', () {
      expect(DlnaController.intTag('<CurrentVolume>9</CurrentVolume>',
          'CurrentVolume'), 9);
      expect(DlnaController.intTag('<x>nan</x>', 'x'), isNull);
      expect(DlnaController.intTag('<a/>', 'CurrentVolume'), isNull);
    });

    test('didlMetadata picks the class from content type', () {
      expect(DlnaController.didlMetadata('u', 't', 'audio/mp3'),
          contains('object.item.audioItem.musicTrack'));
      expect(DlnaController.didlMetadata('u', 't', 'image/jpeg'),
          contains('object.item.imageItem.photo'));
      expect(DlnaController.didlMetadata('u', 't', 'video/mp4'),
          contains('object.item.videoItem'));
    });

    test('faultMessage reads UPnP error bodies', () {
      const fault = '<s:Fault><detail><UPnPError>'
          '<errorCode>401</errorCode>'
          '<errorDescription>Invalid Action</errorDescription>'
          '</UPnPError></detail></s:Fault>';
      expect(DlnaController.faultMessage(fault), contains('401'));
      expect(DlnaController.faultMessage(fault), contains('Invalid Action'));
      expect(DlnaController.faultMessage('<ok/>'), isNull);
    });
  });
}
