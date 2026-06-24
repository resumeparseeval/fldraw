import 'dart:io';
import 'dart:math';

import 'package:nodeline/nodeline.dart';
import 'package:nodeline/src/constants.dart';
import 'package:nodeline/src/core/utils/renderbox.dart';
import 'package:nodeline/src/core/utils/snackbar.dart';
import 'package:nodeline/src/core/utils/svg_exporter.dart';
import 'package:nodeline/src/gen/assets.gen.dart';
import 'package:nodeline/src/ui/shared/skin.dart';
import 'package:nodeline/src/ui/canvas/rich_text_editing_controller.dart';
import 'package:nodeline/src/ui/shared/active_text_editing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide TabItem;
import 'package:uuid/uuid.dart';

/// The Cmd (macOS) / Ctrl (other) symbol for shortcut hints in tooltips.
final String _kCmdKey = Platform.isMacOS ? '⌘' : 'Ctrl';

// ===========================================================================
//  Shared chrome primitives
// ===========================================================================

/// Wraps [child] in a tooltip showing a [description] and an optional
/// [shortcut] hint. Used across the chrome so hovering reveals what a control
/// does and the single key that triggers it.
Widget _withHint(
  Widget child, {
  required String description,
  String? shortcut,
}) {
  return Tooltip(
    tooltip: (context) => TooltipContainer(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(description, style: const TextStyle(fontSize: 11)),
          if (shortcut != null) ...[
            const SizedBox(width: 10),
            Opacity(
              opacity: 0.6,
              child: Text(shortcut, style: const TextStyle(fontSize: 11)),
            ),
          ],
        ],
      ),
    ),
    child: child,
  );
}

/// A single, square, hover-aware chrome button. The visual is provided by
/// [builder] so it can host an SVG (with injected colour) or a Material icon.
///
/// [active] paints the one restrained accent; [danger] tints destructive
/// actions. Everything else stays neutral — this is the building block that
/// keeps the whole interface monotone.
class _ChromeButton extends StatefulWidget {
  const _ChromeButton({
    required this.builder,
    required this.onTap,
    this.active = false,
    this.danger = false,
    this.enabled = true,
    this.size = 36,
    this.description,
    this.shortcut,
  });

  final Widget Function(Color color) builder;
  final VoidCallback? onTap;
  final bool active;
  final bool danger;
  final bool enabled;
  final double size;
  final String? description;
  final String? shortcut;

  @override
  State<_ChromeButton> createState() => _ChromeButtonState();
}

class _ChromeButtonState extends State<_ChromeButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);

    Color fg;
    if (!widget.enabled) {
      fg = t.faint;
    } else if (widget.active) {
      fg = t.accentForeground;
    } else if (widget.danger) {
      fg = _hover ? t.danger : t.danger.withValues(alpha: 0.85);
    } else {
      fg = _hover ? t.foreground : t.foreground.withValues(alpha: 0.82);
    }

    Color bg;
    if (widget.active) {
      bg = t.accent;
    } else if (_hover && widget.enabled) {
      bg = widget.danger ? t.danger.withValues(alpha: 0.12) : t.surfaceHover;
    } else {
      bg = const Color(0x00000000);
    }

    Widget core = AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(t.itemRadius),
      ),
      child: widget.builder(fg),
    );

    if (widget.enabled) {
      core = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: core,
        ),
      );
    }

    if (widget.description != null) {
      core = _withHint(core,
          description: widget.description!, shortcut: widget.shortcut);
    }
    return core;
  }
}

/// A floating card that hosts a cluster of chrome controls.
class _ChromeCard extends StatelessWidget {
  const _ChromeCard({required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return Container(
      padding: padding ?? const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.radius),
        border: Border.all(color: t.border),
        boxShadow: t.shadow,
      ),
      child: child,
    );
  }
}

/// A thin vertical hairline used to group controls inside a card.
class _VRule extends StatelessWidget {
  const _VRule();
  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      color: t.border,
    );
  }
}

// ===========================================================================
//  Top-centre tool island
// ===========================================================================

/// The primary tool palette: a single calm island holding only the everyday
/// creation tools. Less-used shapes live behind a "More" overflow and the
/// style defaults behind a "Style" popover, so the canvas stays uncluttered.
///
/// While a node's text is being edited inline, the island is replaced by a
/// focused rich-text format bar.
class FlowDrawToolbar extends StatelessWidget {
  final List<String> svgs;

  /// When non-null, only these tools are shown.
  final Set<EditorTool>? allowedTools;

  const FlowDrawToolbar({super.key, required this.svgs, this.allowedTools});

