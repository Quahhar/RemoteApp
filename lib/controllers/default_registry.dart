import '../models/protocol_type.dart';
import 'controller_registry.dart';
import 'roku_controller.dart';

/// The single place protocols are wired to their implementations. Add a new
/// protocol here and the rest of the app (discovery fan-out, connection,
/// control) picks it up with no other changes.
///
/// LG webOS, Samsung Tizen, and Android TV are added in a later milestone.
ControllerRegistry buildControllerRegistry() => ControllerRegistry({
      ProtocolType.roku: () => RokuController(),
    });
