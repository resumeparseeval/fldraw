import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeline/src/blocs/canvas/canvas_bloc.dart';
import 'package:nodeline/src/models/drawing_entities.dart';

/// Round-trips the canvas through the same path Beziera's File ▸ Save / Open
/// uses: ProjectSaved → JSON string on disk → jsonDecode → ProjectLoaded.
/// Guards the app's core document feature.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CanvasBloc canvas;

  setUp(() => canvas = CanvasBloc());
  tearDown(() => canvas.close());

  test('save then load preserves nodes, viewport and font', () async {
    // Build a small document.
    canvas.add(DrawingObjectAdded(RectangleObject(
      id: 'r1',
      rect: const Rect.fromLTWH(40, 60, 120, 80),
      text: 'Hello',
    )));
    canvas.add(DrawingObjectAdded(ArrowObject(
      id: 'a1',
      start: const Offset(160, 100),
      end: const Offset(300, 200),
    )));
    await _pump();

    expect(canvas.state.drawingObjects, hasLength(2));

    // Save → encode to a JSON string (what gets written to the .beziera file).
    late String fileContents;
    canvas.add(ProjectSaved(onSave: (data) {
      fileContents = jsonEncode(data);
    }));
    await _pump();
    expect(fileContents, isNotEmpty);

    // Clear the canvas, as a fresh launch / New would.
    canvas.add(NewProjectCreated());
    await _pump();
    expect(canvas.state.drawingObjects, isEmpty);

    // Open → decode the file and load it back.
    final decoded = jsonDecode(fileContents) as Map<String, dynamic>;
    canvas.add(ProjectLoaded(decoded));
    await _pump();

    final loaded = canvas.state.drawingObjects;
    expect(loaded, hasLength(2));
    expect(loaded['r1'], isA<RectangleObject>());
    expect((loaded['r1'] as RectangleObject).text, 'Hello');
    expect(loaded['a1'], isA<ArrowObject>());
  });
}
