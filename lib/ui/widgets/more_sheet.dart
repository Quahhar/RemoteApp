import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/remote_key.dart';
import '../remote_actions.dart';
import '../../theme/app_colors.dart';
import 'upgrade_button.dart';

/// The "More Controls" bottom sheet from the mockup: the full extended command
/// set tucked behind the Remote screen's More button — number pad, quick keys,
/// playback, picture & sound, colour buttons, input/source and smart controls.
///
/// Every tile sends a [RemoteKey] through [pressKey], so an unsupported command
/// on the active TV surfaces the same de-duped "not available" SnackBar as the
/// rest of the app. (App Shortcuts from the mockup are intentionally omitted —
/// app deep-launch isn't implemented yet.)
///
/// The sheet itself opens for everyone (free users see the full set of
/// controls), but when [locked] is true (a non-Pro user) tapping any tile closes
/// the sheet and sends them to the upgrade page instead of firing the command.
Future<void> showMoreSheet(
  BuildContext context,
  WidgetRef ref, {
  bool locked = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x57141210),
    isScrollControlled: true,
    builder: (sheetContext) => _MoreSheet(
      onKey: (k) {
        if (locked) {
          Navigator.of(sheetContext).pop();
          UpgradeButton.open(context);
        } else {
          pressKey(context, ref, k);
        }
      },
    ),
  );
}

class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.onKey});
  final void Function(RemoteKey) onKey;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.86;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 44,
            offset: Offset(0, -12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 38,
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.dotGrid,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'More Controls',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                _CloseButton(onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                18,
                0,
                18,
                26 + MediaQuery.of(context).padding.bottom,
              ),
              child: _MoreBody(onKey: onKey),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreBody extends StatelessWidget {
  const _MoreBody({required this.onKey});
  final void Function(RemoteKey) onKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Number pad.
        _Grid(
          columns: 3,
          spacing: 10,
          children: [
            for (final pad in _digitPad)
              _PadTile(
                label: pad.label,
                onTap: () => onKey(pad.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Divider(height: 1, thickness: 1, color: AppColors.border),
        const SizedBox(height: 14),
        // Quick keys.
        _IconGrid(items: _quickKeys, onKey: onKey),

        _SectionLabel('Playback'),
        _IconGrid(items: _mediaKeys, onKey: onKey),

        _SectionLabel('Picture & Sound'),
        _IconGrid(items: _pictureKeys, onKey: onKey),

        _SectionLabel('Colour Buttons'),
        _Grid(
          columns: 4,
          spacing: 10,
          children: [
            for (final c in _colorKeys)
              _ColorTile(color: c.color, onTap: () => onKey(c.key)),
          ],
        ),

        _SectionLabel('Input / Source'),
        _Grid(
          columns: 3,
          spacing: 10,
          children: [
            for (final i in _inputKeys)
              _TextTile(label: i.label, onTap: () => onKey(i.key)),
          ],
        ),

        _SectionLabel('Smart'),
        _IconGrid(items: _smartKeys, onKey: onKey),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section data
// ---------------------------------------------------------------------------

class _Pad {
  const _Pad(this.label, this.key);
  final String label;
  final RemoteKey key;
}

const List<_Pad> _digitPad = [
  _Pad('1', RemoteKey.digit1),
  _Pad('2', RemoteKey.digit2),
  _Pad('3', RemoteKey.digit3),
  _Pad('4', RemoteKey.digit4),
  _Pad('5', RemoteKey.digit5),
  _Pad('6', RemoteKey.digit6),
  _Pad('7', RemoteKey.digit7),
  _Pad('8', RemoteKey.digit8),
  _Pad('9', RemoteKey.digit9),
  _Pad('—', RemoteKey.dash),
  _Pad('0', RemoteKey.digit0),
  // The mockup's backspace glyph: clears a partial channel entry → Back.
  _Pad('⌫', RemoteKey.back),
];

class _IconKey {
  const _IconKey(this.icon, this.label, this.key);
  final IconData icon;
  final String label;
  final RemoteKey key;
}

const List<_IconKey> _quickKeys = [
  _IconKey(Icons.volume_off, 'Mute', RemoteKey.mute),
  _IconKey(Icons.skip_previous, 'Previous', RemoteKey.previous),
  _IconKey(Icons.play_arrow, 'Play/Pause', RemoteKey.play),
  _IconKey(Icons.skip_next, 'Next', RemoteKey.next),
  _IconKey(Icons.input, 'Source', RemoteKey.source),
  _IconKey(Icons.closed_caption, 'Subtitles', RemoteKey.subtitles),
];

const List<_IconKey> _mediaKeys = [
  _IconKey(Icons.fast_rewind, 'Rewind', RemoteKey.rewind),
  _IconKey(Icons.stop, 'Stop', RemoteKey.stop),
  _IconKey(Icons.fast_forward, 'Forward', RemoteKey.fastForward),
  _IconKey(Icons.fiber_manual_record, 'Record', RemoteKey.record),
  _IconKey(Icons.live_tv, 'Live TV', RemoteKey.liveTv),
  _IconKey(Icons.grid_view, 'Guide', RemoteKey.guide),
];

const List<_IconKey> _pictureKeys = [
  _IconKey(Icons.image, 'Picture', RemoteKey.pictureMode),
  _IconKey(Icons.bedtime, 'Sleep', RemoteKey.sleep),
  _IconKey(Icons.aspect_ratio, 'Aspect', RemoteKey.aspect),
  _IconKey(Icons.music_note, 'Audio', RemoteKey.audioTrack),
];

const List<_IconKey> _smartKeys = [
  _IconKey(Icons.settings, 'Settings', RemoteKey.settings),
  _IconKey(Icons.search, 'Search', RemoteKey.search),
  _IconKey(Icons.mic, 'Voice', RemoteKey.voiceAssist),
  _IconKey(Icons.notifications, 'Alerts', RemoteKey.notifications),
];

class _ColorKey {
  const _ColorKey(this.color, this.key);
  final Color color;
  final RemoteKey key;
}

const List<_ColorKey> _colorKeys = [
  _ColorKey(Color(0xFFE0564E), RemoteKey.colorRed),
  _ColorKey(Color(0xFF3FA75A), RemoteKey.colorGreen),
  _ColorKey(Color(0xFFE8B53D), RemoteKey.colorYellow),
  _ColorKey(Color(0xFF3B7BD4), RemoteKey.colorBlue),
];

class _InputKey {
  const _InputKey(this.label, this.key);
  final String label;
  final RemoteKey key;
}

const List<_InputKey> _inputKeys = [
  _InputKey('HDMI 1', RemoteKey.inputHdmi1),
  _InputKey('HDMI 2', RemoteKey.inputHdmi2),
  _InputKey('HDMI 3', RemoteKey.inputHdmi3),
  _InputKey('AV', RemoteKey.inputAv),
  _InputKey('TV', RemoteKey.inputTv),
];

// ---------------------------------------------------------------------------
// Layout + tiles
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 20, 2, 9),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: AppColors.textFaint,
        ),
      ),
    );
  }
}

