import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/capabilities.dart';
import '../models/connection_status.dart';
import '../models/device.dart';
import '../models/protocol_type.dart';
import '../models/remote_key.dart';

/// The single contract the UI talks to. Every protocol implements this and
/// nothing else is brand-specific above this line.
///
/// Subclasses get status-stream plumbing for free: call [emitStatus] to push
/// state, and the base manages the broadcast controller + [dispose]. Pointer
/// methods default to throwing [UnsupportedError]; controllers that set
/// [Capabilities.pointer] override them.
abstract class RemoteController {
  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _status = ConnectionStatus.disconnected;

  /// Which protocol this controller speaks.
  ProtocolType get protocol;

  /// What this controller supports; drives UI affordances.
  Capabilities get capabilities;

  /// Current ambient connection state.
  ConnectionStatus get status => _status;

  /// Broadcast of connection-state changes. Replays nothing; read [status] for
  /// the current value on subscribe.
  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  @protected
  void emitStatus(ConnectionStatus next) {
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }

  /// Discover devices of this protocol on the LAN. Emits each [Device] as it is
  /// found so the UI can populate incrementally; completes when the scan window
  /// closes.
  Stream<Device> discover({Duration timeout = const Duration(seconds: 5)});

  /// Establish a connection (and pair if needed) to [device]. Throws a
  /// [RemoteException] on failure (e.g. [NotReachableException],
  /// [PairingRequiredException], [PairingRejectedException]).
  Future<void> connect(Device device);

  /// Tear down the active connection. Safe to call when already disconnected.
  Future<void> disconnect();

  /// Send a single button press to the connected device.
  Future<void> sendKey(RemoteKey key);

  /// Relative pointer move (touchpad). Override when [Capabilities.pointer].
  Future<void> movePointer(double dx, double dy) =>
      throw UnsupportedError('${protocol.label} does not support pointer input');

  /// Pointer click/tap. Override when [Capabilities.pointer].
  Future<void> click() =>
      throw UnsupportedError('${protocol.label} does not support pointer input');

  /// Release all resources. Subclasses overriding MUST call super.
  @mustCallSuper
  void dispose() {
    _statusController.close();
  }
}

/// Base class for any recoverable remote-control failure. The [message] is
/// safe to surface directly to the user.
class RemoteException implements Exception {
  const RemoteException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The TV could not be reached (offline, wrong IP, or firewalled).
class NotReachableException extends RemoteException {
  const NotReachableException([super.message = 'TV not reachable']);
}

/// The TV requires an on-screen pairing step (e.g. an Android TV code or a
/// Samsung allow prompt) before it will accept commands.
class PairingRequiredException extends RemoteException {
  const PairingRequiredException([
    super.message = 'Pairing required — accept the prompt on your TV',
  ]);
}

/// The user (or TV) declined the pairing request.
class PairingRejectedException extends RemoteException {
  const PairingRejectedException([super.message = 'Pairing rejected']);
}

/// The connection dropped or a command timed out mid-session.
class ConnectionLostException extends RemoteException {
  const ConnectionLostException([super.message = 'Connection lost']);
}
