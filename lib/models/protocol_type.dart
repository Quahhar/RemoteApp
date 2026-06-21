/// The wire protocol a [Device] speaks. Every supported TV platform maps to
/// exactly one value here, and the [ControllerRegistry] uses it to pick the
/// right [RemoteController]. The UI never branches on this — it is metadata.
enum ProtocolType {
  /// Roku — External Control Protocol (ECP) over HTTP, discovered via SSDP.
  roku(label: 'Roku', defaultPort: 8060),

  /// LG webOS — SSAP over WebSocket; persists a client-key after first pairing.
  webos(label: 'LG webOS', defaultPort: 3000),

  /// Samsung Tizen — WebSocket remote control; persists a token after the
  /// on-TV allow prompt.
  tizen(label: 'Samsung', defaultPort: 8002),

  /// Android TV / Google TV — TLS "remote v2" with 6-digit pairing code.
  androidtv(label: 'Android TV', defaultPort: 6466),

  /// Hisense / VIDAA (and rebrands like Kenstar) — MQTT-over-TLS remote with a
  /// 4-digit on-screen pairing code.
  vidaa(label: 'Hisense / VIDAA TV', defaultPort: 36669);

  const ProtocolType({required this.label, required this.defaultPort});

  /// Human-readable brand name shown in the UI.
  final String label;

  /// Default TCP/UDP port for this protocol; a [Device] may override it.
  final int defaultPort;
}