/// A simple fixed-column grid built from a Wrap so tiles size to the row width.
class _Grid extends StatelessWidget {
  const _Grid({
    required this.columns,
    required this.spacing,
    required this.children,
  });

  final int columns;
  final double spacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _IconGrid extends StatelessWidget {
  const _IconGrid({required this.items, required this.onKey});
  final List<_IconKey> items;
  final void Function(RemoteKey) onKey;

  @override
  Widget build(BuildContext context) {
    return _Grid(
      columns: 3,
      spacing: 10,
      children: [
        for (final item in items)
          _IconTile(
            icon: item.icon,
            label: item.label,
            onTap: () => onKey(item.key),
          ),
      ],
    );
  }
}

/// Shared press-down behaviour: white card that washes amber while held.
class _Tappable extends StatefulWidget {
  const _Tappable({required this.builder, required this.onTap});
  final Widget Function(bool down) builder;
  final VoidCallback onTap;

  @override
  State<_Tappable> createState() => _TappableState();
}

class _TappableState extends State<_Tappable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: widget.builder(_down),
    );
  }
}

BoxDecoration _cardDecoration(bool down) => BoxDecoration(
      color: down ? AppColors.accentSoft : AppColors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
      boxShadow: const [
        BoxShadow(color: Color(0x08000000), blurRadius: 2, offset: Offset(0, 1)),
      ],
    );

class _PadTile extends StatelessWidget {
  const _PadTile({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Tappable(
      onTap: onTap,
      builder: (down) => Container(
        height: 52,
        alignment: Alignment.center,
        decoration: _cardDecoration(down),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w500,
            color: down ? AppColors.accentText : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Tappable(
      onTap: onTap,
      builder: (down) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: _cardDecoration(down),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 24,
                color: down ? AppColors.accentText : AppColors.textPrimary),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextTile extends StatelessWidget {
  const _TextTile({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Tappable(
      onTap: onTap,
      builder: (down) => Container(
        height: 46,
        alignment: Alignment.center,
        decoration: _cardDecoration(down),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: down ? AppColors.accentText : AppColors.dpadArrow,
          ),
        ),
      ),
    );
  }
}

class _ColorTile extends StatelessWidget {
  const _ColorTile({required this.color, required this.onTap});
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Tappable(
      onTap: onTap,
      builder: (down) => Opacity(
        opacity: down ? 0.65 : 1,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(13),
            boxShadow: const [
              BoxShadow(
                color: Color(0x29000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.border,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(Icons.close, size: 19, color: AppColors.textMuted),
        ),
      ),
    );
  }
}
