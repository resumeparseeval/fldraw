/// CLI tool that reads a FlowDraw JSON save file and renders it as SVG.
///
/// Usage:
///   dart run tool/svg_exporter.dart [path] [-o output.svg]
///
/// If no path is given, reads ~/Downloads/flow_draw_debug.json.
/// Output goes to stdout by default (pipeable to a file).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'geometry.dart';
import 'orthogonal_router_standalone.dart';

// -- Theme constants (dark background, white strokes — matches app) ----------

const _bg = '#1a1a1a';
const _stroke = '#e0e0e0';
const _arrowStroke = '#90caf9';
const _lineStroke = '#a5d6a7';
const _pencilStroke = '#ffcc80';
const _figureStroke = '#ce93d8';
const _textColor = '#e0e0e0';
const _labelColor = '#888888';
const _labelFontSize = 10;
const _defaultStrokeWidth = 2;
const _margin = 60.0;
const _cornerRadius = 6.0;
const _arrowHeadSize = 12.0;

// -- Main --------------------------------------------------------------------

void main(List<String> args) {
  final home = Platform.environment['HOME'] ?? '';
  String? inputPath;
  String? outputPath;

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '-o' && i + 1 < args.length) {
      outputPath = args[++i];
    } else if (inputPath == null) {
      inputPath = args[i];
    }
  }
  inputPath ??= '$home/Downloads/flow_draw_debug.json';

  final file = File(inputPath);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $inputPath');
    exit(1);
  }

  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final objects = json['drawingObjects'] as List<dynamic>? ?? [];

  // Build lookup maps.
  final objectsById = <String, Map<String, dynamic>>{};
  final solidRects = <String, Rect>{}; // ID → Rect for solid objects
  for (final obj in objects) {
    final map = obj as Map<String, dynamic>;
    final id = map['id'] as String;
    objectsById[id] = map;
    final type = map['type'] as String?;
    if (const {'rectangle', 'circle', 'figure', 'text', 'svg'}.contains(type)) {
      final r = map['rect'] as Map<String, dynamic>?;
      if (r != null) solidRects[id] = _parseRect(r);
    }
  }

  // Render each object to SVG elements.
  final svgElements = <String>[];
  final allBounds = <Rect>[];

  for (final obj in objects) {
    final map = obj as Map<String, dynamic>;
    final type = map['type'] as String?;
    if (type == null) continue;

    switch (type) {
      case 'rectangle':
        _renderRectangle(map, svgElements, allBounds);
      case 'circle':
        _renderCircle(map, svgElements, allBounds);
      case 'arrow':
        _renderArrow(map, objectsById, solidRects, svgElements, allBounds);
      case 'line':
        _renderLine(map, objectsById, solidRects, svgElements, allBounds);
      case 'pencil_stroke':
        _renderPencilStroke(map, svgElements, allBounds);
      case 'figure':
        _renderFigure(map, svgElements, allBounds);
      case 'text':
        _renderText(map, svgElements, allBounds);
    }
  }

  // Compute viewBox from all rendered bounds.
  if (allBounds.isEmpty) {
    stderr.writeln('No drawable objects found.');
    exit(1);
  }

  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final b in allBounds) {
    minX = math.min(minX, b.left);
    minY = math.min(minY, b.top);
    maxX = math.max(maxX, b.right);
    maxY = math.max(maxY, b.bottom);
  }
  minX -= _margin;
  minY -= _margin;
  maxX += _margin;
  maxY += _margin;
  final vw = maxX - minX;
  final vh = maxY - minY;

  final svg = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg"')
    ..writeln('     viewBox="$minX $minY $vw $vh"')
    ..writeln('     width="${vw.round()}" height="${vh.round()}">')
    ..writeln('  <rect x="$minX" y="$minY" width="$vw" height="$vh" fill="$_bg"/>')
    ..writeln()
    ..writeAll(svgElements, '\n')
    ..writeln()
    ..writeln('</svg>');

  final output = svg.toString();
  if (outputPath != null) {
    File(outputPath).writeAsStringSync(output);
    stderr.writeln('SVG written to $outputPath');
  } else {
    stdout.write(output);
  }
  stderr.writeln(
      'Rendered ${objects.length} objects, viewBox: ${minX.toStringAsFixed(0)},${minY.toStringAsFixed(0)} ${vw.toStringAsFixed(0)}x${vh.toStringAsFixed(0)}');
}

// -- Renderers ---------------------------------------------------------------

