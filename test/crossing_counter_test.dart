import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeline/nodeline.dart';
import 'package:nodeline/src/ui/canvas/crossing_counter.dart';

ArrowObject _arrow(String id, List<Offset> renderedPath) => ArrowObject(
  id: id,
  start: const Offset(-100, -100),
  end: const Offset(-50, -50),
)..renderedPath = renderedPath;

void main() {
  test('counts the rendered route instead of stale raw endpoints', () {
    final first = _arrow('first', const [Offset(0, 0), Offset(10, 0)]);
    final second = _arrow('second', const [Offset(5, -5), Offset(5, 5)]);

    expect(countArrowCrossings([first, second]), 1);
  });

  test('counts a visible crossing at a route bend once', () {
    final first = _arrow('first', const [
      Offset(0, 0),
      Offset(5, 0),
      Offset(5, 5),
    ]);
    final second = _arrow('second', const [Offset(5, -5), Offset(5, 3)]);

    expect(countArrowCrossings([first, second]), 1);
  });

  test('does not count a shared arrow endpoint as a crossing', () {
    final first = _arrow('first', const [Offset(0, 0), Offset(10, 0)]);
    final second = _arrow('second', const [Offset(0, 0), Offset(0, 10)]);

    expect(countArrowCrossings([first, second]), 0);
  });
}
