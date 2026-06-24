import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nodeline/nodeline.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_fonts/system_fonts.dart';

/// File extension for Beziera documents (a JSON project file).
const String _kFileExtension = 'beziera';
const String _kRecentFilesPrefsKey = 'beziera.recentFiles';
const int _kMaxRecentFiles = 10;

/// Autosave: the working document is mirrored to disk on every change so an
/// app restart (or crash) never loses unsaved work — it's restored on launch.
/// Only an explicit New discards it (with a warning).
const String _kAutosaveFileName = 'autosave.beziera';

/// Pref keys holding the autosaved doc's associated file path (so the title
/// restores) and whether it had unsaved changes vs its on-disk file.
const String _kAutosavePathPrefsKey = 'beziera.autosave.filePath';
const String _kAutosaveDirtyPrefsKey = 'beziera.autosave.dirty';

/// Debounce before writing the autosave after a change — long enough to coalesce
/// a burst of edits, short enough that little is lost on a hard crash.
const Duration _kAutosaveDebounce = Duration(milliseconds: 600);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Make every installed system font selectable in the editor's font pickers.
  // Listing is cheap; the actual font glyphs are loaded lazily when picked.
  await _loadSystemFontNames();
  runApp(const BezieraApp());
}

/// Enumerates installed system fonts and registers their family names with the
/// editor so they appear in the font pickers. Falls back silently to the
/// built-in generic families if enumeration fails on this platform.
Future<void> _loadSystemFontNames() async {
  try {
    final names = SystemFonts().getFontList();
    if (names.isNotEmpty) {
      names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      setEditorFontFamilies(names);
    }
  } catch (e) {
    debugPrint('Beziera: could not enumerate system fonts: $e');
  }
}

class BezieraApp extends StatelessWidget {
  const BezieraApp({super.key});

  @override
  Widget build(BuildContext context) {
    // A bare MaterialApp provides Directionality, MediaQuery, and the
    // ambient context PlatformMenuBar and dialogs need. The nodeline `FlowDraw`
    // widget supplies its own shadcn theming inside.
    return const MaterialApp(
      title: 'Beziera',
      debugShowCheckedModeBanner: false,
      home: BezieraHome(),
    );
  }
}

class BezieraHome extends StatefulWidget {
  const BezieraHome({super.key});

  @override
  State<BezieraHome> createState() => _BezieraHomeState();
}

class _BezieraHomeState extends State<BezieraHome> {
  FlowDrawController? _controller;
  bool _showShortcuts = false;

  /// Absolute path of the document currently open, or null for an untitled doc.
  String? _filePath;

  /// True when the canvas has unsaved changes since the last save/open/new.
  bool _dirty = false;

  /// Most-recently-opened files, newest first.
  List<String> _recentFiles = <String>[];

  /// Set while a programmatic document change (new/open) is in flight so the
  /// resulting canvas emission isn't misread as a user edit. The bloc emits
  /// asynchronously, so we clear it on the next microtask after the change.
  bool _suppressDirty = false;

  /// Debounce timer for autosave writes.
  Timer? _autosaveTimer;

  /// True until the first canvas emission settles, so restoring the autosaved
  /// document on launch doesn't immediately re-trigger an autosave write.
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _loadRecentFiles();
    // Load every system font's glyphs in the background so any family the user
    // picks actually renders. Names are already registered synchronously at
    // startup, so the picker is populated immediately; glyphs stream in.
    _loadAllFontGlyphs();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAllFontGlyphs() async {
    try {
      await SystemFonts().loadAllFonts();
    } catch (e) {
      debugPrint('Beziera: background font load failed: $e');
    }
  }

  // --- Recent files persistence ----------------------------------------

