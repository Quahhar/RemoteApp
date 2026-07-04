import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ads/ad_service.dart';
import '../../controllers/remote_controller.dart';
import '../../models/connection_status.dart';
import '../../models/device.dart';
import '../../models/protocol_type.dart';
import '../../state/active_device_provider.dart';
import '../../state/app_providers.dart';
import '../../state/connection_provider.dart';
import '../../state/discovery_provider.dart';
import '../../state/preferences_provider.dart';
import '../../state/saved_devices_provider.dart';
import '../../theme/app_colors.dart';
import '../snackbar.dart';
import '../widgets/upgrade_button.dart';
import 'settings_screen.dart';

/// Devices tab — matches the mockup: a "Devices" header with a Settings gear and
/// a Scan button, a radar card while scanning, a "Found on network" list, a
/// "Recently connected" list, and an inline "Add manually" card. Selecting a
/// device makes it active and connects (running code pairing first when needed).
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovery = ref.watch(discoveryProvider);
    final active = ref.watch(activeDeviceProvider);
    final status = ref.watch(connectionStatusProvider).value ??
        ConnectionStatus.disconnected;
    // Repaint on palette flips (AppColors getters aren't reactive on their own).
    ref.watch(effectiveDarkModeProvider);

    // Discovered devices, excluding the one already shown in "Connected" so it
    // isn't listed twice. Match on id *or* (protocol, host) so the same TV found
    // by both SSDP (rich id) and the LAN port scan (host-based id) de-dupes.
    final newlyFound = discovery.devices
        .where((d) =>
            active == null ||
            (d.id != active.id &&
                !(d.protocol == active.protocol && d.host == active.host)))
        .toList();

    bool isConnected(Device d) =>
        active?.id == d.id && status == ConnectionStatus.connected;

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
      children: [
        _Header(
          scanning: discovery.scanning,
          onScan: () => discovery.scanning
              ? ref.read(discoveryProvider.notifier).stop()
              : ref.read(discoveryProvider.notifier).scan(),
          onSettings: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
        const SizedBox(height: 18),
        if (active != null) ...[
          // Helper widgets that read AppColors in build are instantiated
          // non-const throughout so they repaint after a dark-mode toggle.
          _SectionLabel('Connected'),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _DeviceCard(
              device: active,
              found: false,
              connected: isConnected(active),
              onConnect: () => _select(context, ref, active),
              onRemove: () =>
                  ref.read(savedDevicesProvider.notifier).remove(active.id),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (discovery.scanning) ...[
          _ScanningCard(),
          const SizedBox(height: 18),
        ],
        if (newlyFound.isNotEmpty) ...[
          _SectionLabel('Found on network'),
          for (final device in newlyFound)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DeviceCard(
                device: device,
                found: true,
                connected: isConnected(device),
                onConnect: () => _select(context, ref, device),
              ),
            ),
          const SizedBox(height: 8),
        ] else if (!discovery.scanning && active == null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No device connected. Scan, or add one manually below.',
              style: TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
          ),
        ],
        _ManualAddCard(onSubmit: (device) => _select(context, ref, device)),
      ],
    );
  }

  Future<void> _select(
      BuildContext context, WidgetRef ref, Device device) async {
    final controller =
        ref.read(controllerRegistryProvider).controllerFor(device.protocol);
    // Code-based pairing (Android TV / VIDAA) must happen before we connect.
    if (controller.capabilities.requiresPairingCode && !device.isPaired) {
      await _pairThenConnect(context, ref, controller, device);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    showSnack(messenger, 'Connecting to ${device.name}…');
    try {
      await ref.read(activeDeviceProvider.notifier).select(device);
      showSnack(messenger, 'Connected to ${device.name}');
      // The only ad trigger: a natural break, never during remote use. (If the
      // UI is later redesigned, keep this one call to preserve ad behaviour.)
      // Fire-and-forget: the service runs its own countdown and shows the ad.
      ref.read(adServiceProvider).maybeShowAfterConnect();
    } on RemoteException catch (e) {
      await _connectOrFallback(messenger, ref, device, e.message);
    } catch (_) {
      await _connectOrFallback(
          messenger, ref, device, 'Could not connect to the device');
    }
  }

  /// Last resort when a device's own protocol won't connect: try the same TV
  /// over DLNA (its built-in remote may be firmware-locked while its media
  /// renderer is open). Shows the cast result on success, else the original
  /// error. No-op fallback for devices that are already DLNA.
  Future<void> _connectOrFallback(
    ScaffoldMessengerState messenger,
    WidgetRef ref,
    Device device,
    String originalError,
  ) async {
    final fallback = await ref
        .read(activeDeviceProvider.notifier)
        .connectViaDlnaFallback(device);
    // Keep the original failure visible in the fallback message — silently
    // switching to Cast made it look like the native protocol never existed.
    showSnack(
      messenger,
      fallback != null
          ? '$originalError\nConnected to ${device.name} over Cast instead — '
              'volume, mute and play/pause will work.'
          : originalError,
    );
  }

  /// Run the on-TV code pairing, then connect. Generic over any controller that
  /// declares [Capabilities.requiresPairingCode] — no brand logic here.
  Future<void> _pairThenConnect(
    BuildContext context,
    WidgetRef ref,
    RemoteController controller,
    Device device,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    showSnack(messenger, 'Pairing with ${device.name}…');
    try {
      await controller.beginPairing(device);
    } on RemoteException catch (e) {
      await _connectOrFallback(messenger, ref, device, e.message);
      return;
    } catch (_) {
      await _connectOrFallback(messenger, ref, device, 'Could not reach the TV');
      return;
    }
    messenger.removeCurrentSnackBar();
    if (!context.mounted) return;

    final code = await showDialog<String>(
      context: context,
      builder: (_) => _PairingCodeDialog(deviceName: device.name),
    );
    if (code == null || code.isEmpty) {
      await controller.disconnect();
      return;
    }

    try {
      await controller.completePairing(code);
    } on RemoteException catch (e) {
      showSnack(messenger, e.message);
      return;
    }

    final token = controller.authToken;
    if (token == null) {
      showSnack(messenger, 'Pairing failed. Please try again.');
      return;
    }
    if (!context.mounted) return;
    await _select(context, ref, device.copyWith(authToken: token));
  }
}

