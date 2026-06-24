import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure mirror of `_firstFreeSlot` (see flow_draw_editor_data_layer.dart) sans
/// the grid snapping: start at (left, top); if that overlaps any existing rect,
/// step downward by [step] until clear. Tab uses this so a new connected node
/// stacks under an existing child instead of overlapping it.
Rect firstFreeSlot({
  required double left,
  required double top,
  required double width,
  required double height,
  required double step,
  required List<Rect> existing,
}) {
  var candidateTop = top;
  for (var i = 0; i < 200; i++) {
    final candidate = Rect.fromLTWH(left, candidateTop, width, height);
    if (!existing.any((r) => r.overlaps(candidate))) return candidate;
    candidateTop += step;
  }
  return Rect.fromLTWH(left, candidateTop, width, height);
}

void main() {
  const w = 100.0, h = 80.0;
  // step mirrors production: height + (height*0.6).clamp(40,160) = 80 + 48 = 128
  const step = 128.0;

  test('empty target slot is used as-is', () {
    final slot = firstFreeSlot(
      left: 260, top: 0, width: w, height: h, step: step, existing: const [],
    );
    expect(slot.left, 260);
    expect(slot.top, 0);
  });

  test('occupied slot stacks down to the first free row', () {
    // A child already sits at the default right-slot (260,0).
    final existing = <Rect>[const Rect.fromLTWH(260, 0, w, h)];
    final slot = firstFreeSlot(
      left: 260, top: 0, width: w, height: h, step: step, existing: existing,
    );
    expect(slot.left, 260); // same column
    expect(slot.top, 128); // pushed down one row, no longer overlapping
    expect(existing.any((r) => r.overlaps(slot)), isFalse);
  });

  test('two occupied rows push to the third', () {
    final existing = <Rect>[
      const Rect.fromLTWH(260, 0, w, h),
      const Rect.fromLTWH(260, 128, w, h),
    ];
    final slot = firstFreeSlot(
      left: 260, top: 0, width: w, height: h, step: step, existing: existing,
    );
    expect(slot.top, 256);
    expect(existing.any((r) => r.overlaps(slot)), isFalse);
  });

  test('a node in a different column does not push placement down', () {
    // Existing node far to the right shares no x-overlap with the target slot.
    final existing = <Rect>[const Rect.fromLTWH(900, 0, w, h)];
    final slot = firstFreeSlot(
      left: 260, top: 0, width: w, height: h, step: step, existing: existing,
    );
    expect(slot.top, 0); // stays in the default row
  });
}
