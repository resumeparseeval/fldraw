// Generates the README hero images by importing Mermaid diagrams through the
// SDK's own importer and rendering them with PngExporter. Run with:
//   flutter test test/generate_readme_images_test.dart
// Output: assets/readme/*.png
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeline/nodeline.dart';
import 'package:nodeline/src/models/drawing_entities.dart'
    show drawingObjectFromJson, LinkPathType;
import 'package:nodeline/src/core/utils/orthogonal_router.dart';

Future<void> _render(String mermaid, String outPath, {double pixelRatio = 2.0}) async {
  // The PNG exporter renders label text verbatim and the importer parses line
  // by line, so collapse Mermaid's <br/> tags to a space (keeps each node on
  // one source line while dropping the literal tag from the rendered label).
  mermaid = mermaid.replaceAll(RegExp(r'<br\s*/?>'), ' ');
  final project = MermaidImporter.import(mermaid);
  final list = (project['drawingObjects'] as List)
      .map((j) => drawingObjectFromJson(j as Map<String, dynamic>))
      .whereType<DrawingObject>()
      .toList();
  final objects = {for (final o in list) o.id: o};
  expect(objects, isNotEmpty, reason: 'importer produced no objects for $outPath');

  // Route arrows orthogonally so the exported image matches the real app's
  // perpendicular routing. The importer marks arrows orthogonal but leaves
  // waypoints for the paint-time router, so we run that router here exactly the
  // way the render object does: snap each endpoint to its attached node's edge,
  // pass the source/target rects (which drive the perpendicular exit/entry
  // stubs) and exclude those two rects from the obstacle list.
  final routed = <(Offset, Offset)>[];
  for (final o in objects.values) {
    if (o is! ArrowObject || o.pathType != LinkPathType.orthogonal) continue;

    final startId = o.startAttachment?.objectId;
    final endId = o.endAttachment?.objectId;
    final startObj = startId != null ? objects[startId] : null;
    final endObj = endId != null ? objects[endId] : null;
    final startRect = startObj?.rect;
    final endRect = endObj?.rect;

    var start = startRect != null ? _snapToNearestEdge(o.start, startRect) : o.start;
    var end = endRect != null ? _snapToNearestEdge(o.end, endRect) : o.end;
    // For non-rectangular shapes (e.g. diamonds) the bounding-box edge sits
    // outside the visual border, leaving a gap. Pull the endpoint onto the
    // actual shape path so the line touches the drawn edge.
    if (startObj != null) start = _snapToShapeBorder(start, startObj);
    if (endObj != null) end = _snapToShapeBorder(end, endObj);

    final obstacles = <Rect>[];
    for (final other in objects.values) {
      if (other.id == o.id) continue;
      if (other.id == startId || other.id == endId) continue;
      if (other is ArrowObject || other is LineObject) continue;
      obstacles.add(other.rect);
    }

    o.start = start;
    o.end = end;
    o.waypoints = OrthogonalRouter.route(
      start: start,
      end: end,
      obstacles: obstacles,
      startObjectRect: startRect,
      endObjectRect: endRect,
      existingSegments: routed,
    );
    final pts = [start, ...?o.waypoints, end];
    for (var i = 0; i < pts.length - 1; i++) {
      routed.add((pts[i], pts[i + 1]));
    }
  }

  final png = await PngExporter.exportPng(objects, pixelRatio: pixelRatio);
  expect(png, isNotNull, reason: 'exporter returned null for $outPath');

  final file = File(outPath);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(png!);
  // ignore: avoid_print
  print('wrote $outPath (${png.length} bytes, ${objects.length} objects)');
}

