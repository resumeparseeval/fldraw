/// Minimal Offset and Rect classes compatible with Flutter's API surface,
/// for use in standalone CLI tools that can't depend on dart:ui.
import 'dart:math' as math;

class Offset {
  final double dx;
  final double dy;

  const Offset(this.dx, this.dy);
  static const Offset zero = Offset(0, 0);

  double get distance => math.sqrt(dx * dx + dy * dy);
  double get distanceSquared => dx * dx + dy * dy;

  Offset operator +(Offset other) => Offset(dx + other.dx, dy + other.dy);
  Offset operator -(Offset other) => Offset(dx - other.dx, dy - other.dy);
  Offset operator *(double operand) => Offset(dx * operand, dy * operand);
  Offset operator /(double operand) => Offset(dx / operand, dy / operand);

  @override
  bool operator ==(Object other) =>
      other is Offset && dx == other.dx && dy == other.dy;

  @override
  int get hashCode => Object.hash(dx, dy);

  @override
  String toString() => 'Offset($dx, $dy)';
}

class Rect {
  final double left;
  final double top;
  final double _width;
  final double _height;

  const Rect._(this.left, this.top, this._width, this._height);

  factory Rect.fromLTWH(double left, double top, double width, double height) =>
      Rect._(left, top, width, height);

  factory Rect.fromLTRB(double left, double top, double right, double bottom) =>
      Rect._(left, top, right - left, bottom - top);

  factory Rect.fromPoints(Offset a, Offset b) {
    final l = math.min(a.dx, b.dx);
    final t = math.min(a.dy, b.dy);
    final r = math.max(a.dx, b.dx);
    final bo = math.max(a.dy, b.dy);
    return Rect._(l, t, r - l, bo - t);
  }

  double get width => _width;
  double get height => _height;
  double get right => left + _width;
  double get bottom => top + _height;

  Offset get center => Offset(left + _width / 2, top + _height / 2);
  Offset get topLeft => Offset(left, top);
  Offset get topRight => Offset(right, top);
  Offset get bottomLeft => Offset(left, bottom);
  Offset get bottomRight => Offset(right, bottom);
  Offset get topCenter => Offset(left + _width / 2, top);
  Offset get bottomCenter => Offset(left + _width / 2, bottom);
  Offset get centerLeft => Offset(left, top + _height / 2);
  Offset get centerRight => Offset(right, top + _height / 2);

  Rect inflate(double delta) =>
      Rect._(left - delta, top - delta, _width + delta * 2, _height + delta * 2);

  bool overlaps(Rect other) =>
      left < other.right &&
      right > other.left &&
      top < other.bottom &&
      bottom > other.top;

  bool contains(Offset point) =>
      point.dx >= left && point.dx <= right &&
      point.dy >= top && point.dy <= bottom;

  Rect get normalize {
    final w = _width < 0 ? -_width : _width;
    final h = _height < 0 ? -_height : _height;
    final l = _width < 0 ? left + _width : left;
    final t = _height < 0 ? top + _height : top;
    return Rect._(l, t, w, h);
  }

  @override
  bool operator ==(Object other) =>
      other is Rect &&
      left == other.left &&
      top == other.top &&
      _width == other._width &&
      _height == other._height;

  @override
  int get hashCode => Object.hash(left, top, _width, _height);

  @override
  String toString() => 'Rect.fromLTWH($left, $top, $_width, $_height)';
}
