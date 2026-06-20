/// The protocol-agnostic set of buttons a remote can send.
///
/// Widgets emit these; each [RemoteController] translates them to its own wire
/// format. Every value MUST be mapped by every controller (see the per-protocol
/// key-mapping unit tests), even if the mapping is "unsupported".
enum RemoteKey {
  power,

  // D-pad.
  up,
  down,
  left,
  right,
  ok, // a.k.a. select / enter

  // Navigation.
  back,
  home,
  menu,

  // Volume.
  volumeUp,
  volumeDown,
  mute,

  // Channel.
  channelUp,
  channelDown,

  // Transport.
  play,
  pause;

  /// Whether this key is one of the four directional pad keys.
  bool get isDpad =>
      this == RemoteKey.up ||
      this == RemoteKey.down ||
      this == RemoteKey.left ||
      this == RemoteKey.right;
}
