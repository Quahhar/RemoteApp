import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/controller_registry.dart';
import '../controllers/default_registry.dart';
import '../persistence/atv_identity_store.dart';
import '../persistence/device_store.dart';
import '../persistence/vidaa_identity_store.dart';

/// Provides the loaded [SharedPreferences]. Overridden in `main()` with the
/// already-resolved instance so the rest of the tree can read it synchronously.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main() with the loaded '
    'SharedPreferences instance.',
  );
});

/// Persistence for saved devices + active selection.
final deviceStoreProvider = Provider<DeviceStore>(
  (ref) => DeviceStore(ref.watch(sharedPreferencesProvider)),
);

/// The protocol -> controller registry. Disposed with the provider container.
final controllerRegistryProvider = Provider<ControllerRegistry>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final registry = buildControllerRegistry(
    atvIdentity: AtvIdentityStore(prefs),
    vidaaIdentity: VidaaIdentityStore(prefs),
  );
  ref.onDispose(registry.disposeAll);
  return registry;
});