/// Pulls a (bounding-box-snapped) endpoint onto the object's actual drawn
/// border. Rectangles/circles already fill their box closely enough, but
/// diamonds and parallelograms have a visual border inset from the box, so the
/// line would otherwise stop short. We sample the shape's [Path] and find the
/// border point along the endpoint's entry axis (vertical if the point is on
/// the box top/bottom edge, horizontal if on the left/right edge).
Offset _snapToShapeBorder(Offset point, DrawingObject obj) {
  final rect = obj.rect;
  const eps = 0.5;
  final onTopOrBottom =
      (point.dy - rect.top).abs() < eps || (point.dy - rect.bottom).abs() < eps;

  // Diamonds connect at their 4 vertices (the canonical flowchart look): a
  // vertical entry meets the top/bottom point, a horizontal entry meets the
  // left/right point. This makes the stub land exactly on a vertex instead of
  // mid-face, where a straight stub would otherwise meet the slanted edge.
  if (obj is DiamondObject) {
    final c = rect.center;
    if (onTopOrBottom) {
      return Offset(c.dx, point.dy <= c.dy ? rect.top : rect.bottom);
    }
    return Offset(point.dx <= c.dx ? rect.left : rect.right, c.dy);
  }

  final Path path;
  if (obj is ParallelogramObject) {
    path = obj.path;
  } else {
    return point;
  }

  Offset? best;
  double bestDelta = double.infinity;
  for (final metric in path.computeMetrics()) {
    for (double d = 0; d <= metric.length; d += 1.0) {
      final pos = metric.getTangentForOffset(d)?.position;
      if (pos == null) continue;
      if (onTopOrBottom) {
        // Entry is vertical: keep x, find the border y nearest the point.
        if ((pos.dx - point.dx).abs() > 1.5) continue;
        final delta = (pos.dy - point.dy).abs();
        if (delta < bestDelta) {
          bestDelta = delta;
          best = Offset(point.dx, pos.dy);
        }
      } else {
        // Entry is horizontal: keep y, find the border x nearest the point.
        if ((pos.dy - point.dy).abs() > 1.5) continue;
        final delta = (pos.dx - point.dx).abs();
        if (delta < bestDelta) {
          bestDelta = delta;
          best = Offset(pos.dx, point.dy);
        }
      }
    }
  }
  return best ?? point;
}

/// Mirrors the render object's snap: moves [point] onto the nearest edge of
/// [rect] so the router's stub leaves the box perpendicularly.
Offset _snapToNearestEdge(Offset point, Rect rect) {
  final distToLeft = (point.dx - rect.left).abs();
  final distToRight = (point.dx - rect.right).abs();
  final distToTop = (point.dy - rect.top).abs();
  final distToBottom = (point.dy - rect.bottom).abs();
  final minDist =
      [distToLeft, distToRight, distToTop, distToBottom].reduce((a, b) => a < b ? a : b);
  if (minDist == distToLeft) return Offset(rect.left, point.dy);
  if (minDist == distToRight) return Offset(rect.right, point.dy);
  if (minDist == distToTop) return Offset(point.dx, rect.top);
  return Offset(point.dx, rect.bottom);
}

Future<void> _registerFont(String family, List<String> candidatePaths) async {
  for (final path in candidatePaths) {
    final f = File(path);
    if (f.existsSync()) {
      final loader = FontLoader(family)
        ..addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
      await loader.load();
      return;
    }
  }
  // ignore: avoid_print
  print('WARNING: no font found for family "$family"; text may render as boxes');
}

Future<void> _loadRealFont() async {
  // flutter test ships the "Ahem" font (every glyph is a solid box), so we must
  // register real TTFs under EVERY family the exporter asks for: 'sans-serif'
  // for body labels and the default font family (Courier) for the monospace
  // title runs. Without the Courier registration, titles render as tofu boxes.
  const sans = [
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/Library/Fonts/Arial Unicode.ttf',
  ];
  const mono = [
    '/System/Library/Fonts/Supplemental/Courier New.ttf',
    '/System/Library/Fonts/Menlo.ttc',
    '/System/Library/Fonts/Monaco.ttf',
  ];
  await _registerFont('sans-serif', sans);
  await _registerFont('Courier', mono);
  await _registerFont(kEditorDefaultFontFamily, mono);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const basic = '''
flowchart TD
    A["Start"] --> B["Process Input"]
    B --> C{"Valid?"}
    C --> D["Save to Database"]
    C --> E["Show Error"]
    D --> F["Done"]
    E --> B
''';

  testWidgets('basic_ui.png', (tester) async {
    await tester.runAsync(() async {
      await _loadRealFont();
      await _render(basic, 'assets/readme/basic_ui.png');
    });
  });

  testWidgets('complex consciousness diagram', (tester) async {
    await tester.runAsync(() async {
      await _loadRealFont();
      await _render(TestDiagrams.consciousness, 'assets/readme/complex.png');
    });
  });
}
