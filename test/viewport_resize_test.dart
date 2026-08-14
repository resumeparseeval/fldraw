import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeline/src/ui/canvas/flow_draw_editor_data_layer.dart';

void main() {
  test('resize compensation preserves a world point on screen', () {
    const previous = Size(1200, 800);
    const next = Size(900, 650);
    const zoom = 0.5;
    const worldPoint = Offset(320, 240);
    const viewportOffset = Offset(-180, -120);

    final compensation = viewportResizeCompensation(previous, next, zoom);
    final previousScreen =
        previous.center(Offset.zero) + (worldPoint + viewportOffset) * zoom;
    final nextScreen =
        next.center(Offset.zero) +
        (worldPoint + viewportOffset + compensation) * zoom;

    expect(nextScreen.dx, closeTo(previousScreen.dx, 1e-9));
    expect(nextScreen.dy, closeTo(previousScreen.dy, 1e-9));
  });
}