  bool _isAllowed(EditorTool tool) =>
      allowedTools == null || allowedTools!.contains(tool);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RichTextEditingController?>(
      valueListenable: activeTextEditing,
      builder: (context, activeController, _) {
        if (activeController != null) {
          return _ChromeCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: _InlineTextBar(controller: activeController),
          );
        }
        return _buildIsland(context);
      },
    );
  }

  Widget _buildIsland(BuildContext context) {
    final toolBloc = context.watch<ToolBloc>();
    final active = toolBloc.state.activeTool;

    void select(EditorTool tool) => toolBloc.add(ToolSelected(tool));

    Widget tool(EditorTool t, String label, String key,
        Widget Function(Color) icon) {
      return _ChromeButton(
        active: active == t,
        description: label,
        shortcut: key,
        onTap: () => select(t),
        builder: icon,
      );
    }

    final core = <Widget>[
      if (_isAllowed(EditorTool.arrow))
        tool(EditorTool.arrow, 'Select / move', 'V',
            (c) => Assets.icons.arrow.svg(width: 17, color: c)),
      if (_isAllowed(EditorTool.square))
        tool(EditorTool.square, 'Rectangle', 'R',
            (c) => Assets.icons.square.svg(width: 16, color: c)),
      if (_isAllowed(EditorTool.circle))
        tool(EditorTool.circle, 'Ellipse', 'O',
            (c) => Assets.icons.circle.svg(width: 16, color: c)),
      if (_isAllowed(EditorTool.diamond))
        tool(EditorTool.diamond, 'Diamond', 'G',
            (c) => Icon(Icons.diamond_outlined, size: 16, color: c)),
      if (_isAllowed(EditorTool.arrowTopRight))
        tool(EditorTool.arrowTopRight, 'Arrow (connects shapes)', 'A',
            (c) => Assets.icons.arrowTopRight.svg(width: 16, color: c)),
      if (_isAllowed(EditorTool.line))
        tool(EditorTool.line, 'Line', 'L',
            (c) => Assets.icons.line.svg(width: 16, color: c)),
      if (_isAllowed(EditorTool.pencil))
        tool(EditorTool.pencil, 'Pencil (freehand)', 'D',
            (c) => Assets.icons.pencil.svg(width: 16, color: c)),
      if (_isAllowed(EditorTool.text))
        tool(EditorTool.text, 'Text', 'T',
            (c) => Assets.icons.text.svg(width: 16, color: c)),
    ];

    // Overflow shapes — kept out of the everyday flow.
    final overflow = <_OverflowTool>[
      if (_isAllowed(EditorTool.parallelogram))
        _OverflowTool(EditorTool.parallelogram, 'Parallelogram', 'P',
            (c) => Transform.rotate(
                angle: 1.5708,
                child: Icon(Icons.change_history, size: 16, color: c))),
      if (_isAllowed(EditorTool.forkJoin))
        _OverflowTool(EditorTool.forkJoin, 'Fork / join bar', 'J',
            (c) => Icon(Icons.horizontal_rule, size: 18, color: c)),
      if (_isAllowed(EditorTool.figure))
        _OverflowTool(EditorTool.figure, 'Figure / SVG shape', 'F',
            (c) => Assets.icons.figure.svg(width: 16, color: c)),
      if (_isAllowed(EditorTool.comment))
        _OverflowTool(EditorTool.comment, 'Comment pin', 'C',
            (c) => Assets.icons.comment.svg(width: 16, color: c)),
    ];

    return _ChromeCard(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...core,
          if (overflow.isNotEmpty) ...[
            const _VRule(),
            _MoreToolsButton(
              tools: overflow,
              active: active,
              svgs: svgs,
              onSelect: select,
            ),
          ],
          const _VRule(),
          _StyleDefaultsButton(),
        ],
      ),
    );
  }
}

class _OverflowTool {
  const _OverflowTool(this.tool, this.label, this.key, this.icon);
  final EditorTool tool;
  final String label;
  final String key;
  final Widget Function(Color) icon;
}

/// "More" overflow: the remaining shape tools plus the icon library, in a
/// labelled popover list.
class _MoreToolsButton extends StatelessWidget {
  const _MoreToolsButton({
    required this.tools,
    required this.active,
    required this.svgs,
    required this.onSelect,
  });