IconData protocolIcon(ProtocolType protocol) => switch (protocol) {
      ProtocolType.roku => Icons.cast,
      ProtocolType.webos => Icons.tv,
      ProtocolType.tizen => Icons.tv,
      ProtocolType.androidtv => Icons.android,
      ProtocolType.vidaa => Icons.connected_tv,
      ProtocolType.dlna => Icons.cast_connected,
    };

// ---------------------------------------------------------------------------
// Header: title + Settings gear + Scan
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.scanning,
    required this.onScan,
    required this.onSettings,
  });

  final bool scanning;
  final VoidCallback onScan;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
      child: Row(
        children: [
          Expanded(
            // On narrow phones (especially with a larger system font) the
            // trailing Upgrade/gear/Scan buttons squeeze this slot below the
            // title's natural width and the text wraps/clips. Scale it down
            // to fit on one line instead.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Devices',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const UpgradeButton(),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onSettings,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.settings_outlined,
                size: 22, color: AppColors.textMuted),
          ),
          const SizedBox(width: 4),
          _ScanButton(scanning: scanning, onTap: onScan),
        ],
      ),
    );
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.scanning, required this.onTap});
  final bool scanning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Container(
          // Fixed width with a Scan<->Stop label (near-identical widths) so the
          // button never reflows the row — which used to squeeze the "Devices"
          // title. The radar card below conveys that a scan is in progress.
          width: 84,
          height: 38,
          alignment: Alignment.center,
          child: Text(
            scanning ? 'Stop' : 'Scan',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scanning radar card
// ---------------------------------------------------------------------------

class _ScanningCard extends StatelessWidget {
  const _ScanningCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            spreadRadius: -6,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const _Radar(),
          const SizedBox(height: 14),
          Text(
            'Scanning your network…',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Radar extends StatefulWidget {
  const _Radar();

  @override
  State<_Radar> createState() => _RadarState();
}

class _RadarState extends State<_Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      height: 90,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) => CustomPaint(painter: _RadarPainter(_c.value)),
            ),
          ),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.wifi, size: 24, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (final offset in [0.0, 0.5]) {
      final p = (t + offset) % 1.0;
      final radius = 15 + p * 33; // expands outward
      final paint = Paint()
        ..color = AppColors.accent.withValues(alpha: 0.18 * (1 - p));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.t != t;
}

// ---------------------------------------------------------------------------
// Section label + device cards
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.found,
    required this.connected,
    required this.onConnect,
    this.onRemove,
  });

  final Device device;
  final bool found;
  final bool connected;
  final VoidCallback onConnect;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final iconBg = found ? AppColors.accentSoft : AppColors.fieldBg;
    final iconFg = found ? AppColors.accent : AppColors.textMuted;

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: connected ? null : onConnect,
        onLongPress: onRemove == null ? null : () => _confirmRemove(context),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 12,
                spreadRadius: -6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(protocolIcon(device.protocol),
                    size: 22, color: iconFg),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${device.protocol.label} • ${device.host}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (connected)
                _ConnectedChip()
              else
                _ConnectButton(found: found, onTap: onConnect),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Forget ${device.name}?'),
        content: const Text('This removes it from your saved devices.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (remove == true) onRemove?.call();
  }
}

