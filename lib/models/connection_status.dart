/// Lifecycle of a [RemoteController]'s link to its active device.
///
/// This is the *ambient* state surfaced on the controller's status stream.
/// Actionable failures (with messages like "TV not reachable") are thrown as
/// [RemoteException]s from `connect()` / `sendKey()` so the UI can react to
/// both: a steady status indicator plus a transient error message.
enum ConnectionStatus {
  /// No active connection.
  disconnected,

  /// A connect attempt (or pairing handshake) is in progress.
  connecting,

  /// Connected and ready to send keys.
  connected,

  /// The last attempt failed; see the thrown [RemoteException] for details.
  error;

  bool get isConnected => this == ConnectionStatus.connected;
  bool get isBusy => this == ConnectionStatus.connecting;
}