void _renderRectangle(
  Map<String, dynamic> map,
  List<String> svg,
  List<Rect> bounds,
) {
  final rect = _parseRect(map['rect'] as Map<String, dynamic>);
  final dashArray = _dashArray(map['lineStyle'] as String?);
  final text = map['text'] as String?;
  final shortId = _shortId(map['id'] as String);

  svg.add('  <!-- rectangle $shortId -->');
  svg.add('  <rect x="${rect.left}" y="${rect.top}" '
      'width="${rect.width}" height="${rect.height}" '
      'rx="$_cornerRadius" ry="$_cornerRadius" '
      'fill="none" stroke="$_stroke" stroke-width="$_defaultStrokeWidth"'
      '${dashArray.isNotEmpty ? ' stroke-dasharray="$dashArray"' : ''}'
      '/>');

  if (text != null && text.isNotEmpty) {
    svg.add('  <text x="${rect.center.dx}" y="${rect.center.dy}" '
        'fill="$_textColor" font-size="14" font-family="sans-serif" '
        'text-anchor="middle" dominant-baseline="central">'
        '${_escapeXml(text)}</text>');
  }

  // Debug label
  svg.add('  <text x="${rect.left + 3}" y="${rect.top - 3}" '
      'fill="$_labelColor" font-size="$_labelFontSize" font-family="monospace">'
      '$shortId</text>');

  bounds.add(rect);
}

void _renderCircle(
  Map<String, dynamic> map,
  List<String> svg,
  List<Rect> bounds,
) {
  final rect = _parseRect(map['rect'] as Map<String, dynamic>);
  final cx = rect.center.dx;
  final cy = rect.center.dy;
  final rx = rect.width / 2;
  final ry = rect.height / 2;
  final dashArray = _dashArray(map['lineStyle'] as String?);
  final text = map['text'] as String?;
  final shortId = _shortId(map['id'] as String);

  svg.add('  <!-- circle $shortId -->');
  svg.add('  <ellipse cx="$cx" cy="$cy" rx="$rx" ry="$ry" '
      'fill="none" stroke="$_stroke" stroke-width="$_defaultStrokeWidth"'
      '${dashArray.isNotEmpty ? ' stroke-dasharray="$dashArray"' : ''}'
      '/>');

  if (text != null && text.isNotEmpty) {
    svg.add('  <text x="$cx" y="$cy" '
        'fill="$_textColor" font-size="14" font-family="sans-serif" '
        'text-anchor="middle" dominant-baseline="central">'
        '${_escapeXml(text)}</text>');
  }

  svg.add('  <text x="${rect.left + 3}" y="${rect.top - 3}" '
      'fill="$_labelColor" font-size="$_labelFontSize" font-family="monospace">'
      '$shortId</text>');

  bounds.add(rect);
}

void _renderArrow(
  Map<String, dynamic> map,
  Map<String, Map<String, dynamic>> objectsById,
  Map<String, Rect> solidRects,
  List<String> svg,
  List<Rect> bounds,
) {
  final shortId = _shortId(map['id'] as String);
  final dashArray = _dashArray(map['lineStyle'] as String?);
  final pathType = map['pathType'] as String? ?? 'straight';
  final start = _parseOffset(map['start'] as List);
  final end = _parseOffset(map['end'] as List);

  List<Offset> fullPath;

  if (pathType == 'orthogonal') {
    fullPath = _computeOrthogonalPath(map, start, end, objectsById, solidRects);
  } else {
    // Straight or bezier — just connect start to end.
    fullPath = [start, end];
  }

  if (fullPath.length < 2) fullPath = [start, end];

  // Render polyline.
  final points = fullPath.map((p) => '${p.dx},${p.dy}').join(' ');
  svg.add('  <!-- arrow $shortId ($pathType) -->');
  svg.add('  <polyline points="$points" '
      'fill="none" stroke="$_arrowStroke" stroke-width="$_defaultStrokeWidth" '
      'stroke-linejoin="round" stroke-linecap="round"'
      '${dashArray.isNotEmpty ? ' stroke-dasharray="$dashArray"' : ''}'
      '/>');

  // Arrowhead at end.
  _renderArrowhead(fullPath, svg);

  // Label.
  final mid = fullPath[fullPath.length ~/ 2];
  svg.add('  <text x="${mid.dx + 4}" y="${mid.dy - 4}" '
      'fill="$_labelColor" font-size="$_labelFontSize" font-family="monospace">'
      '$shortId</text>');

  // Bounds.
  var bMinX = double.infinity, bMinY = double.infinity;
  var bMaxX = double.negativeInfinity, bMaxY = double.negativeInfinity;
  for (final p in fullPath) {
    bMinX = math.min(bMinX, p.dx);
    bMinY = math.min(bMinY, p.dy);
    bMaxX = math.max(bMaxX, p.dx);
    bMaxY = math.max(bMaxY, p.dy);
  }
  bounds.add(Rect.fromLTRB(bMinX, bMinY, bMaxX, bMaxY));
}