  final List<_OverflowTool> tools;
  final EditorTool active;
  final List<String> svgs;
  final ValueChanged<EditorTool> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    final isActive = tools.any((o) => o.tool == active);
    return _ChromeButton(
      active: isActive,
      description: 'More shapes & icons',
      onTap: () {
        showPopover(
          context: context,
          alignment: Alignment.topCenter,
          builder: (popoverContext) {
            return ModalContainer(
              child: SizedBox(
                width: 220,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final o in tools)
                      _PopoverRow(
                        icon: o.icon(t.foreground),
                        label: o.label,
                        trailing: o.key,
                        selected: o.tool == active,
                        onTap: () {
                          onSelect(o.tool);
                          closeOverlay(popoverContext);
                        },
                      ),
                    _PopoverDivider(),
                    _PopoverRow(
                      icon: Assets.icons.add.svg(width: 16, color: t.foreground),
                      label: 'Icon library…',
                      trailing: '/',
                      onTap: () {
                        closeOverlay(popoverContext);
                        _showAddPopover(context, svgs);
                      },
                    ),
                  ],
                ),
              ),
            ).withPadding(top: 8);
          },
        );
      },
      builder: (c) => Icon(Icons.more_horiz, size: 18, color: c),
    );
  }
}

/// Sets the style defaults applied to *new* shapes: default line style and the
/// global default font. Keeps these power-user knobs available without
/// cluttering the canvas.
class _StyleDefaultsButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _ChromeButton(
      description: 'Style defaults',
      onTap: () {
        final toolBloc = context.read<ToolBloc>();
        final canvasBloc = context.read<CanvasBloc>();
        showPopover(
          context: context,
          alignment: Alignment.topCenter,
          builder: (popoverContext) {
            final t = FlowDrawSkin.of(context);
            return ModalContainer(
              child: SizedBox(
                width: 230,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 2, bottom: 4),
                        child: Text('Default line',
                            style:
                                TextStyle(fontSize: 11, color: t.muted)),
                      ),
                      for (final style in LineStyle.values)
                        _PopoverRow(
                          icon: SizedBox(
                            width: 34,
                            height: 14,
                            child: CustomPaint(
                              painter: _LineStylePreviewPainter(
                                  style, t.foreground),
                            ),
                          ),
                          label: _lineStyleLabel(style),
                          selected: toolBloc.state.lineStyle == style,
                          onTap: () {
                            toolBloc.add(LineStyleSelected(style));
                            closeOverlay(popoverContext);
                          },
                        ),
                      _PopoverDivider(),
                      Padding(
                        padding: const EdgeInsets.only(left: 2, bottom: 4),
                        child: Text('Default font',
                            style:
                                TextStyle(fontSize: 11, color: t.muted)),
                      ),
                      _FontControls(
                        editingSelection: false,
                        customized: false,
                        family: canvasBloc.state.defaultFontFamily,
                        size: canvasBloc.state.defaultFontSize,
                        globalFamily: canvasBloc.state.defaultFontFamily,
                        globalSize: canvasBloc.state.defaultFontSize,
                        compact: true,
                        onChanged: (f, s) {
                          canvasBloc.add(
                              GlobalFontChanged(fontFamily: f, fontSize: s));
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ).withPadding(top: 8);
          },
        );
      },
      builder: (c) => Icon(Icons.tune, size: 17, color: c),
    );
  }
}

String _lineStyleLabel(LineStyle style) => switch (style) {
      LineStyle.solid => 'Solid',
      LineStyle.dashed => 'Dashed',
      LineStyle.dotted => 'Dotted',
      LineStyle.rough => 'Rough',
    };

/// The rich-text format bar shown in place of the tool island while a node's
/// text is being edited inline. Targets the live caret selection so
/// family / size / bold / italic / colour apply per-character.
class _InlineTextBar extends StatelessWidget {
  const _InlineTextBar({required this.controller});
  final RichTextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final sel = controller.selectionStyle();
        final family = sel.fontFamily ?? '—';
        final sizeLabel =
            sel.fontSize != null ? sel.fontSize!.round().toString() : '—';
        final bold = sel.bold ?? false;
        final italic = sel.italic ?? false;

