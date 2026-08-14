import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeline/src/core/utils/layered_layout.dart';

void main() {
  test('orders adjacent ranks without avoidable crossings', () {
    const size = Size(100, 60);
    const nodes = [
      LayoutNode('a', size),
      LayoutNode('b', size),
      LayoutNode('c', size),
      LayoutNode('x', size),
      LayoutNode('y', size),
      LayoutNode('z', size),
    ];
    const edges = [('a', 'z'), ('b', 'y'), ('c', 'x')];

    final result = const LayeredLayout().layout(nodes, edges);

    final upper = [
      'a',
      'b',
      'c',
    ]..sort((first, second) => result[first]!.dx.compareTo(result[second]!.dx));
    final lower = [
      'x',
      'y',
      'z',
    ]..sort((first, second) => result[first]!.dx.compareTo(result[second]!.dx));
    final lowerPosition = {for (final (index, id) in lower.indexed) id: index};
    final targets = {'a': 'z', 'b': 'y', 'c': 'x'};
    final targetOrder = [for (final id in upper) lowerPosition[targets[id]]!];

    expect(targetOrder, orderedEquals([0, 1, 2]));
  });
}
