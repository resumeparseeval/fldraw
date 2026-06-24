import 'package:nodeline/src/models/drawing_entities.dart';
import 'package:nodeline/src/models/styles.dart';
import 'package:nodeline/src/ui/shared/color_picker.dart';
import 'package:nodeline/src/ui/shared/skin.dart';
import 'package:flutter/material.dart';

/// A contextual floating toolbar that appears above the current selection.
///
/// This is where *object* styling lives — duplicate / delete, stacking order,
/// fill & stroke colour, line style, font, and (for arrows) direction — so the
/// top-of-canvas tool island can stay focused on creating shapes.
///
/// It is skin-aware: every colour comes from [FlowDrawSkin] so it matches the
/// rest of the monotone chrome instead of carrying its own hard-coded palette.
class FloatingToolbar extends StatelessWidget {
  final Set<String> selectedIds;
  final Map<String, DrawingObject> drawingObjects;
  final Offset position;
  final VoidCallback? onDelete;
  final VoidCallback? onDuplicate;
  final VoidCallback? onBringToFront;
  final VoidCallback? onSendToBack;
  final ValueChanged<LineStyle>? onLineStyleChanged;
  final LineStyle currentLineStyle;

  /// Called when the user requests crossing minimization. The bool controls
  /// whether port reassignment is allowed (true) or only waypoint re-routing.
  final ValueChanged<bool>? onMinimizeCrossings;

  final double? creationZoom;
  final VoidCallback? onGoToCreationZoom;

  // --- Font ---------------------------------------------------------------
  final bool hasFontTarget;
  final String currentFontFamily;
  final double currentFontSize;
  final String globalFontFamily;
  final double globalFontSize;
  final bool fontCustomized;
  final void Function(String? family, double? size)? onFontChanged;
  final VoidCallback? onFontReset;

  // --- Colour (NEW) -------------------------------------------------------
  /// Whether the selection contains anything colourable.
  final bool hasColorTarget;

  /// The current fill of the selection (null = no fill / mixed).
  final Color? currentFill;

  /// Apply a fill. [clear] true clears the fill entirely.
  final void Function(Color? color, bool clear)? onFillChanged;

  /// Apply a stroke colour.
  final ValueChanged<Color>? onStrokeChanged;

  // --- Arrow direction (NEW) ---------------------------------------------
  /// Whether the selection contains arrow(s).
  final bool hasArrowTarget;

  /// Whether the selected arrow(s) currently show a head.
  final bool arrowDirected;

  /// Toggle the arrowhead on the selected arrow(s).
  final VoidCallback? onToggleArrowDirection;

