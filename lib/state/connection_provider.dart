import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection_status.dart';
import 'active_device_provider.dart';

/// Live connection status of the active controller. Seeds with the controller's
/// current status, then follows its broadcast stream. Disconnected when there
/// is no active device.
final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) async* {
  final controller = ref.watch(activeControllerProvider);
  if (controller == null) {
    yield ConnectionStatus.disconnected;
    return;
  }
  yield controller.status;
  yield* controller.statusStream;
});
