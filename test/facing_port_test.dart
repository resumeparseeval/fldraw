import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure mirror of `_facingPort` (see flow_draw_editor_data_layer.dart): given a
/// node rect and the rect it should point at, returns the cardinal port
/// (attachment relativePosition) on the side facing the target. Used both by
/// Alt/Cmd drag re-porting and by arrow-key-move re-porting so a moved node's
/// edges keep facing their neighbours instead of crossing.
Offset facingPort(Rect fromRect, Rect toRect) {
  const top = Offset(0.5, 0.0);
  const bottom = Offset(0.5, 1.0);
  const left = Offset(0.0, 0.5);
  const right = Offset(1.0, 0.5);
  final d = toRect.center - fromRect.center;
  if (d.dy.abs() >= d.dx.abs()) {
    return d.dy >= 0 ? bottom : top;
  }
  return d.dx >= 0 ? right : left;
}

void main() {
  final origin = const Rect.fromLTWH(0, 0, 100, 80);
  Rect at(double dx, double dy) =>
      Rect.fromLTWH(origin.left + dx, origin.top + dy, 100, 80);

  test('target to the right → right port', () {
    expect(facingPort(origin, at(300, 0)), const Offset(1.0, 0.5));
  });

  test('target to the left → left port', () {
    expect(facingPort(origin, at(-300, 0)), const Offset(0.0, 0.5));
  });

  test('target below → bottom port', () {
    expect(facingPort(origin, at(0, 300)), const Offset(0.5, 1.0));
  });

  test('target above → top port', () {
    expect(facingPort(origin, at(0, -300)), const Offset(0.5, 0.0));
  });

  test('mostly-vertical diagonal prefers the vertical side', () {
    // dy dominates → bottom, even though there's some rightward offset.
    expect(facingPort(origin, at(80, 300)), const Offset(0.5, 1.0));
  });

  test('mostly-horizontal diagonal prefers the horizontal side', () {
    expect(facingPort(origin, at(300, 80)), const Offset(1.0, 0.5));
  });
}
