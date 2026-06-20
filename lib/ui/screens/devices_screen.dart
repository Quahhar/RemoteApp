import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/remote_controller.dart';
import '../../models/device.dart';
import '../../models/protocol_type.dart';
import '../../state/active_device_provider.dart';
import '../../state/discovery_provider.dart';
import '../../state/saved_devices_provider.dart';
import '../widgets/screen_header.dart';

/// Device manager: saved devices, a live cross-protocol scan, and manual add by
/// IP + brand. Selecting a device makes it active and connects.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedDevicesProvider);
    final discovery = ref.watch(discoveryProvider);
    final active = ref.watch(activeDeviceProvider);

    // Discovered devices not already in the saved list.
    final savedIds = saved.map((d) => d.id).toSet();
    final newlyFound =
        discovery.devices.where((d) => !savedIds.contains(d.id)).toList();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const ScreenHeader('Devices'),
            _ScanBar(
              scanning: discovery.scanning,
              onScan: () => ref.read(discoveryProvider.notifier).scan(),
              onStop: () => ref.read(discoveryProvider.notifier).stop(),
            ),
            if (saved.isNotEmpty) ...[
              const _SectionHeader('Saved'),
              for (final device in saved)
                _DeviceTile(
                  device: device,
                  isActive: device.id == active?.id,
                  onTap: () => _select(context, ref, device),
                  onRemove: () =>
                      ref.read(savedDevicesProvider.notifier).remove(device.id),
                ),
            ],
            _SectionHeader(
              newlyFound.isEmpty && !discovery.scanning ? 'Discovered' : 'Found',
            ),
            if (newlyFound.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  discovery.scanning
                      ? 'Scanning your network…'
                      : 'No new devices. Tap Scan, or add one manually.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final device in newlyFound)
                _DeviceTile(
                  device: device,
                  isActive: false,
                  onTap: () => _select(context, ref, device),
                ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showManualAdd(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add manually'),
      ),
    );
  }

  Future<void> _select(
      BuildContext context, WidgetRef ref, Device device) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Connecting to ${device.name}…')),
    );
    try {
      await ref.read(activeDeviceProvider.notifier).select(device);
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Connected to ${device.name}')),
      );
    } on RemoteException catch (e) {
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not connect to the device')),
      );
    }
  }

  Future<void> _showManualAdd(BuildContext context, WidgetRef ref) async {
    final device = await showDialog<Device>(
      context: context,
      builder: (_) => const _ManualAddDialog(),
    );
    if (device != null && context.mounted) {
      await _select(context, ref, device);
    }
  }
}

IconData protocolIcon(ProtocolType protocol) => switch (protocol) {
      ProtocolType.roku => Icons.cast,
      ProtocolType.webos => Icons.tv,
      ProtocolType.tizen => Icons.tv,
      ProtocolType.androidtv => Icons.android,
    };

class _ScanBar extends StatelessWidget {
  const _ScanBar({
    required this.scanning,
    required this.onScan,
    required this.onStop,
  });

  final bool scanning;
  final VoidCallback onScan;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: scanning
                ? const LinearProgressIndicator()
                : Text(
                    'Scan your Wi-Fi for TVs',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          scanning
              ? TextButton.icon(
                  onPressed: onStop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                )
              : FilledButton.tonalIcon(
                  onPressed: onScan,
                  icon: const Icon(Icons.search),
                  label: const Text('Scan'),
                ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isActive,
    required this.onTap,
    this.onRemove,
  });

  final Device device;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isActive ? scheme.primaryContainer : null,
      child: ListTile(
        leading: Icon(protocolIcon(device.protocol)),
        title: Text(device.name),
        subtitle: Text('${device.protocol.label} · ${device.host}'),
        trailing: isActive
            ? Icon(Icons.check_circle, color: scheme.primary)
            : (onRemove == null
                ? const Icon(Icons.add_circle_outline)
                : IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onRemove,
                  )),
        onTap: onTap,
      ),
    );
  }
}

class _ManualAddDialog extends StatefulWidget {
  const _ManualAddDialog();

  @override
  State<_ManualAddDialog> createState() => _ManualAddDialogState();
}

class _ManualAddDialogState extends State<_ManualAddDialog> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _nameController = TextEditingController();
  ProtocolType _protocol = ProtocolType.roku;

  @override
  void dispose() {
    _hostController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final host = _hostController.text.trim();
    final name = _nameController.text.trim();
    final device = Device(
      id: '${_protocol.name}-$host',
      name: name.isEmpty ? '${_protocol.label} ($host)' : name,
      host: host,
      protocol: _protocol,
    );
    Navigator.of(context).pop(device);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add device'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<ProtocolType>(
              initialValue: _protocol,
              decoration: const InputDecoration(labelText: 'Brand'),
              items: [
                for (final p in ProtocolType.values)
                  DropdownMenuItem(value: p, child: Text(p.label)),
              ],
              onChanged: (p) => setState(() => _protocol = p ?? _protocol),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'IP address',
                hintText: '192.168.1.50',
              ),
              keyboardType: TextInputType.url,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return 'Required';
                if (!RegExp(r'^[\w.\-:]+$').hasMatch(value)) {
                  return 'Enter a valid IP or hostname';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                hintText: 'Living Room TV',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
