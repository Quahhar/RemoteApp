import '../models/protocol_type.dart';
import 'remote_controller.dart';

/// Maps a [ProtocolType] to the [RemoteController] that drives it.
///
/// Controllers are created lazily and cached — one instance per protocol, each
/// managing at most one active connection. This is the *only* place protocols
/// are wired to implementations; the rest of the app resolves controllers
/// through here and never constructs them directly.
class ControllerRegistry {
  ControllerRegistry(this._factories);

  final Map<ProtocolType, RemoteController Function()> _factories;
  final Map<ProtocolType, RemoteController> _instances = {};

  /// The controller for [type], created on first use and cached thereafter.
  RemoteController controllerFor(ProtocolType type) {
    final factory = _factories[type];
    if (factory == null) {
      throw ArgumentError('No controller registered for $type');
    }
    return _instances.putIfAbsent(type, factory);
  }

  /// All protocols this registry can drive (e.g. to fan out discovery).
  List<ProtocolType> get protocols => _factories.keys.toList(growable: false);

  /// Eagerly resolves and returns a controller for every registered protocol.
  Iterable<RemoteController> get all => protocols.map(controllerFor);

  /// Dispose every instantiated controller and clear the cache.
  void disposeAll() {
    for (final controller in _instances.values) {
      controller.dispose();
    }
    _instances.clear();
  }
}