  Future<void> _loadRecentFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_kRecentFilesPrefsKey) ?? const [];
    // Drop files that no longer exist on disk.
    final existing = stored.where((path) => File(path).existsSync()).toList();
    if (mounted) setState(() => _recentFiles = existing);
  }

  Future<void> _rememberRecentFile(String path) async {
    final updated = <String>[path, ..._recentFiles.where((f) => f != path)];
    if (updated.length > _kMaxRecentFiles) {
      updated.removeRange(_kMaxRecentFiles, updated.length);
    }
    setState(() => _recentFiles = updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kRecentFilesPrefsKey, updated);
  }

  // --- Autosave ---------------------------------------------------------

  Future<String> _autosavePath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, _kAutosaveFileName);
  }

  /// Schedules a debounced autosave of the current canvas. Called on every
  /// canvas change so unsaved work survives a restart or crash.
  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_kAutosaveDebounce, _writeAutosave);
  }

  Future<void> _writeAutosave() async {
    if (_controller == null) return;
    try {
      final json = await _serialize();
      final path = await _autosavePath();
      await File(path).writeAsString(json);
      final prefs = await SharedPreferences.getInstance();
      if (_filePath != null) {
        await prefs.setString(_kAutosavePathPrefsKey, _filePath!);
      } else {
        await prefs.remove(_kAutosavePathPrefsKey);
      }
      await prefs.setBool(_kAutosaveDirtyPrefsKey, _dirty);
    } catch (e) {
      debugPrint('Beziera: autosave failed: $e');
    }
  }

  /// Restores the autosaved document on launch, if any. Returns true if a
  /// document was restored. Runs after the controller is created.
  Future<bool> _restoreAutosave() async {
    if (_controller == null) return false;
    try {
      final path = await _autosavePath();
      final file = File(path);
      if (!file.existsSync()) return false;
      final contents = await file.readAsString();
      if (contents.trim().isEmpty) return false;
      final data = jsonDecode(contents) as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      final restoredPath = prefs.getString(_kAutosavePathPrefsKey);
      final wasDirty = prefs.getBool(_kAutosaveDirtyPrefsKey) ?? true;

      _restoring = true;
      _suppressDirty = true;
      _controller!.loadProject(data);
      setState(() {
        _filePath = restoredPath;
        _dirty = wasDirty;
      });
      // Release the guards after the load emission settles.
      Future.delayed(const Duration(milliseconds: 80), () {
        _suppressDirty = false;
        _restoring = false;
      });
      return true;
    } catch (e) {
      debugPrint('Beziera: could not restore autosave: $e');
      return false;
    }
  }

  /// Deletes the autosave file and its prefs — used when the user explicitly
  /// discards via New, so the next launch starts blank.
  Future<void> _clearAutosave() async {
    _autosaveTimer?.cancel();
    try {
      final file = File(await _autosavePath());
      if (file.existsSync()) await file.delete();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAutosavePathPrefsKey);
      await prefs.remove(_kAutosaveDirtyPrefsKey);
    } catch (e) {
      debugPrint('Beziera: could not clear autosave: $e');
    }
  }

  // --- Document title --------------------------------------------------

  String get _documentName =>
      _filePath == null ? 'Untitled' : p.basename(_filePath!);

  String get _windowTitle =>
      'Beziera — ${_dirty ? '• ' : ''}$_documentName';

  // --- File actions ----------------------------------------------------

  /// Serializes the current canvas to a JSON string via the controller.
  Future<String> _serialize() {
    final completer = Completer<String>();
    _controller!.saveProject((data) {
      completer.complete(const JsonEncoder.withIndent('  ').convert(data));
    });
    return completer.future;
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_dirty) return true;
    final keep = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: Text(
          'Do you want to save the changes you made to "$_documentName"? '
          'Your changes will be lost if you don\'t save them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Don't Save"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (keep == null) return false; // Cancel
    if (keep) return _save(); // Save first; proceed only if it succeeds.
    return true; // Discard.
  }

  Future<void> _newDocument() async {
    // New is the explicit "throw away" action — warn before discarding the
    // current (autosaved) graph so it isn't lost by accident.
    if (!await _confirmDiscardForNew()) return;
    await _clearAutosave();
    _applyDocumentChange(() {
      _controller!.createNewProject();
      _filePath = null;
    });
  }

  /// Warns that starting a new document discards the current graph. Returns true
  /// to proceed. Offers to Save first if the doc has a file path / unsaved work.
  Future<bool> _confirmDiscardForNew() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start a new document?'),
        content: Text(
          _filePath == null
              ? 'Your current graph "$_documentName" will be discarded. '
                  'This can\'t be undone.'
              : 'Unsaved changes to "$_documentName" will be discarded. '
                  'This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          if (_dirty || _filePath != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Save first…'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (proceed == null) {
      // "Save first…" — save, then proceed only if the save succeeded.
      return _save();
    }
    return proceed;
  }

  Future<void> _open() async {
    if (!await _confirmDiscardIfDirty()) return;
    final typeGroup = XTypeGroup(
      label: 'Beziera document',
      extensions: const [_kFileExtension, 'json'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    await _openPath(file.path);
  }

  Future<void> _openPath(String path) async {
    try {
      final contents = await File(path).readAsString();
      final data = jsonDecode(contents) as Map<String, dynamic>;
      _applyDocumentChange(() {
        _controller!.loadProject(data);
        _filePath = path;
      });
      await _rememberRecentFile(path);
    } catch (e) {
      _showError('Could not open file', '$e');
    }
  }

  /// Saves to the current file, or prompts for a location if untitled.
  /// Returns true if the document was written.
  Future<bool> _save() async {
    if (_filePath == null) return _saveAs();
    return _writeTo(_filePath!);
  }

  Future<bool> _saveAs() async {
    final base = _filePath == null
        ? 'Untitled'
        : p.basenameWithoutExtension(_filePath!);
    final location = await getSaveLocation(
      suggestedName: '$base.$_kFileExtension',
      acceptedTypeGroups: [
        XTypeGroup(
          label: 'Beziera document',
          extensions: const [_kFileExtension],
        ),
      ],
    );
    if (location == null) return false;
    var path = location.path;
    if (p.extension(path).isEmpty) path = '$path.$_kFileExtension';
    return _writeTo(path);
  }

  Future<bool> _writeTo(String path) async {
    try {
      final json = await _serialize();
      await File(path).writeAsString(json);
      setState(() {
        _filePath = path;
        _dirty = false;
      });
      await _rememberRecentFile(path);
      // Refresh the autosave so its associated path + clean state match the
      // explicit save (Save doesn't emit a canvas change to trigger it).
      await _writeAutosave();
      return true;
    } catch (e) {
      _showError('Could not save file', '$e');
      return false;
    }
  }

  void _showError(String title, String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // --- Controller wiring -----------------------------------------------

  void _onControllerCreated(FlowDrawController controller) {
    _controller = controller;
    // Bring back whatever was on the canvas when the app last closed.
    _restoreAutosave();
  }

  void _onCanvasChanged(CanvasState state) {
    // Always mirror the canvas to the autosave file (even for our own
    // load/new and viewport changes) so a restart restores the exact state.
    if (!_restoring) _scheduleAutosave();
    // Ignore emissions caused by our own load/new (not real user edits).
    if (_suppressDirty) return;
    // Any canvas emission after a load/new/save means the user edited; mark
    // dirty. Pure viewport pans/zooms also emit, but treating them as edits is
    // harmless and matches how most drawing apps behave.
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  /// Runs a programmatic document change ([action] loads or clears the canvas),
  /// then marks the document clean once the resulting bloc emission settles —
  /// without it being misread as a user edit.
  void _applyDocumentChange(VoidCallback action) {
    _suppressDirty = true;
    action();
    setState(() => _dirty = false);
    // The bloc emits asynchronously; release the guard after it has flushed.
    Future.delayed(const Duration(milliseconds: 50), () {
      _suppressDirty = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: _buildMenus(),
      child: Title(
        title: _windowTitle,
        color: const Color(0xFF000000),
        child: FlowDraw(
          onControllerCreated: _onControllerCreated,
          onCanvasStateChanged: _onCanvasChanged,
          child: _Editor(
            showShortcuts: _showShortcuts,
            onShowShortcuts: () => setState(() => _showShortcuts = true),
            onCloseShortcuts: () => setState(() => _showShortcuts = false),
            documentName: _documentName,
            dirty: _dirty,
          ),
        ),
      ),
    );
  }

  // --- Native macOS menu bar -------------------------------------------

  List<PlatformMenuItem> _buildMenus() {
    return [
      // The application menu (About / Quit) is supplied by the platform; we
      // declare an empty leading menu so it keeps its standard slot.
      const PlatformMenu(
        label: 'Beziera',
        menus: [
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.servicesSubmenu,
          ),
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.hideOtherApplications,
          ),
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
        ],
      ),
      PlatformMenu(
        label: 'File',
        menus: [
          PlatformMenuItem(
            label: 'New',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyN,
                meta: true),
            onSelected: _newDocument,
          ),
          PlatformMenuItem(
            label: 'Open…',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyO,
                meta: true),
            onSelected: _open,
          ),
          if (_recentFiles.isNotEmpty)
            PlatformMenu(
              label: 'Open Recent',
              menus: [
                for (final path in _recentFiles)
                  PlatformMenuItem(
                    label: p.basename(path),
                    onSelected: () => _openRecent(path),
                  ),
              ],
            ),
          PlatformMenuItem(
            label: 'Save',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyS,
                meta: true),
            onSelected: () => _save(),
          ),
          PlatformMenuItem(
            label: 'Save As…',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyS,
                meta: true, shift: true),
            onSelected: () => _saveAs(),
          ),
        ],
      ),
      PlatformMenu(
        label: 'Edit',
        menus: [
          PlatformMenuItem(
            label: 'Undo',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyZ,
                meta: true),
            onSelected: () => _controller?.undo(),
          ),
          PlatformMenuItem(
            label: 'Redo',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyZ,
                meta: true, shift: true),
            onSelected: () => _controller?.redo(),
          ),
        ],
      ),
      const PlatformMenu(
        label: 'View',
        menus: [
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.toggleFullScreen,
          ),
        ],
      ),
      const PlatformMenu(
        label: 'Window',
        menus: [
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.minimizeWindow,
          ),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.zoomWindow,
          ),
        ],
      ),
    ];
  }

  Future<void> _openRecent(String path) async {
    if (!File(path).existsSync()) {
      _showError('File not found', 'The file no longer exists:\n$path');
      await _loadRecentFiles();
      return;
    }
    if (!await _confirmDiscardIfDirty()) return;
    await _openPath(path);
  }
}