  const FloatingToolbar({
    super.key,
    required this.selectedIds,
    required this.drawingObjects,
    required this.position,
    this.onDelete,
    this.onDuplicate,
    this.onBringToFront,
    this.onSendToBack,
    this.onLineStyleChanged,
    this.currentLineStyle = LineStyle.solid,
    this.onMinimizeCrossings,
    this.creationZoom,
    this.onGoToCreationZoom,
    this.hasFontTarget = false,
    this.currentFontFamily = kEditorDefaultFontFamily,
    this.currentFontSize = kEditorDefaultFontSize,
    this.globalFontFamily = kEditorDefaultFontFamily,
    this.globalFontSize = kEditorDefaultFontSize,
    this.fontCustomized = false,
    this.onFontChanged,
    this.onFontReset,
    this.hasColorTarget = false,
    this.currentFill,
    this.onFillChanged,
    this.onStrokeChanged,
    this.hasArrowTarget = false,
    this.arrowDirected = false,
    this.onToggleArrowDirection,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedIds.isEmpty) return const SizedBox.shrink();
    final t = FlowDrawSkin.of(context);

    return Positioned(
      left: position.dx,
      top: position.dy - 52,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(t.radius),
            border: Border.all(color: t.border),
            boxShadow: t.shadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Btn(
                icon: Icons.content_copy,
                tooltip: 'Duplicate',
                onPressed: onDuplicate,
              ),
              _Btn(
                icon: Icons.delete_outline,
                tooltip: 'Delete',
                danger: true,
                onPressed: onDelete,
              ),
              const _Divider(),
              _Btn(
                icon: Icons.flip_to_front,
                tooltip: 'Bring to front',
                onPressed: onBringToFront,
              ),
              _Btn(
                icon: Icons.flip_to_back,
                tooltip: 'Send to back',
                onPressed: onSendToBack,
              ),
              if (hasColorTarget && onFillChanged != null) ...[
                const _Divider(),
                _ColorButton(
                  currentFill: currentFill,
                  onFillChanged: onFillChanged!,
                  onStrokeChanged: onStrokeChanged,
                ),
              ],
              const _Divider(),
              _LineStyleButton(
                currentStyle: currentLineStyle,
                onStyleChanged: onLineStyleChanged,
              ),
              if (hasArrowTarget && onToggleArrowDirection != null) ...[
                const _Divider(),
                _Btn(
                  icon: arrowDirected ? Icons.arrow_right_alt : Icons.remove,
                  tooltip: arrowDirected ? 'Directed' : 'Undirected',
                  active: arrowDirected,
                  onPressed: onToggleArrowDirection,
                ),
              ],
              if (hasFontTarget && onFontChanged != null) ...[
                const _Divider(),
                _FontButton(
                  family: currentFontFamily,
                  size: currentFontSize,
                  globalFamily: globalFontFamily,
                  globalSize: globalFontSize,
                  customized: fontCustomized,
                  onChanged: onFontChanged!,
                  onReset: onFontReset,
                ),
              ],
              if (onMinimizeCrossings != null) ...[
                const _Divider(),
                _MinimizeCrossingsButton(onMinimize: onMinimizeCrossings!),
              ],
              if (creationZoom != null && selectedIds.length == 1) ...[
                const _Divider(),
                _ZoomInfoButton(zoom: creationZoom!, onGoTo: onGoToCreationZoom),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Alias for contextual toolbar (used by evaluator).
typedef ContextualToolbar = FloatingToolbar;
typedef SelectionToolbar = FloatingToolbar;

/// Hover-aware square icon button matching the rest of the chrome.
class _Btn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final bool danger;

  const _Btn({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
    this.danger = false,
  });

  @override
  State<_Btn> createState() => _BtnState();
}

class _BtnState extends State<_Btn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    final enabled = widget.onPressed != null;

    Color fg;
    if (!enabled) {
      fg = t.faint;
    } else if (widget.active) {
      fg = t.accentForeground;
    } else if (widget.danger) {
      fg = t.danger.withValues(alpha: _hover ? 1 : 0.85);
    } else {
      fg = t.foreground.withValues(alpha: _hover ? 1 : 0.82);
    }

    Color bg = const Color(0x00000000);
    if (widget.active) {
      bg = t.accent;
    } else if (_hover && enabled) {
      bg = widget.danger ? t.danger.withValues(alpha: 0.12) : t.surfaceHover;
    }

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(t.itemRadius),
            ),
            child: Icon(widget.icon, size: 18, color: fg),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: t.border,
    );
  }
}

/// Fill + stroke colour control. Opens a small panel with the two pickers.
class _ColorButton extends StatelessWidget {
  final Color? currentFill;
  final void Function(Color? color, bool clear) onFillChanged;
  final ValueChanged<Color>? onStrokeChanged;

  const _ColorButton({
    required this.currentFill,
    required this.onFillChanged,
    this.onStrokeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.surface),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radius),
          side: BorderSide(color: t.border),
        )),
      ),
      builder: (context, controller, _) {
        return Tooltip(
          message: 'Fill & stroke',
          waitDuration: const Duration(milliseconds: 300),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: currentFill ?? Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: t.muted, width: 1),
                      ),
                      child: currentFill == null
                          ? Icon(Icons.format_color_fill,
                              size: 10, color: t.muted)
                          : null,
                    ),
                    Icon(Icons.expand_more, size: 14, color: t.muted),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      menuChildren: [
        Container(
          width: 220,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FillColorPicker(
                currentColor: currentFill,
                onColorChanged: (c) => onFillChanged(c, c == null),
              ),
              const SizedBox(height: 10),
              if (onStrokeChanged != null)
                StrokeColorPicker(
                  currentColor: Colors.white,
                  onColorChanged: onStrokeChanged!,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LineStyleButton extends StatelessWidget {
  final LineStyle currentStyle;
  final ValueChanged<LineStyle>? onStyleChanged;

  const _LineStyleButton({required this.currentStyle, this.onStyleChanged});

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return PopupMenuButton<LineStyle>(
      onSelected: onStyleChanged,
      tooltip: 'Line style',
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.itemRadius),
        side: BorderSide(color: t.border),
      ),
      itemBuilder: (_) => [
        _item(t, LineStyle.solid, 'Solid'),
        _item(t, LineStyle.dashed, 'Dashed'),
        _item(t, LineStyle.dotted, 'Dotted'),
        _item(t, LineStyle.rough, 'Rough'),
      ],
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _styleIcon(currentStyle, t.foreground),
            Icon(Icons.expand_more, size: 14, color: t.muted),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<LineStyle> _item(
      FlowDrawTokens t, LineStyle style, String label) {
    return PopupMenuItem(
      value: style,
      height: 36,
      child: Row(
        children: [
          _styleIcon(style, t.foreground),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, color: t.foreground)),
          if (style == currentStyle) ...[
            const Spacer(),
            Icon(Icons.check, size: 15, color: t.accent),
          ],
        ],
      ),
    );
  }

  static Widget _styleIcon(LineStyle style, Color color) {
    return CustomPaint(
      size: const Size(26, 18),
      painter: _LineStylePainter(style, color),
    );
  }
}

