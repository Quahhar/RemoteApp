import 'package:flutter/foundation.dart';

import 'protocol_type.dart';

/// A saved or discovered TV.
///
/// Identity is the stable [id] (e.g. a Roku serial / device UDN, or
/// `protocol-host` for a manual add) so the same physical TV de-duplicates
/// across rediscovery and survives an IP change after a manual re-add.
/// Fully JSON-serializable for persistence via shared_preferences.
@immutable
class Device {
  const Device({
    required this.id,
    required this.name,
    required this.host,
    required this.protocol,
    this.port,
    this.authToken,
    this.lastConnected,
  });

  /// Stable unique identifier (independent of [host]).
  final String id;

  /// Friendly name shown in the UI (e.g. "Living Room Roku").
  final String name;

  /// IP address or hostname on the LAN.
  final String host;

  /// Which [RemoteController] drives this device.
  final ProtocolType protocol;

  /// Optional port override; defaults to [ProtocolType.defaultPort].
  final int? port;

  /// Persisted credential: LG client-key, Samsung token, or Android TV creds.
  /// Null until the device has been paired.
  final String? authToken;

  /// When we last successfully connected; used to sort the device list.
  final DateTime? lastConnected;

  /// Effective port to talk to, honoring an override.
  int get effectivePort => port ?? protocol.defaultPort;

  /// True once this device has stored pairing credentials.
  bool get isPaired => authToken != null && authToken!.isNotEmpty;

  Device copyWith({
    String? id,
    String? name,
    String? host,
    ProtocolType? protocol,
    int? port,
    String? authToken,
    DateTime? lastConnected,
  }) {
    return Device(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      protocol: protocol ?? this.protocol,
      port: port ?? this.port,
      authToken: authToken ?? this.authToken,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'protocol': protocol.name,
        if (port != null) 'port': port,
        if (authToken != null) 'authToken': authToken,
        if (lastConnected != null)
          'lastConnected': lastConnected!.toIso8601String(),
      };

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as String,
        name: json['name'] as String,
        host: json['host'] as String,
        protocol: ProtocolType.values.byName(json['protocol'] as String),
        port: json['port'] as int?,
        authToken: json['authToken'] as String?,
        lastConnected: json['lastConnected'] == null
            ? null
            : DateTime.parse(json['lastConnected'] as String),
      );

  @override
  bool operator ==(Object other) => other is Device && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Device($id, $name, ${protocol.name}@$host:$effectivePort)';
}