        void openFontPopover() {
          showPopover(
            context: context,
            alignment: Alignment.topCenter,
            builder: (popoverContext) {
              return ModalContainer(
                child: SizedBox(
                  width: 240,
                  child: _FontControls(
                    editingSelection: true,
                    customized: false,
                    family: sel.fontFamily ?? kEditorDefaultFontFamily,
                    size: sel.fontSize ?? kEditorDefaultFontSize,
                    globalFamily: kEditorDefaultFontFamily,
                    globalSize: kEditorDefaultFontSize,
                    onChanged: (f, s) {
                      controller.applyToSelection(
                        fontFamily: Attr.set(f),
                        fontSize: Attr.set(s),
                      );
                    },
                    richController: controller,
                    selBold: sel.bold,
                    selItalic: sel.italic,
                    selColor: sel.color,
                  ),
                ),
              ).withPadding(top: 8);
            },
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 4),
            Icon(Icons.text_fields, size: 15, color: t.muted),
            const SizedBox(width: 8),
            _ChromeButton(
              size: 32,
              description: 'Font & size',
              onTap: openFontPopover,
              builder: (c) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$family  $sizeLabel',
                      style: TextStyle(fontSize: 12, color: c)),
                  Icon(Icons.expand_more, size: 14, color: c),
                ],
              ),
            ),
            const _VRule(),
            _ChromeButton(
              size: 32,
              active: bold,
              description: 'Bold',
              onTap: () =>
                  controller.applyToSelection(bold: Attr.set(!bold)),
              builder: (c) => Icon(Icons.format_bold, size: 17, color: c),
            ),
            _ChromeButton(
              size: 32,
              active: italic,
              description: 'Italic',
              onTap: () =>
                  controller.applyToSelection(italic: Attr.set(!italic)),
              builder: (c) => Icon(Icons.format_italic, size: 17, color: c),
            ),
          ],
        );
      },
    );
  }
}

// ===========================================================================
//  Top-left menu bar — file, history & power tools
// ===========================================================================

/// The corner command surface: a tidy ⋯-style menu that gathers every power
/// tool (auto-layout, swap, lay-on-path, Mermaid, text-to-diagram, export)
/// out of the main flow, flanked by always-available undo / redo.
class FlowDrawMenuBar extends StatelessWidget {
  const FlowDrawMenuBar({super.key, this.onShowShortcuts});

  /// Invoked when the user picks "Keyboard shortcuts" from the menu.
  final VoidCallback? onShowShortcuts;

  @override
  Widget build(BuildContext context) {
    return _ChromeCard(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Builder(builder: (btnContext) {
            return _ChromeButton(
              description: 'Menu',
              onTap: () => _openMenu(btnContext),
              builder: (c) => Icon(Icons.menu, size: 18, color: c),
            );
          }),
          const _VRule(),
          _ChromeButton(
            description: 'Undo',
            shortcut: '$_kCmdKey Z',
            onTap: () => context.read<CanvasBloc>().add(UndoRequested()),
            builder: (c) => Icon(Icons.undo, size: 18, color: c),
          ),
          _ChromeButton(
            description: 'Redo',
            shortcut: '⇧$_kCmdKey Z',
            onTap: () => context.read<CanvasBloc>().add(RedoRequested()),
            builder: (c) => Icon(Icons.redo, size: 18, color: c),
          ),
        ],
      ),
    );
  }

  void _openMenu(BuildContext anchorContext) {
    final canvasBloc = anchorContext.read<CanvasBloc>();
    final selectionBloc = anchorContext.read<SelectionBloc>();

    showPopover(
      context: anchorContext,
      alignment: Alignment.topCenter,
      builder: (popoverContext) {
        final t = FlowDrawSkin.of(anchorContext);
        return ModalContainer(
          child: SizedBox(
            width: 260,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PopoverRow(
                  icon: Icon(Icons.note_add_outlined, size: 16, color: t.foreground),
                  label: 'New diagram',
                  onTap: () {
                    canvasBloc.add(NewProjectCreated());
                    closeOverlay(popoverContext);
                  },
                ),
                _PopoverDivider(),
                _PopoverSectionLabel('Arrange'),
                _PopoverRow(
                  icon: Icon(Icons.auto_awesome_mosaic, size: 16, color: t.foreground),
                  label: 'Tidy — reduce crossings',
                  trailing: '⇧$_kCmdKey L',
                  onTap: () {
                    canvasBloc.add(const AutoLayoutRequested());
                    closeOverlay(popoverContext);
                  },
                ),
                _PopoverRow(
                  icon: Icon(Icons.timeline, size: 16, color: t.foreground),
                  label: 'Lay along guide',
                  trailing: '⇧$_kCmdKey U',
                  onTap: () {
                    canvasBloc.add(const LayoutAlongGuideRequested());
                    closeOverlay(popoverContext);
                  },
                ),
                _PopoverRow(
                  icon: Icon(Icons.swap_horiz, size: 16, color: t.foreground),
                  label: 'Swap positions',
                  trailing: '⇧$_kCmdKey S',
                  onTap: () {
                    canvasBloc.add(const SwapRequested());
                    closeOverlay(popoverContext);
                  },
                ),
                _PopoverRow(
                  icon: Icon(Icons.fit_screen, size: 16, color: t.foreground),
                  label: 'Fit shapes to content',
                  onTap: () {
                    canvasBloc.add(NodesFittedToContent(
                      selectionBloc.state.selectedDrawingObjectIds,
                      margin: kDefaultFitMargin,
                    ));
                    closeOverlay(popoverContext);
                  },
                ),
                _PopoverDivider(),
                _PopoverSectionLabel('Generate & exchange'),
                _PopoverRow(
                  icon: Icon(Icons.auto_awesome, size: 16, color: t.foreground),
                  label: 'Text to diagram…',
                  onTap: () {
                    closeOverlay(popoverContext);
                    showPromptToWorkflowDialog(anchorContext, canvasBloc);
                  },
                ),
                _PopoverRow(
                  icon: Icon(Icons.account_tree_outlined, size: 16, color: t.foreground),
                  label: 'Mermaid import / export…',
                  onTap: () {
                    closeOverlay(popoverContext);
                    _openMermaid(anchorContext, canvasBloc, selectionBloc);
                  },
                ),
                _PopoverRow(
                  icon: Icon(Icons.image_outlined, size: 16, color: t.foreground),
                  label: 'Export as SVG',
                  onTap: () {
                    closeOverlay(popoverContext);
                    _exportSvg(canvasBloc);
                  },
                ),
                _PopoverDivider(),
                _PopoverRow(
                  icon: Icon(Icons.keyboard_outlined, size: 16, color: t.foreground),
                  label: 'Keyboard shortcuts',
                  trailing: '?',
                  onTap: () {
                    closeOverlay(popoverContext);
                    onShowShortcuts?.call();
                  },
                ),
              ],
            ),
          ),
        ).withPadding(top: 8);
      },
    );
  }
}