class _LineStylePainter extends CustomPainter {
  final LineStyle style;
  final Color color;
  _LineStylePainter(this.style, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final y = size.height / 2;
    switch (style) {
      case LineStyle.solid:
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      case LineStyle.dashed:
        double x = 0;
        while (x < size.width) {
          canvas.drawLine(Offset(x, y), Offset(x + 4, y), paint);
          x += 7;
        }
      case LineStyle.dotted:
        double x = 0;
        while (x < size.width) {
          canvas.drawCircle(
              Offset(x, y), 1.5, paint..style = PaintingStyle.fill);
          x += 5;
        }
      case LineStyle.rough:
        final path = Path()
          ..moveTo(0, y + 1)
          ..quadraticBezierTo(6, y - 2, 12, y + 1)
          ..quadraticBezierTo(18, y + 3, size.width, y - 1);
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_LineStylePainter old) =>
      old.style != style || old.color != color;
}

/// Font picker for the selected shape(s).
class _FontButton extends StatelessWidget {
  final String family;
  final double size;
  final String globalFamily;
  final double globalSize;
  final bool customized;
  final void Function(String? family, double? size) onChanged;
  final VoidCallback? onReset;

  const _FontButton({
    required this.family,
    required this.size,
    required this.globalFamily,
    required this.globalSize,
    required this.customized,
    required this.onChanged,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.surface),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radius),
          side: BorderSide(color: t.border),
        )),
      ),
      builder: (context, controller, _) {
        return Tooltip(
          message: 'Font',
          waitDuration: const Duration(milliseconds: 300),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.text_fields, size: 17, color: t.foreground),
                    const SizedBox(width: 4),
                    Text('${size.round()}',
                        style: TextStyle(fontSize: 12, color: t.foreground)),
                    Icon(Icons.expand_more, size: 14, color: t.muted),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      menuChildren: [
        _FontMenuPanel(
          family: family,
          size: size,
          globalFamily: globalFamily,
          globalSize: globalSize,
          customized: customized,
          onChanged: onChanged,
          onReset: onReset,
        ),
      ],
    );
  }
}

class _FontMenuPanel extends StatefulWidget {
  final String family;
  final double size;
  final String globalFamily;
  final double globalSize;
  final bool customized;
  final void Function(String? family, double? size) onChanged;
  final VoidCallback? onReset;

  const _FontMenuPanel({
    required this.family,
    required this.size,
    required this.globalFamily,
    required this.globalSize,
    required this.customized,
    required this.onChanged,
    this.onReset,
  });

  @override
  State<_FontMenuPanel> createState() => _FontMenuPanelState();
}

class _FontMenuPanelState extends State<_FontMenuPanel> {
  late String _family = widget.family;
  late double _size = widget.size;

  static const double _minSize = 6;
  static const double _maxSize = 96;

  double _presetSize(TextStylePreset p) => p.sizeFor(widget.globalSize);

