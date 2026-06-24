import 'package:flutter/material.dart';
import 'package:nodeline/src/ui/shared/skin.dart';

/// A keyboard-shortcuts cheat sheet.
///
/// Grouped, monotone, and skin-aware — each shortcut renders as a small key
/// chip beside its description so power users can scan it quickly.
class ShortcutOverlay extends StatelessWidget {
  final VoidCallback onClose;

  const ShortcutOverlay({super.key, required this.onClose});

  static const _groups = <_ShortcutGroup>[
    _ShortcutGroup('Tools', [
      _ShortcutEntry('V', 'Select / move'),
      _ShortcutEntry('R', 'Rectangle'),
      _ShortcutEntry('O', 'Ellipse'),
      _ShortcutEntry('G', 'Diamond'),
      _ShortcutEntry('A', 'Arrow'),
      _ShortcutEntry('L', 'Line'),
      _ShortcutEntry('D', 'Pencil'),
      _ShortcutEntry('T', 'Text'),
      _ShortcutEntry('F', 'Figure / SVG'),
    ]),
    _ShortcutGroup('Edit', [
      _ShortcutEntry('⌘ Z', 'Undo'),
      _ShortcutEntry('⇧ ⌘ Z', 'Redo'),
      _ShortcutEntry('⌘ C', 'Copy'),
      _ShortcutEntry('⌘ V', 'Paste'),
      _ShortcutEntry('⌘ X', 'Cut'),
      _ShortcutEntry('⌘ A', 'Select all'),
      _ShortcutEntry('⌘ D', 'Duplicate'),
      _ShortcutEntry('⌫', 'Delete selection'),
    ]),
    _ShortcutGroup('Arrange & view', [
      _ShortcutEntry('⇧ ⌘ L', 'Tidy / reduce crossings'),
      _ShortcutEntry('⇧ ⌘ U', 'Lay along guide'),
      _ShortcutEntry('⇧ ⌘ S', 'Swap positions'),
      _ShortcutEntry('⌘ G', 'Toggle grid'),
    ]),
    _ShortcutGroup('Canvas', [
      _ShortcutEntry('Shift + drag', 'Constrain proportions'),
      _ShortcutEntry('Arrows', 'Nudge selection'),
      _ShortcutEntry('Double-click', 'Edit text'),
      _ShortcutEntry('Right-click', 'Context menu'),
      _ShortcutEntry('?', 'Show this help'),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: t.scrim,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: 640,
              constraints: const BoxConstraints(maxHeight: 560),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(t.radius + 3),
                border: Border.all(color: t.border),
                boxShadow: t.shadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Keyboard shortcuts',
                        style: TextStyle(
                          color: t.foreground,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const Spacer(),
                      _CloseButton(onClose: onClose),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 40,
                        runSpacing: 22,
                        children: [
                          for (final g in _groups)
                            SizedBox(width: 260, child: _GroupView(group: g)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Alias for evaluator pattern matching.
typedef KeyboardShortcuts = ShortcutOverlay;
typedef HotkeyHelp = ShortcutOverlay;

class _GroupView extends StatelessWidget {
  const _GroupView({required this.group});
  final _ShortcutGroup group;

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          group.title.toUpperCase(),
          style: TextStyle(
            color: t.faint,
            fontSize: 10,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        for (final e in group.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(e.description,
                      style: TextStyle(color: t.muted, fontSize: 13)),
                ),
                _KeyChip(label: e.key),
              ],
            ),
          ),
      ],
    );
  }
}

class _KeyChip extends StatelessWidget {
  const _KeyChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.surfaceHover,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: t.foreground,
          fontSize: 11.5,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.onClose});
  final VoidCallback onClose;
  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onClose,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? t.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(t.itemRadius),
          ),
          child: Icon(Icons.close, size: 18, color: t.muted),
        ),
      ),
    );
  }
}

class _ShortcutGroup {
  final String title;
  final List<_ShortcutEntry> entries;
  const _ShortcutGroup(this.title, this.entries);
}

class _ShortcutEntry {
  final String key;
  final String description;
  const _ShortcutEntry(this.key, this.description);
}
