import '../models/protocol_type.dart';
import 'androidtv_controller.dart';
import 'controller_registry.dart';
import 'roku_controller.dart';
import 'tizen_controller.dart';
import 'webos_controller.dart';

/// The single place protocols are wired to their implementations. Add a new
/// protocol here and the rest of the app (discovery fan-out, connection,
/// control) picks it up with no other changes.
ControllerRegistry buildControllerRegistry() => ControllerRegistry({
      ProtocolType.roku: () => RokuController(),
      ProtocolType.webos: () => WebosController(),
      ProtocolType.tizen: () => TizenController(),
      ProtocolType.androidtv: () => AndroidTvController(),
    });
