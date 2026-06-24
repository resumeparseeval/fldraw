import 'package:flutter/widgets.dart';
import 'package:nodeline/nodeline.dart';

void main() {
  runApp(const NodelineExampleApp());
}

/// A clean, monotone drawing-app shell built on nodeline.
///
/// The canvas fills the screen. Chrome is pushed to the edges so the drawing
/// surface stays the focus:
///   • a top-centre **tool island** for everyday creation tools,
///   • a top-left **menu** that gathers file actions and power tools,
///   • a bottom-left **zoom / grid** cluster,
///   • and a contextual selection toolbar (provided by the canvas) that
///     appears only when something is selected.
class NodelineExampleApp extends StatelessWidget {
  const NodelineExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const FlowDraw(child: _Editor());
  }
}

class _Editor extends StatefulWidget {
  const _Editor();

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  bool _showShortcuts = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The infinite canvas fills everything.
        const Positioned.fill(
          // Pass SVG asset paths to the toolbar to enable the icon-stamp tool.
          child: FlowDrawCanvas(),
        ),

        // Top-left: menu (file + power tools) and history.
        Positioned(
          top: 18,
          left: 18,
          child: FlowDrawMenuBar(
            onShowShortcuts: () => setState(() => _showShortcuts = true),
          ),
        ),

        // Top-centre: the primary tool island.
        const Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: 18),
            child: FlowDrawToolbar(svgs: []),
          ),
        ),

        // Bottom-left: zoom + grid.
        const Positioned(
          left: 18,
          bottom: 18,
          child: FlowDrawCanvasControls(),
        ),

        // Keyboard shortcuts cheat sheet.
        if (_showShortcuts)
          Positioned.fill(
            child: ShortcutOverlay(
              onClose: () => setState(() => _showShortcuts = false),
            ),
          ),
      ],
    );
  }
}
