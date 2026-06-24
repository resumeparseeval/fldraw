import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure mirror of `_navigateToNode`'s directional-nearest scoring (see
/// flow_draw_editor_data_layer.dart). Cmd+Arrow jumps the selection to the
/// nearest shape node within a 90° cone toward [dir]. Kept in lockstep with the
/// production heuristic so a regression in either shows up here.
String? nearestInDirection(Map<String, Rect> shapes, String fromId, Offset dir) {
  final origin = shapes[fromId]!.center;
  String? best;
  double bestScore = double.infinity;
  shapes.forEach((id, rect) {
    if (id == fromId) return;
    final d = rect.center - origin;
    final along = d.dx * dir.dx + d.dy * dir.dy;
    if (along <= 0) return; // not in the pressed direction
    final off = (d.dx * dir.dy - d.dy * dir.dx).abs();
    if (off > along) return; // outside the 90° cone
    final score = along + off * 2; // prefer aligned + near
    if (score < bestScore) {
      bestScore = score;
      best = id;
    }
  });
  return best;
}

void main() {
  // chicago — food — planta in a row; `below` sits under food.
  final shapes = <String, Rect>{
    'chicago': const Rect.fromLTWH(0, 0, 100, 80),
    'food': const Rect.fromLTWH(260, 0, 100, 80),
    'planta': const Rect.fromLTWH(520, 0, 100, 80),
    'below': const Rect.fromLTWH(260, 300, 100, 80),
  };

  const right = Offset(1, 0);
  const left = Offset(-1, 0);
  const up = Offset(0, -1);
  const down = Offset(0, 1);

  test('right steps along the row', () {
    expect(nearestInDirection(shapes, 'chicago', right), 'food');
    expect(nearestInDirection(shapes, 'food', right), 'planta');
  });

  test('no node past the end is a no-op', () {
    expect(nearestInDirection(shapes, 'planta', right), isNull);
  });

  test('left steps back along the row', () {
    expect(nearestInDirection(shapes, 'food', left), 'chicago');
  });

  test('down/up reach the vertically-offset node', () {
    expect(nearestInDirection(shapes, 'food', down), 'below');
    expect(nearestInDirection(shapes, 'below', up), 'food');
  });

  test('the cone is 90° wide, so a diagonal node still counts', () {
    // `below` is down-and-right of chicago. delta=(260,300): along(down)=300,
    // off=260, and 260 ≤ 300, so it sits just inside chicago's downward cone.
    expect(nearestInDirection(shapes, 'chicago', down), 'below');
  });

  test('a node beyond 45° off-axis is excluded', () {
    // A node only slightly below but far to the right of chicago is outside the
    // downward cone (off-axis spread exceeds along-axis distance).
    final s = <String, Rect>{
      'a': const Rect.fromLTWH(0, 0, 100, 80),
      'farRight': const Rect.fromLTWH(800, 60, 100, 80), // ~level, far right
    };
    expect(nearestInDirection(s, 'a', down), isNull);
    expect(nearestInDirection(s, 'a', right), 'farRight');
  });
}
