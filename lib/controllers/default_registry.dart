import '../models/protocol_type.dart';
import '../persistence/atv_identity_store.dart';
import '../persistence/vidaa_identity_store.dart';
import 'androidtv_controller.dart';
import 'controller_registry.dart';
import 'dlna_controller.dart';
import 'hisense_controller.dart';
import 'roku_controller.dart';
import 'tizen_controller.dart';
import 'webos_controller.dart';

/// The single place protocols are wired to their implementations. Add a new
/// protocol here and the rest of the app (discovery fan-out, connection,
/// control) picks it up with no other changes.
ControllerRegistry buildControllerRegistry({
  required AtvIdentityStore atvIdentity,
  required VidaaIdentityStore vidaaIdentity,
}) =>
    ControllerRegistry({
      ProtocolType.roku: () => RokuController(),
      ProtocolType.webos: () => WebosController(),
      ProtocolType.tizen: () => TizenController(),
      ProtocolType.androidtv: () => AndroidTvController(identity: atvIdentity),
      ProtocolType.vidaa: () => HisenseController(identity: vidaaIdentity),
      ProtocolType.dlna: () => DlnaController(),
    });