class _ConnectedChip extends StatelessWidget {
  const _ConnectedChip();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check, size: 16, color: AppColors.green),
        const SizedBox(width: 5),
        Text(
          'Connected',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.green,
          ),
        ),
      ],
    );
  }
}

class _ConnectButton extends StatelessWidget {
  const _ConnectButton({required this.found, required this.onTap});
  final bool found;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = found ? AppColors.accentSoft : AppColors.fieldBg;
    final fg = found ? AppColors.accent : AppColors.textPrimary;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          alignment: Alignment.center,
          child: Text(
            'Connect',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inline manual add
// ---------------------------------------------------------------------------

class _ManualAddCard extends StatefulWidget {
  const _ManualAddCard({required this.onSubmit});
  final void Function(Device) onSubmit;

  @override
  State<_ManualAddCard> createState() => _ManualAddCardState();
}

class _ManualAddCardState extends State<_ManualAddCard> {
  final _ip = TextEditingController();
  ProtocolType _protocol = ProtocolType.roku;

  @override
  void dispose() {
    _ip.dispose();
    super.dispose();
  }

  void _add() {
    final host = _ip.text.trim();
    if (host.isEmpty) return;
    final device = Device(
      id: '${_protocol.name}-$host',
      name: '${_protocol.label} ($host)',
      host: host,
      protocol: _protocol,
    );
    _ip.clear();
    FocusScope.of(context).unfocus();
    widget.onSubmit(device);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            spreadRadius: -6,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 11),
            child: Text(
              'ADD MANUALLY',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: AppColors.textMuted,
              ),
            ),
          ),
          // Brand picker.
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.fieldBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ProtocolType>(
                value: _protocol,
                isExpanded: true,
                icon: Icon(Icons.expand_more, color: AppColors.textMuted),
                style: TextStyle(
                    fontSize: 15, color: AppColors.textPrimary),
                items: [
                  for (final p in ProtocolType.values)
                    DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                onChanged: (p) => setState(() => _protocol = p ?? _protocol),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // IP + Add.
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.fieldBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: TextField(
                    controller: _ip,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _add(),
                    style: TextStyle(
                        fontSize: 15, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'IP address e.g. 192.168.1.10',
                      hintStyle: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: _add,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    alignment: Alignment.center,
                    child: const Text(
                      'Add',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Collects the code the TV shows during pairing (Android TV / VIDAA).
class _PairingCodeDialog extends StatefulWidget {
  const _PairingCodeDialog({required this.deviceName});
  final String deviceName;

  @override
  State<_PairingCodeDialog> createState() => _PairingCodeDialogState();
}

class _PairingCodeDialogState extends State<_PairingCodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter pairing code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Enter the code shown on ${widget.deviceName}.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'e.g. 4A7B2C',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Pair')),
      ],
    );
  }
}