/// A clean, monotone drawing-app shell built on nodeline.
///
/// The canvas fills the screen. Chrome is pushed to the edges so the drawing
/// surface stays the focus:
///   • a top-centre **tool island** for everyday creation tools,
///   • a top-left **menu** that gathers file actions and power tools,
///   • a bottom-left **zoom / grid** cluster,
///   • a top-right **document status** chip showing the open file, and
///   • a contextual selection toolbar (provided by the canvas) that
///     appears only when something is selected.
class _Editor extends StatelessWidget {
  const _Editor({
    required this.showShortcuts,
    required this.onShowShortcuts,
    required this.onCloseShortcuts,
    required this.documentName,
    required this.dirty,
  });

  final bool showShortcuts;
  final VoidCallback onShowShortcuts;
  final VoidCallback onCloseShortcuts;
  final String documentName;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The infinite canvas fills everything.
        const Positioned.fill(
          child: FlowDrawCanvas(),
        ),

        // Top-left: menu (file + power tools) and history.
        Positioned(
          top: 18,
          left: 18,
          child: FlowDrawMenuBar(
            onShowShortcuts: onShowShortcuts,
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

        // Top-right: the open document's name + dirty indicator.
        Positioned(
          top: 18,
          right: 18,
          child: _DocumentChip(name: documentName, dirty: dirty),
        ),

        // Bottom-left: zoom + grid.
        const Positioned(
          left: 18,
          bottom: 18,
          child: FlowDrawCanvasControls(),
        ),

        // Keyboard shortcuts cheat sheet.
        if (showShortcuts)
          Positioned.fill(
            child: ShortcutOverlay(onClose: onCloseShortcuts),
          ),
      ],
    );
  }
}

/// Small read-only chip showing the current document name and a dot when there
/// are unsaved changes.
class _DocumentChip extends StatelessWidget {
  const _DocumentChip({required this.name, required this.dirty});

  final String name;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xF2FFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x14000000)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dirty)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFFEA9D34),
                  shape: BoxShape.circle,
                ),
              ),
            Text(
              name,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF1A1A1A),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