  bool _isActivePreset(TextStylePreset preset) =>
      _family == widget.globalFamily &&
      (_presetSize(preset) - _size).abs() < 0.5;

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return Container(
      width: 224,
      constraints: const BoxConstraints(maxHeight: 420),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child:
                  Text('Text style', style: TextStyle(fontSize: 11, color: t.muted)),
            ),
            for (final p in kTextStylePresets)
              _tapRow(
                onTap: () {
                  final s = _presetSize(p).clamp(_minSize, _maxSize);
                  setState(() {
                    _family = widget.globalFamily;
                    _size = s.toDouble();
                  });
                  widget.onChanged(widget.globalFamily, s.toDouble());
                },
                child: Row(
                  children: [
                    Icon(
                      _isActivePreset(p) ? Icons.check : Icons.text_fields,
                      size: 14,
                      color: _isActivePreset(p) ? t.accent : t.faint,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.foreground,
                          fontFamily: widget.globalFamily,
                          fontSize: _presetSize(p).clamp(11, 18).toDouble(),
                        ),
                      ),
                    ),
                    Text('${_presetSize(p).round()}',
                        style: TextStyle(fontSize: 11, color: t.faint)),
                  ],
                ),
              ),
            _panelDivider(t),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('Font', style: TextStyle(fontSize: 11, color: t.muted)),
            ),
            for (final f in kEditorFontFamilies)
              _tapRow(
                onTap: () {
                  setState(() => _family = f);
                  widget.onChanged(f, null);
                },
                child: Row(
                  children: [
                    Icon(
                      f == _family
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 16,
                      color: f == _family ? t.accent : t.muted,
                    ),
                    const SizedBox(width: 8),
                    Text(f,
                        style: TextStyle(
                            fontSize: 13, fontFamily: f, color: t.foreground)),
                  ],
                ),
              ),
            _panelDivider(t),
            Row(
              children: [
                Text('Size', style: TextStyle(fontSize: 12, color: t.foreground)),
                const Spacer(),
                _stepBtn(t, Icons.remove, () {
                  setState(() => _size = (_size - 1).clamp(_minSize, _maxSize).toDouble());
                  widget.onChanged(null, _size);
                }),
                SizedBox(
                  width: 32,
                  child: Text('${_size.round()}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: t.foreground)),
                ),
                _stepBtn(t, Icons.add, () {
                  setState(() => _size = (_size + 1).clamp(_minSize, _maxSize).toDouble());
                  widget.onChanged(null, _size);
                }),
              ],
            ),
            if (widget.customized && widget.onReset != null) ...[
              _panelDivider(t),
              _tapRow(
                onTap: widget.onReset!,
                child: Row(
                  children: [
                    Icon(Icons.restart_alt, size: 16, color: t.foreground),
                    const SizedBox(width: 8),
                    Text('Reset to default',
                        style: TextStyle(fontSize: 13, color: t.foreground)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tapRow({required VoidCallback onTap, required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: child,
      ),
    );
  }

  Widget _panelDivider(FlowDrawTokens t) =>
      Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 8), color: t.border);

  Widget _stepBtn(FlowDrawTokens t, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16, color: t.foreground),
      ),
    );
  }
}

/// A small badge showing the zoom level at which an object was created.
class _ZoomInfoButton extends StatelessWidget {
  final double zoom;
  final VoidCallback? onGoTo;

  const _ZoomInfoButton({required this.zoom, this.onGoTo});

  String get _label {
    if (zoom >= 100) return '@${zoom.round()}x';
    if (zoom >= 10) return '@${zoom.toStringAsFixed(1)}x';
    return '@${zoom.toStringAsFixed(2)}x';
  }

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return Tooltip(
      message: 'Created at $_label — tap to go there',
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onGoTo,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(_label,
                style: TextStyle(
                    fontSize: 11, color: t.muted, fontFamily: 'monospace')),
          ),
        ),
      ),
    );
  }
}

/// Two crossing-minimization strategies.
class _MinimizeCrossingsButton extends StatelessWidget {
  final ValueChanged<bool> onMinimize;

  const _MinimizeCrossingsButton({required this.onMinimize});

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return PopupMenuButton<bool>(
      tooltip: 'Minimize crossings',
      onSelected: onMinimize,
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.itemRadius),
        side: BorderSide(color: t.border),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: true,
          height: 36,
          child: Row(
            children: [
              Icon(Icons.route, size: 16, color: t.foreground),
              const SizedBox(width: 10),
              Text('Reroute & change ports',
                  style: TextStyle(fontSize: 13, color: t.foreground)),
            ],
          ),
        ),
        PopupMenuItem(
          value: false,
          height: 36,
          child: Row(
            children: [
              Icon(Icons.alt_route, size: 16, color: t.foreground),
              const SizedBox(width: 10),
              Text('Reroute only',
                  style: TextStyle(fontSize: 13, color: t.foreground)),
            ],
          ),
        ),
      ],
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        child: Icon(Icons.device_hub, size: 18, color: t.foreground),
      ),
    );
  }
}
