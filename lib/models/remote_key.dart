/// The protocol-agnostic set of buttons a remote can send.
///
/// Widgets emit these; each [RemoteController] translates them to its own wire
/// format. The keys split into two tiers:
///
///  - [core] — the 16 buttons every TV protocol genuinely supports. Every
///    controller MUST map all of these (asserted by the per-protocol mapping
///    unit tests). These are the controls on the main Remote screen.
///  - everything else ("extended") — the richer command set surfaced in the
///    More sheet (number pad, transport, colour buttons, inputs, …). Support
///    varies a lot between brands, so a controller maps only the extended keys
///    it can actually send; [RemoteController.sendKey] reports the rest as
///    "not available on this TV" (a clean, de-duped SnackBar).
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
  pause,

  // ---- Extended (More sheet) ------------------------------------------------

  // Number pad.
  digit0,
  digit1,
  digit2,
  digit3,
  digit4,
  digit5,
  digit6,
  digit7,
  digit8,
  digit9,
  dash, // the "-" sub-channel separator

  // Extra transport / quick keys.
  previous,
  next,
  rewind,
  fastForward,
  stop,
  record,

  // Media surfaces.
  liveTv,
  guide,
  source, // input/source selector
  subtitles, // closed captions

  // Picture & sound.
  pictureMode,
  sleep,
  aspect,
  audioTrack,

  // Colour buttons.
  colorRed,
  colorGreen,
  colorYellow,
  colorBlue,

  // Direct input selection.
  inputHdmi1,
  inputHdmi2,
  inputHdmi3,
  inputAv,
  inputTv,

  // Smart / system.
  settings,
  search,
  voiceAssist,
  notifications;

  /// The 16 universally-supported buttons. Every controller maps all of these.
  static const List<RemoteKey> core = [
    power,
    up,
    down,
    left,
    right,
    ok,
    back,
    home,
    menu,
    volumeUp,
    volumeDown,
    mute,
    channelUp,
    channelDown,
    play,
    pause,
  ];

  /// Whether this key is part of the always-supported [core] set.
  bool get isCore => core.contains(this);

  /// Whether this key is one of the four directional pad keys.
  bool get isDpad =>
      this == RemoteKey.up ||
      this == RemoteKey.down ||
      this == RemoteKey.left ||
      this == RemoteKey.right;

  /// Whether this key is a 0-9 number-pad digit.
  bool get isDigit =>
      index >= RemoteKey.digit0.index && index <= RemoteKey.digit9.index;
}
