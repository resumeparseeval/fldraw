/// CLI tool that reads a flow_draw debug JSON file and prints copy-pasteable
/// Dart `RoutingFixture(...)` code for each orthogonal arrow.
///
/// Usage:
///   dart run tool/extract_routing_fixture.dart [path]
///
/// If no path is given, reads ~/Downloads/flow_draw_debug.json.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final home = Platform.environment['HOME'] ?? '';
  final path = args.isNotEmpty
      ? args.first
      : '$home/Downloads/flow_draw_debug.json';

  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $path');
    exit(1);
  }

  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final objects = json['drawingObjects'] as List<dynamic>? ?? [];

  // Build ID → Rect map for all solid objects.
  final rects = <String, _ObjRect>{};
  for (final obj in objects) {
    final map = obj as Map<String, dynamic>;
    final type = map['type'] as String?;
    if (type == null) continue;

    // Skip non-solid objects (arrows, lines, pencil strokes)
    if (const {'arrow', 'line', 'pencil'}.contains(type)) continue;

    final id = map['id'] as String;
    final r = map['rect'] as Map<String, dynamic>?;
    if (r == null) continue;
    rects[id] = _ObjRect(
      id: id,
      type: type,
      rect: _parseRect(r),
    );
  }

  // Process each orthogonal arrow with attachments.
  var index = 0;
  for (final obj in objects) {
    final map = obj as Map<String, dynamic>;
    if (map['type'] != 'arrow') continue;
    if (map['pathType'] != 'orthogonal') continue;

    final startAttachment = map['startAttachment'] as Map<String, dynamic>?;
    final endAttachment = map['endAttachment'] as Map<String, dynamic>?;
    if (startAttachment == null || endAttachment == null) continue;

    final sourceId = startAttachment['objectId'] as String;
    final targetId = endAttachment['objectId'] as String;
    final sourceObj = rects[sourceId];
    final targetObj = rects[targetId];
    if (sourceObj == null || targetObj == null) continue;

    final startRel = _parseOffset(startAttachment['relativePosition'] as List);
    final endRel = _parseOffset(endAttachment['relativePosition'] as List);

    // Collect obstacles: all solid objects except source and target.
    final obstacleRects = rects.values
        .where((o) => o.id != sourceId && o.id != targetId)
        .toList();

    index++;
    final name = 'fixture_$index';

    stdout.writeln("final $name = RoutingFixture(");
    stdout.writeln("  name: '$name',");
    stdout.writeln("  sourceRect: ${_rectLiteral(sourceObj.rect)},");
    stdout.writeln("  targetRect: ${_rectLiteral(targetObj.rect)},");
    stdout.writeln("  startRelPos: ${_offsetLiteral(startRel)},");
    stdout.writeln("  endRelPos: ${_offsetLiteral(endRel)},");
    if (obstacleRects.isNotEmpty) {
      stdout.writeln("  obstacles: [");
      for (final o in obstacleRects) {
        final shortId = o.id.length > 8 ? o.id.substring(0, 8) : o.id;
        stdout.writeln("    ${_rectLiteral(o.rect)}, // ${o.type} $shortId");
      }
      stdout.writeln("  ],");
    }
    stdout.writeln(");");
    stdout.writeln();
  }

  if (index == 0) {
    stderr.writeln('No orthogonal arrows with attachments found in $path');
  } else {
    stderr.writeln('Extracted $index fixture(s).');
  }
}

class _ObjRect {
  final String id;
  final String type;
  final List<double> rect; // [left, top, width, height]
  _ObjRect({required this.id, required this.type, required this.rect});
}

List<double> _parseRect(Map<String, dynamic> r) {
  return [
    (r['left'] as num).toDouble(),
    (r['top'] as num).toDouble(),
    (r['width'] as num).toDouble(),
    (r['height'] as num).toDouble(),
  ];
}

List<double> _parseOffset(List<dynamic> list) {
  return [(list[0] as num).toDouble(), (list[1] as num).toDouble()];
}

String _rectLiteral(List<double> r) {
  return 'Rect.fromLTWH(${r[0]}, ${r[1]}, ${r[2]}, ${r[3]})';
}

String _offsetLiteral(List<double> o) {
  return 'Offset(${o[0]}, ${o[1]})';
}
