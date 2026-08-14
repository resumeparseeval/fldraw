import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:nodeline/src/blocs/canvas/canvas_bloc.dart';
import 'package:nodeline/src/models/drawing_entities.dart';

List<Offset> _arrowPolyline(ArrowObject arrow) {
  final rendered = arrow.renderedPath;
  if (rendered != null && rendered.length >= 2) return rendered;
  return [arrow.start, ...?arrow.waypoints, arrow.end];
}

@visibleForTesting
int countArrowCrossings(Iterable<ArrowObject> arrows) {
  final polylines = arrows
      .map(_arrowPolyline)
      .where((polyline) => polyline.length >= 2)
      .toList();
  var total = 0;
  for (var i = 0; i < polylines.length; i++) {
    for (var j = i + 1; j < polylines.length; j++) {
      final first = polylines[i];
      final second = polylines[j];
      final intersections = <String>{};
      for (var x = 0; x < first.length - 1; x++) {
        for (var y = 0; y < second.length - 1; y++) {
          final point = _segmentIntersection(
            first[x],
            first[x + 1],
            second[y],
            second[y + 1],
          );
          if (point == null ||
              (_isPathEndpoint(point, first) &&
                  _isPathEndpoint(point, second))) {
            continue;
          }
          // A crossing at a bend is found by both adjacent segments. Count its
          // screen position once per arrow pair.
          intersections.add(
            '${(point.dx * 1000).round()}:${(point.dy * 1000).round()}',
          );
        }
      }
      total += intersections.length;
    }
  }
  return total;
}

Offset? _segmentIntersection(Offset p1, Offset p2, Offset p3, Offset p4) {
  final first = p2 - p1;
  final second = p4 - p3;
  final cross = first.dx * second.dy - first.dy * second.dx;
  if (cross.abs() < 1e-10) return null;
  final t = ((p3.dx - p1.dx) * second.dy - (p3.dy - p1.dy) * second.dx) / cross;
  final u = ((p3.dx - p1.dx) * first.dy - (p3.dy - p1.dy) * first.dx) / cross;
  const epsilon = 1e-8;
  if (t < -epsilon || t > 1 + epsilon || u < -epsilon || u > 1 + epsilon) {
    return null;
  }
  return p1 + first * t;
}

bool _isPathEndpoint(Offset point, List<Offset> path) =>
    (point - path.first).distanceSquared < 1e-10 ||
    (point - path.last).distanceSquared < 1e-10;

/// A small toggleable HUD badge that shows the live count of edge crossings
/// (arrow-vs-arrow segment intersections) in the current diagram. Useful for
/// watching the count drop while running Tidy or hand-tuning connections.
class CrossingCounter extends StatefulWidget {
  const CrossingCounter({super.key});

  @override
  State<CrossingCounter> createState() => _CrossingCounterState();
}

class _CrossingCounterState extends State<CrossingCounter> {
  bool _enabled = true;
  CanvasState? _scheduledState;
  CanvasState? _refreshedState;

  void _schedulePostPaintRefresh(CanvasState state) {
    if (!_enabled ||
        identical(_scheduledState, state) ||
        identical(_refreshedState, state)) {
      return;
    }
    _scheduledState = state;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_enabled) return;
      _refreshedState = state;
      if (identical(_scheduledState, state)) _scheduledState = null;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 80,
      right: 12,
      child: GestureDetector(
        onTap: () => setState(() {
          _enabled = !_enabled;
          _scheduledState = null;
          _refreshedState = null;
        }),
        behavior: HitTestBehavior.opaque,
        child: BlocBuilder<CanvasBloc, CanvasState>(
          // Recompute whenever objects change (also fires on viewport changes,
          // which is fine — crossings are viewport-independent and cheap here).
          buildWhen: (a, b) =>
              _enabled &&
              (a.drawingObjects != b.drawingObjects || a.nodes != b.nodes),
          builder: (context, state) {
            _schedulePostPaintRefresh(state);
            final count = _enabled
                ? countArrowCrossings(
                    state.drawingObjects.values.whereType<ArrowObject>(),
                  )
                : 0;
            final color = !_enabled
                ? const Color(0x99000000)
                : count == 0
                ? const Color(0xCC047857) // green when crossing-free
                : const Color(0xCC1D4ED8);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _enabled
                      ? const Color(0xFF60A5FA)
                      : const Color(0x33FFFFFF),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _enabled ? Icons.call_split : Icons.call_split_outlined,
                    size: 13,
                    color: const Color(0xFFE5E7EB),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _enabled ? 'Crossings: $count' : 'Crossings',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFFE5E7EB),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