void _openMermaid(
  BuildContext anchorContext,
  CanvasBloc canvasBloc,
  SelectionBloc selectionBloc,
) {
  showPopover(
    context: anchorContext,
    alignment: Alignment.topCenter,
    builder: (popoverContext) {
      return ModalContainer(
        child: SizedBox(
          width: 380,
          child: _MermaidPopoverContent(
            popoverContext: popoverContext,
            canvasBloc: canvasBloc,
            selectionBloc: selectionBloc,
          ),
        ),
      ).withPadding(top: 8);
    },
  );
}

Future<void> _exportSvg(CanvasBloc canvasBloc) async {
  final svg = SvgExporter.export(
    canvasBloc.state.drawingObjects,
    defaultFontFamily: canvasBloc.state.defaultFontFamily,
    defaultFontSize: canvasBloc.state.defaultFontSize,
  );
  if (svg.isEmpty) {
    showNodeEditorSnackbar('Nothing to export', SnackbarType.error);
    return;
  }
  try {
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/fldraw_export.svg');
    await file.writeAsString(svg);
    if (Platform.isMacOS) {
      await Process.run('open', [file.path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [file.path]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', file.path]);
    }
    showNodeEditorSnackbar('SVG opened in viewer', SnackbarType.success);
  } catch (e) {
    showNodeEditorSnackbar('Failed to open SVG: $e', SnackbarType.error);
  }
}

// ===========================================================================
//  Bottom-left canvas controls — grid & zoom
// ===========================================================================

/// The quiet corner cluster that drawing apps park view controls in: grid
/// toggle and a zoom stepper whose percentage doubles as "reset to 100%".
class FlowDrawCanvasControls extends StatelessWidget {
  const FlowDrawCanvasControls({super.key});

  static const double _minZoom = 0.1;
  static const double _maxZoom = 8.0;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CanvasBloc, CanvasState>(
      builder: (context, state) {
        final t = FlowDrawSkin.of(context);
        final bloc = context.read<CanvasBloc>();
        final zoom = state.viewportZoom;

        void setZoom(double z) =>
            bloc.add(CanvasZoomed(z.clamp(_minZoom, _maxZoom).toDouble()));

        return _ChromeCard(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ChromeButton(
                size: 32,
                active: state.showGrid,
                description: 'Alignment grid',
                shortcut: '$_kCmdKey G',
                onTap: () => bloc.add(const GridToggled()),
                builder: (c) => Icon(Icons.grid_4x4, size: 16, color: c),
              ),
              const _VRule(),
              _ChromeButton(
                size: 32,
                description: 'Zoom out',
                onTap: () => setZoom(zoom / 1.2),
                builder: (c) => Icon(Icons.remove, size: 16, color: c),
              ),
              _withHint(
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setZoom(1.0),
                    child: SizedBox(
                      width: 50,
                      child: Text(
                        '${(zoom * 100).round()}%',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: t.foreground,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
                description: 'Reset to 100%',
              ),
              _ChromeButton(
                size: 32,
                description: 'Zoom in',
                onTap: () => setZoom(zoom * 1.2),
                builder: (c) => Icon(Icons.add, size: 16, color: c),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ===========================================================================
//  Popover row primitives (shared by every dropdown above)
// ===========================================================================

class _PopoverRow extends StatefulWidget {
  const _PopoverRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.selected = false,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final String? trailing;
  final bool selected;

  @override
  State<_PopoverRow> createState() => _PopoverRowState();
}

class _PopoverRowState extends State<_PopoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: _hover ? t.surfaceHover : const Color(0x00000000),
            borderRadius: BorderRadius.circular(t.itemRadius),
          ),
          child: Row(
            children: [
              SizedBox(width: 34, child: Center(child: widget.icon)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: t.foreground,
                    fontWeight:
                        widget.selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (widget.selected)
                Icon(Icons.check, size: 14, color: t.accent)
              else if (widget.trailing != null)
                Text(widget.trailing!,
                    style: TextStyle(fontSize: 11, color: t.faint)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PopoverDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: t.border,
    );
  }
}

class _PopoverSectionLabel extends StatelessWidget {
  const _PopoverSectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 2, bottom: 4),
      child: Text(text,
          style: TextStyle(
              fontSize: 10,
              color: t.faint,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600)),
    );
  }
}

// ===========================================================================
//  Icon library picker
// ===========================================================================

void _showAddPopover(BuildContext context, List<String> svgs) {
  final canvasBloc = context.read<CanvasBloc>();
  List<String> filteredAssets = svgs;

  showPopover(
    context: context,
    alignment: Alignment.topCenter,
    builder: (context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return ModalContainer(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      placeholder: const Text('Search 2500+ icons…'),
                      autofocus: true,
                      onChanged: (value) {
                        setState(() {
                          filteredAssets = svgs
                              .where((e) => e
                                  .split('/')
                                  .last
                                  .split('.')
                                  .first
                                  .toLowerCase()
                                  .contains(value.toLowerCase()))
                              .toList();
                        });
                      },
                    ),
                    const Gap(16),
                    Expanded(
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: filteredAssets.length,
                        itemBuilder: (context, index) => IconButton.outline(
                          onPressed: () {
                            closeOverlay(context, filteredAssets.elementAt(index));
                          },
                          icon: SvgPicture.asset(filteredAssets[index]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ).withPadding(top: 16);
        },
      );
    },
  ).future.then((value) async {
    if (value != null && value is String) {
      final String svgString = await rootBundle.loadString(value);
      final pictureInfo = await vg.loadPicture(SvgStringLoader(svgString), null);
      final Size svgSize = pictureInfo.size;

      final canvasState = canvasBloc.state;
      final editorBounds = getEditorBoundsInScreen(kNodeEditorWidgetKey);
      final centerOfScreenWorldPos = screenToWorld(
            editorBounds?.center ?? Offset.zero,
            canvasState.viewportOffset,
            canvasState.viewportZoom,
          ) ??
          Offset.zero;

      final initialRect = Rect.fromCenter(
        center: centerOfScreenWorldPos,
        width: svgSize.width.isFinite ? svgSize.width : 100.0,
        height: svgSize.height.isFinite ? svgSize.height : 100.0,
      );

      final newObject = SvgObject(
        id: const Uuid().v4(),
        rect: initialRect,
        assetPath: value,
        pictureInfo: pictureInfo,
      );

      canvasBloc.add(DrawingObjectAdded(newObject));
    }
  });
}

// ===========================================================================
//  Line-style preview painter
// ===========================================================================

class _LineStylePreviewPainter extends CustomPainter {
  final LineStyle style;
  final Color color;

  _LineStylePreviewPainter(this.style, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final y = size.height / 2;
    final path = Path()
      ..moveTo(0, y)
      ..lineTo(size.width, y);

    switch (style) {
      case LineStyle.solid:
        canvas.drawPath(path, paint);
        break;
      case LineStyle.dashed:
        const dashWidth = 5.0;
        const dashSpace = 3.0;
        double x = 0;
        while (x < size.width) {
          final end = min(x + dashWidth, size.width);
          canvas.drawLine(Offset(x, y), Offset(end, y), paint);
          x = end + dashSpace;
        }
        break;
      case LineStyle.dotted:
        const spacing = 4.0;
        const radius = 1.0;
        final dotPaint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        double x = 0;
        while (x < size.width) {
          canvas.drawCircle(Offset(x, y), radius, dotPaint);
          x += spacing;
        }
        break;
      case LineStyle.rough:
        final rng = Random(42);
        const step = 3.0;
        final points = <Offset>[];
        double x = 0;
        while (x < size.width) {
          final offset = (rng.nextDouble() - 0.5) * 0.6;
          points.add(Offset(x, y + offset));
          x += step;
        }
        points.add(Offset(size.width, y));
        if (points.length >= 2) {
          final roughPath = Path()..moveTo(points[0].dx, points[0].dy);
          for (int i = 0; i < points.length - 1; i++) {
            final p0 = points[i];
            final p1 = points[i + 1];
            roughPath.quadraticBezierTo(
                p0.dx, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
          }
          roughPath.lineTo(points.last.dx, points.last.dy);
          canvas.drawPath(roughPath, paint);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(_LineStylePreviewPainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.color != color;
}

// ===========================================================================
//  Font controls (reused by the style-defaults popover and the inline bar)
// ===========================================================================

/// A compact toggle button for bold/italic in the inline format bar.
class _FormatToggle extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _FormatToggle(
      {required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: active ? t.accent : const Color(0x00000000),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon,
            size: 16, color: active ? t.accentForeground : t.foreground),
      ),
    );
  }
}

/// Reusable family-picker + size-stepper. [onChanged] reports the full desired
/// (family, size) on every interaction.
class _FontControls extends StatefulWidget {
  final String family;
  final double size;
  final void Function(String family, double size) onChanged;
  final String globalFamily;
  final double globalSize;
  final bool editingSelection;
  final bool customized;
  final VoidCallback? onReset;

  /// When non-null, the popover edits live rich text.
  final RichTextEditingController? richController;
  final bool? selBold;
  final bool? selItalic;
  final int? selColor;

  /// Tightens spacing + drops the header for use inside the style-defaults menu.
  final bool compact;

  const _FontControls({
    required this.family,
    required this.size,
    required this.onChanged,
    required this.globalFamily,
    required this.globalSize,
    this.editingSelection = false,
    this.customized = false,
    this.onReset,
    this.richController,
    this.selBold,
    this.selItalic,
    this.selColor,
    this.compact = false,
  });

  @override
  State<_FontControls> createState() => _FontControlsState();
}

class _FontControlsState extends State<_FontControls> {
  late String _family = widget.family;
  late double _size = widget.size;

  static const double _minSize = 6;
  static const double _maxSize = 96;

  void _emit() => widget.onChanged(_family, _size);

  double _presetSize(TextStylePreset p) => p.sizeFor(widget.globalSize);

  bool _isActivePreset(TextStylePreset preset) =>
      _family == widget.globalFamily &&
      (_presetSize(preset) - _size).abs() < 0.5;

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 440),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.compact) ...[
              Text(
                widget.editingSelection ? 'Font (selected)' : 'Font (all)',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const Gap(8),
            ],
            Text('Text style', style: TextStyle(fontSize: 11, color: t.muted)),
            const Gap(2),
            for (final p in kTextStylePresets)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    _family = widget.globalFamily;
                    _size = _presetSize(p).clamp(_minSize, _maxSize).toDouble();
                  });
                  _emit();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        _isActivePreset(p) ? Icons.check : Icons.text_fields,
                        size: 14,
                        color: _isActivePreset(p) ? t.accent : t.faint,
                      ),
                      const Gap(8),
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
              ),
            const Gap(8),
            Text('Font', style: TextStyle(fontSize: 11, color: t.muted)),
            const Gap(2),
            for (final family in kEditorFontFamilies)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() => _family = family);
                  _emit();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        family == _family
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 16,
                        color: family == _family ? t.accent : t.muted,
                      ),
                      const Gap(8),
                      Text(family,
                          style: TextStyle(
                              fontSize: 13,
                              fontFamily: family,
                              color: t.foreground)),
                    ],
                  ),
                ),
              ),
            const Gap(8),
            Row(
              children: [
                Text('Size', style: TextStyle(fontSize: 12, color: t.foreground)),
                const Spacer(),
                _StepButton(
                  icon: Icons.remove,
                  onTap: () {
                    setState(
                        () => _size = (_size - 1).clamp(_minSize, _maxSize).toDouble());
                    _emit();
                  },
                ),
                SizedBox(
                  width: 36,
                  child: Text('${_size.round()}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: t.foreground)),
                ),
                _StepButton(
                  icon: Icons.add,
                  onTap: () {
                    setState(
                        () => _size = (_size + 1).clamp(_minSize, _maxSize).toDouble());
                    _emit();
                  },
                ),
              ],
            ),
            if (widget.richController != null) ..._richFormatRows(t),
            if (widget.editingSelection &&
                widget.customized &&
                widget.onReset != null) ...[
              const Gap(8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onReset,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.restart_alt, size: 16, color: t.foreground),
                      const Gap(8),
                      Text('Reset to default',
                          style:
                              TextStyle(fontSize: 13, color: t.foreground)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static const List<Color> _textColors = [
    Colors.white,
    Colors.black,
    Color(0xFFE53935),
    Color(0xFFFB8C00),
    Color(0xFFFDD835),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
  ];

  List<Widget> _richFormatRows(FlowDrawTokens t) {
    final c = widget.richController!;
    final bold = widget.selBold ?? false;
    final italic = widget.selItalic ?? false;
    return [
      const Gap(12),
      Text('Format',
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: t.foreground)),
      const Gap(8),
      Row(
        children: [
          _FormatToggle(
            icon: Icons.format_bold,
            active: bold,
            onTap: () => c.applyToSelection(bold: Attr.set(!bold)),
          ),
          const Gap(4),
          _FormatToggle(
            icon: Icons.format_italic,
            active: italic,
            onTap: () => c.applyToSelection(italic: Attr.set(!italic)),
          ),
        ],
      ),
      const Gap(10),
      Text('Colour', style: TextStyle(fontSize: 12, color: t.foreground)),
      const Gap(6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final color in _textColors)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => c.applyToSelection(color: Attr.set(color.value)),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.selColor == color.value ? t.accent : t.border,
                    width: widget.selColor == color.value ? 2 : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    ];
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
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

// ===========================================================================
//  Mermaid import / export popover
// ===========================================================================

class _MermaidPopoverContent extends StatefulWidget {
  final BuildContext popoverContext;
  final CanvasBloc canvasBloc;
  final SelectionBloc selectionBloc;

  const _MermaidPopoverContent({
    required this.popoverContext,
    required this.canvasBloc,
    required this.selectionBloc,
  });

  @override
  State<_MermaidPopoverContent> createState() => _MermaidPopoverContentState();
}

class _MermaidPopoverContentState extends State<_MermaidPopoverContent> {
  bool _showExport = false;
  final _importController = TextEditingController();
  final _exportController = TextEditingController();

  @override
  void dispose() {
    _importController.dispose();
    _exportController.dispose();
    super.dispose();
  }

  void _handleExport() {
    final selectedIds = widget.selectionBloc.state.selectedDrawingObjectIds;
    final mermaid = MermaidExporter.export(
      widget.canvasBloc.state.drawingObjects,
      selectedIds: selectedIds.isNotEmpty ? selectedIds : null,
    );
    setState(() {
      _exportController.text = mermaid;
      _showExport = true;
    });
  }

  void _handleCopyExport() {
    Clipboard.setData(ClipboardData(text: _exportController.text));
    closeOverlay(widget.popoverContext);
    showNodeEditorSnackbar('Mermaid copied to clipboard', SnackbarType.success);
  }

  void _handleImport() {
    final text = _importController.text.trim();
    if (text.isEmpty) return;
    try {
      final projectData = MermaidImporter.import(text);
      widget.canvasBloc.add(ProjectLoaded(projectData));
      closeOverlay(widget.popoverContext);
      showNodeEditorSnackbar('Mermaid diagram imported', SnackbarType.success);
    } catch (e) {
      showNodeEditorSnackbar('Failed to import: $e', SnackbarType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = FlowDrawSkin.of(context);
    if (_showExport) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GhostButton(
                density: ButtonDensity.compact,
                onPressed: () => setState(() => _showExport = false),
                child: const Icon(Icons.arrow_back, size: 14),
              ),
              const Gap(8),
              const Text('Export as Mermaid',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const Gap(8),
          TextField(
            controller: _exportController,
            maxLines: 8,
            readOnly: true,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
          const Gap(8),
          PrimaryButton(
            density: ButtonDensity.compact,
            onPressed: _handleCopyExport,
            child: const Text('Copy to clipboard'),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Paste Mermaid diagram',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const Gap(4),
        Text('Supports flowchart (graph) syntax',
            style: TextStyle(fontSize: 11, color: t.muted)),
        const Gap(8),
        TextField(
          key: const ValueKey('mermaid_import_field'),
          controller: _importController,
          placeholder: const Text('graph TD\n  A[Start] --> B[End]'),
          maxLines: 8,
          autofocus: true,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
        const Gap(8),
        PrimaryButton(
          density: ButtonDensity.compact,
          onPressed: _handleImport,
          child: const Text('Render diagram'),
        ),
        const Gap(4),
        GhostButton(
          density: ButtonDensity.compact,
          onPressed: _handleExport,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.upload, size: 14),
              Gap(6),
              Text('Export current diagram', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