void _renderLine(
  Map<String, dynamic> map,
  Map<String, Map<String, dynamic>> objectsById,
  Map<String, Rect> solidRects,
  List<String> svg,
  List<Rect> bounds,
) {
  final shortId = _shortId(map['id'] as String);
  final dashArray = _dashArray(map['lineStyle'] as String?);
  final start = _parseOffset(map['start'] as List);
  final end = _parseOffset(map['end'] as List);

  final points = '${start.dx},${start.dy} ${end.dx},${end.dy}';
  svg.add('  <!-- line $shortId -->');
  svg.add('  <polyline points="$points" '
      'fill="none" stroke="$_lineStroke" stroke-width="$_defaultStrokeWidth" '
      'stroke-linejoin="round" stroke-linecap="round"'
      '${dashArray.isNotEmpty ? ' stroke-dasharray="$dashArray"' : ''}'
      '/>');

  svg.add('  <text x="${(start.dx + end.dx) / 2 + 4}" y="${(start.dy + end.dy) / 2 - 4}" '
      'fill="$_labelColor" font-size="$_labelFontSize" font-family="monospace">'
      '$shortId</text>');

  bounds.add(Rect.fromPoints(start, end));
}

void _renderPencilStroke(
  Map<String, dynamic> map,
  List<String> svg,
  List<Rect> bounds,
) {
  final shortId = _shortId(map['id'] as String);
  final rawPoints = map['points'] as List<dynamic>?;
  if (rawPoints == null || rawPoints.isEmpty) return;

  final pts = <Offset>[];
  for (final p in rawPoints) {
    final arr = p as List<dynamic>;
    pts.add(Offset((arr[0] as num).toDouble(), (arr[1] as num).toDouble()));
  }

  final pointsStr = pts.map((p) => '${p.dx},${p.dy}').join(' ');
  svg.add('  <!-- pencil $shortId -->');
  svg.add('  <polyline points="$pointsStr" '
      'fill="none" stroke="$_pencilStroke" stroke-width="1.5" '
      'stroke-linejoin="round" stroke-linecap="round"/>');

  var bMinX = double.infinity, bMinY = double.infinity;
  var bMaxX = double.negativeInfinity, bMaxY = double.negativeInfinity;
  for (final p in pts) {
    bMinX = math.min(bMinX, p.dx);
    bMinY = math.min(bMinY, p.dy);
    bMaxX = math.max(bMaxX, p.dx);
    bMaxY = math.max(bMaxY, p.dy);
  }
  bounds.add(Rect.fromLTRB(bMinX, bMinY, bMaxX, bMaxY));
}

void _renderFigure(
  Map<String, dynamic> map,
  List<String> svg,
  List<Rect> bounds,
) {
  final rect = _parseRect(map['rect'] as Map<String, dynamic>);
  final label = map['label'] as String? ?? '';
  final shortId = _shortId(map['id'] as String);

  svg.add('  <!-- figure $shortId -->');
  svg.add('  <rect x="${rect.left}" y="${rect.top}" '
      'width="${rect.width}" height="${rect.height}" '
      'fill="none" stroke="$_figureStroke" stroke-width="1" '
      'stroke-dasharray="6,3"/>');

  if (label.isNotEmpty) {
    svg.add('  <text x="${rect.left + 6}" y="${rect.top + 14}" '
        'fill="$_figureStroke" font-size="12" font-family="sans-serif">'
        '${_escapeXml(label)}</text>');
  }

  svg.add('  <text x="${rect.left + 3}" y="${rect.top - 3}" '
      'fill="$_labelColor" font-size="$_labelFontSize" font-family="monospace">'
      '$shortId</text>');

  bounds.add(rect);
}

void _renderText(
  Map<String, dynamic> map,
  List<String> svg,
  List<Rect> bounds,
) {
  final rect = _parseRect(map['rect'] as Map<String, dynamic>);
  final text = map['text'] as String? ?? '';
  final shortId = _shortId(map['id'] as String);

  svg.add('  <!-- text $shortId -->');
  if (text.isNotEmpty) {
    svg.add('  <text x="${rect.center.dx}" y="${rect.center.dy}" '
        'fill="$_textColor" font-size="14" font-family="sans-serif" '
        'text-anchor="middle" dominant-baseline="central">'
        '${_escapeXml(text)}</text>');
  }

  svg.add('  <text x="${rect.left + 3}" y="${rect.top - 3}" '
      'fill="$_labelColor" font-size="$_labelFontSize" font-family="monospace">'
      '$shortId</text>');

  bounds.add(rect);
}

