import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeline/nodeline.dart';
import 'package:nodeline/src/ui/canvas/flow_draw_editor_render_object.dart';

void main() {
  const rect = Rect.fromLTWH(0, 0, 120, 80);

  test('paint dispatch includes every supported workflow shape', () {
    final shapes = <DrawingObject>[
      RectangleObject(id: 'rectangle', rect: rect),
      CircleObject(id: 'circle', rect: rect),
      DiamondObject(id: 'diamond', rect: rect),
      ParallelogramObject(id: 'parallelogram', rect: rect),
      ForkJoinObject(id: 'fork-join', rect: rect),
      FigureObject(id: 'figure', rect: rect),
      TextObject(id: 'text', rect: rect),
    ];

    expect(shapes.every(isCanvasShapeObject), isTrue);
    expect(
      isCanvasShapeObject(
        ArrowObject(id: 'arrow', start: rect.centerLeft, end: rect.centerRight),
      ),
      isFalse,
    );
  });
}