// -- Arrow routing -----------------------------------------------------------

List<Offset> _computeOrthogonalPath(
  Map<String, dynamic> arrowMap,
  Offset start,
  Offset end,
  Map<String, Map<String, dynamic>> objectsById,
  Map<String, Rect> solidRects,
) {
  final startAttachment = arrowMap['startAttachment'] as Map<String, dynamic>?;
  final endAttachment = arrowMap['endAttachment'] as Map<String, dynamic>?;

  // Resolve attachment points to absolute coordinates.
  Rect? startObjRect;
  Rect? endObjRect;
  var routeStart = start;
  var routeEnd = end;

  if (startAttachment != null) {
    final objId = startAttachment['objectId'] as String;
    startObjRect = solidRects[objId];
    if (startObjRect != null) {
      final rel = _parseOffset(startAttachment['relativePosition'] as List);
      routeStart = _resolveAttachment(rel, startObjRect);
    }
  }

  if (endAttachment != null) {
    final objId = endAttachment['objectId'] as String;
    endObjRect = solidRects[objId];
    if (endObjRect != null) {
      final rel = _parseOffset(endAttachment['relativePosition'] as List);
      routeEnd = _resolveAttachment(rel, endObjRect);
    }
  }

  // Collect obstacles — all solid objects except source and target.
  final sourceId = startAttachment?['objectId'] as String?;
  final targetId = endAttachment?['objectId'] as String?;
  final obstacles = <Rect>[];
  for (final entry in solidRects.entries) {
    if (entry.key == sourceId || entry.key == targetId) continue;
    obstacles.add(entry.value);
  }

  // Route using the same algorithm as the app.
  final waypoints = OrthogonalRouter.route(
    start: routeStart,
    end: routeEnd,
    obstacles: obstacles,
    startObjectRect: startObjRect,
    endObjectRect: endObjRect,
  );

  return [routeStart, ...waypoints, routeEnd];
}

/// Convert a relative position (0-1 normalized) to absolute coords on a rect,
/// snapping to the nearest edge.
Offset _resolveAttachment(Offset relPos, Rect rect) {
  final absX = rect.left + relPos.dx * rect.width;
  final absY = rect.top + relPos.dy * rect.height;

  // Snap to nearest edge.
  final distLeft = (absX - rect.left).abs();
  final distRight = (absX - rect.right).abs();
  final distTop = (absY - rect.top).abs();
  final distBottom = (absY - rect.bottom).abs();
  final minDist = [distLeft, distRight, distTop, distBottom].reduce(math.min);

  if (minDist == distLeft) return Offset(rect.left, absY);
  if (minDist == distRight) return Offset(rect.right, absY);
  if (minDist == distTop) return Offset(absX, rect.top);
  return Offset(absX, rect.bottom);
}

// -- Arrowhead ---------------------------------------------------------------

void _renderArrowhead(List<Offset> path, List<String> svg) {
  if (path.length < 2) return;
  final tip = path.last;
  final prev = path[path.length - 2];

  // Direction from prev to tip.
  final dx = tip.dx - prev.dx;
  final dy = tip.dy - prev.dy;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 0.1) return;

  final ux = dx / len;
  final uy = dy / len;

  // Perpendicular.
  final px = -uy;
  final py = ux;

  final s = _arrowHeadSize;
  final base1 = Offset(tip.dx - ux * s + px * s * 0.4, tip.dy - uy * s + py * s * 0.4);
  final base2 = Offset(tip.dx - ux * s - px * s * 0.4, tip.dy - uy * s - py * s * 0.4);

  svg.add('  <polygon points="${tip.dx},${tip.dy} ${base1.dx},${base1.dy} ${base2.dx},${base2.dy}" '
      'fill="$_arrowStroke"/>');
}

// -- Helpers -----------------------------------------------------------------

Rect _parseRect(Map<String, dynamic> r) {
  return Rect.fromLTWH(
    (r['left'] as num).toDouble(),
    (r['top'] as num).toDouble(),
    (r['width'] as num).toDouble(),
    (r['height'] as num).toDouble(),
  );
}

Offset _parseOffset(List<dynamic> list) {
  return Offset(
    (list[0] as num).toDouble(),
    (list[1] as num).toDouble(),
  );
}

String _shortId(String id) {
  return id.length > 8 ? id.substring(0, 8) : id;
}

String _dashArray(String? lineStyle) {
  return switch (lineStyle) {
    'dashed' => '8,4',
    'dotted' => '2,4',
    _ => '',
  };
}

String _escapeXml(String s) {
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
