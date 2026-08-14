import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeline/src/blocs/canvas/canvas_bloc.dart';
import 'package:nodeline/src/blocs/selection/selection_bloc.dart';
import 'package:nodeline/src/core/agent/tool_call.dart';
import 'package:nodeline/src/core/agent/tool_dispatcher.dart';
import 'package:nodeline/src/models/drawing_entities.dart';
import 'package:nodeline/src/ui/canvas/flow_draw_editor_data_layer.dart'
    show nextEndpointOnNode;

/// Sliding an edge endpoint along its attached node's edge: the bloc event, the
/// selected-endpoint selection state, and the agent tool.

Future<void> _pump() => Future<void>.delayed(Duration.zero);

/// A node-like shape (rectangle) at a known rect, plus an arrow whose END is
/// attached to the top edge of that shape.
void _seed(CanvasBloc bloc, {required Offset relEnd}) {
  bloc.add(DrawingObjectAdded(RectangleObject(
    id: 'box',
    rect: const Rect.fromLTWH(100, 100, 200, 80),
  )));
  bloc.add(DrawingObjectAdded(ArrowObject(
    id: 'e1',
    start: const Offset(0, 0),
    end: Offset(100 + 200 * relEnd.dx, 100 + 80 * relEnd.dy),
    endAttachment:
        ObjectAttachment(objectId: 'box', relativePosition: relEnd),
  )));
}

void main() {
  test('EndpointMovedAlongEdge slides the end along the top edge, staying attached',
      () async {
    final bloc = CanvasBloc();
    addTearDown(bloc.close);
    // End attached at center of the top edge (0.5, 0).
    _seed(bloc, relEnd: const Offset(0.5, 0.0));
    await _pump();

    bloc.add(const EndpointMovedAlongEdge('e1', false, 1)); // slide right
    await _pump();

    final a = bloc.state.drawingObjects['e1'] as ArrowObject;
    // Still attached to the same node, still on the top edge (dy == 0).
    expect(a.endAttachment, isNotNull);
    expect(a.endAttachment!.objectId, 'box');
    expect(a.endAttachment!.relativePosition.dy, 0.0);
    // Moved toward the right along x.
    expect(a.endAttachment!.relativePosition.dx, greaterThan(0.5));
    // World endpoint recomputed onto the node's top edge.
    expect(a.end.dy, 100.0);
    expect(a.end.dx, greaterThan(200.0)); // right of center (200)
  });

  test('fine (Shift) slide moves ~1px, far less than a coarse step', () async {
    final coarse = CanvasBloc();
    final fine = CanvasBloc();
    addTearDown(coarse.close);
    addTearDown(fine.close);
    _seed(coarse, relEnd: const Offset(0.5, 0.0)); // box width 200
    _seed(fine, relEnd: const Offset(0.5, 0.0));
    await _pump();

    coarse.add(const EndpointMovedAlongEdge('e1', false, 1));
    fine.add(const EndpointMovedAlongEdge('e1', false, 1, fine: true));
    await _pump();

    final coarseDx =
        (coarse.state.drawingObjects['e1'] as ArrowObject).endAttachment!.relativePosition.dx;
    final fineDx =
        (fine.state.drawingObjects['e1'] as ArrowObject).endAttachment!.relativePosition.dx;

    // Box 200x80 -> perimeter 560, avgEdge 140. Coarse step = 140/12 world
    // units along the top edge (width 200) => +0.0583 dx. Fine = 1px => +0.005.
    expect(coarseDx - 0.5, closeTo((140 / 12) / 200, 1e-6));
    expect(fineDx - 0.5, closeTo(1 / 200, 1e-6));
    expect(fineDx, lessThan(coarseDx));
  });

  test('sliding past a corner wraps onto the adjacent edge (same node)',
      () async {
    final bloc = CanvasBloc();
    addTearDown(bloc.close);
    // Start near the top-right corner of the top edge.
    _seed(bloc, relEnd: const Offset(0.95, 0.0));
    await _pump();

    // A few right-slides should carry it past the top-right corner and onto the
    // RIGHT edge (dx == 1, dy increasing from 0).
    for (var i = 0; i < 4; i++) {
      bloc.add(const EndpointMovedAlongEdge('e1', false, 1));
    }
    await _pump();
    final rel =
        (bloc.state.drawingObjects['e1'] as ArrowObject).endAttachment!.relativePosition;
    expect(rel.dx, closeTo(1.0, 1e-6), reason: 'now on the right edge');
    expect(rel.dy, greaterThan(0.0));
    expect(rel.dy, lessThan(1.0));
  });

  test('sliding wraps all the way around the perimeter and back', () async {
    final bloc = CanvasBloc();
    addTearDown(bloc.close);
    _seed(bloc, relEnd: const Offset(0.5, 0.0));
    await _pump();
    final start =
        (bloc.state.drawingObjects['e1'] as ArrowObject).endAttachment!.relativePosition;

    // Perimeter = 560, coarse step = 140/12 ≈ 11.67 world units. Enough presses
    // to traverse the whole perimeter wraps back near the origin.
    const stepsToWrap = 48; // 48 * 11.67 ≈ 560
    for (var i = 0; i < stepsToWrap; i++) {
      bloc.add(const EndpointMovedAlongEdge('e1', false, 1));
    }
    await _pump();
    final back =
        (bloc.state.drawingObjects['e1'] as ArrowObject).endAttachment!.relativePosition;
    // Returned to roughly the top edge near where it started.
    expect(back.dy, closeTo(0.0, 0.05));
    expect(back.dx, closeTo(start.dx, 0.1));
  });

  test('moving an unattached endpoint is a no-op', () async {
    final bloc = CanvasBloc();
    addTearDown(bloc.close);
    bloc.add(DrawingObjectAdded(ArrowObject(
      id: 'free',
      start: Offset.zero,
      end: const Offset(100, 0),
    )));
    await _pump();
    final before = bloc.state.drawingObjects['free'] as ArrowObject;
    bloc.add(const EndpointMovedAlongEdge('free', false, 1));
    await _pump();
    final after = bloc.state.drawingObjects['free'] as ArrowObject;
    expect(after.end, before.end);
  });

  test('undo of an endpoint move does NOT revert an earlier font-size change',
      () async {
    final bloc = CanvasBloc();
    addTearDown(bloc.close);
    _seed(bloc, relEnd: const Offset(0.5, 0.0));
    await _pump();

    // Earlier, unrelated change: bump the global default font size.
    bloc.add(const GlobalFontChanged(fontSize: 40));
    await _pump();
    expect(bloc.state.defaultFontSize, 40);

    // Move the endpoint.
    bloc.add(const EndpointMovedAlongEdge('e1', false, 1));
    await _pump();
    expect(
        (bloc.state.drawingObjects['e1'] as ArrowObject)
            .endAttachment!
            .relativePosition
            .dx,
        greaterThan(0.5));

    // Undo should revert ONLY the endpoint move; font size stays 40.
    bloc.add(UndoRequested());
    await _pump();
    expect(
        (bloc.state.drawingObjects['e1'] as ArrowObject)
            .endAttachment!
            .relativePosition
            .dx,
        0.5);
    expect(bloc.state.defaultFontSize, 40,
        reason: 'undo must not roll back the earlier font-size change');
  });

  test(
      'endpoint move undo is self-contained even after a stale DrawingObjectUpdated',
      () async {
    // Reproduces the reported bug: a prior DrawingObjectUpdated (as fired by
    // toolbar text/line-style edits) leaves a deferred pre-operation snapshot.
    // The endpoint move must NOT consume that stale snapshot, or undo would roll
    // back past the earlier edit.
    final bloc = CanvasBloc();
    addTearDown(bloc.close);
    _seed(bloc, relEnd: const Offset(0.5, 0.0));
    await _pump();

    // Earlier edit that sets the lingering snapshot: recolor the box.
    final box = bloc.state.drawingObjects['box'] as RectangleObject;
    bloc.add(DrawingObjectUpdated(
        box.copyWith(strokeColor: const Color(0xFFFF0000))));
    await _pump();
    expect((bloc.state.drawingObjects['box'] as RectangleObject).strokeColor,
        const Color(0xFFFF0000));

    // Endpoint move, then undo.
    bloc.add(const EndpointMovedAlongEdge('e1', false, 1));
    await _pump();
    bloc.add(UndoRequested());
    await _pump();

    // Endpoint reverted...
    expect(
        (bloc.state.drawingObjects['e1'] as ArrowObject)
            .endAttachment!
            .relativePosition
            .dx,
        0.5);
    // ...but the earlier recolor survives (not rolled back).
    expect((bloc.state.drawingObjects['box'] as RectangleObject).strokeColor,
        const Color(0xFFFF0000),
        reason: 'undo must not revert past the earlier edit');
  });

  test('the move is undoable', () async {
    final bloc = CanvasBloc();
    addTearDown(bloc.close);
    _seed(bloc, relEnd: const Offset(0.5, 0.0));
    await _pump();

    bloc.add(const EndpointMovedAlongEdge('e1', false, 1));
    await _pump();
    final moved =
        (bloc.state.drawingObjects['e1'] as ArrowObject).endAttachment!.relativePosition.dx;
    expect(moved, greaterThan(0.5));

    bloc.add(UndoRequested());
    await _pump();
    final restored =
        (bloc.state.drawingObjects['e1'] as ArrowObject).endAttachment!.relativePosition.dx;
    expect(restored, 0.5);
  });

  test('EndpointSelected sets selection state and clears object selection',
      () async {
    final sel = SelectionBloc();
    addTearDown(sel.close);
    sel.add(const SelectionReplaced(drawingObjectIds: {'x'}));
    await _pump();
    expect(sel.state.selectedDrawingObjectIds, {'x'});

    sel.add(const EndpointSelected((objectId: 'e1', isStart: false)));
    await _pump();
    expect(sel.state.selectedEndpoint, (objectId: 'e1', isStart: false));
    // Picking an endpoint clears the object selection.
    expect(sel.state.selectedDrawingObjectIds, isEmpty);

    // Selecting an object again clears the endpoint pick.
    sel.add(const SelectionReplaced(drawingObjectIds: {'y'}));
    await _pump();
    expect(sel.state.selectedEndpoint, isNull);
  });

  test('nextEndpointOnNode cycles through all endpoints attached to the node',
      () {
    const node = Rect.fromLTWH(0, 0, 100, 100);
    // Three different edges, each with an endpoint attached to "n":
    //  - e1.end on the top edge      (0.5, 0)   -> angle ~ -90°
    //  - e2.start on the right edge  (1.0, 0.5)  -> angle ~ 0°
    //  - e3.end on the bottom edge   (0.5, 1.0)  -> angle ~ +90°
    final objs = <String, DrawingObject>{
      'e1': ArrowObject(
        id: 'e1',
        start: const Offset(-50, -50),
        end: const Offset(50, 0),
        endAttachment: const ObjectAttachment(
            objectId: 'n', relativePosition: Offset(0.5, 0.0)),
      ),
      'e2': ArrowObject(
        id: 'e2',
        start: const Offset(100, 50),
        end: const Offset(200, 50),
        startAttachment: const ObjectAttachment(
            objectId: 'n', relativePosition: Offset(1.0, 0.5)),
      ),
      'e3': ArrowObject(
        id: 'e3',
        start: const Offset(50, 100),
        end: const Offset(50, 200),
        startAttachment: const ObjectAttachment(
            objectId: 'n', relativePosition: Offset(0.5, 1.0)),
      ),
    };

    // Clockwise order by angle: top(e1.end) -> right(e2.start) -> bottom(e3.start)
    final cur = (objectId: 'e1', isStart: false);
    final next = nextEndpointOnNode(
        current: cur, nodeId: 'n', nodeRect: node, drawingObjects: objs, dir: 1);
    expect(next, (objectId: 'e2', isStart: true));

    // Forward again lands on the bottom endpoint (a DIFFERENT edge — proves it
    // cycles across endpoints on the node, not just start<->end of one edge).
    final next2 = nextEndpointOnNode(
        current: next!, nodeId: 'n', nodeRect: node, drawingObjects: objs, dir: 1);
    expect(next2, (objectId: 'e3', isStart: true));

    // Previous from e1.end wraps to the last in clockwise order (e3.start).
    final prev = nextEndpointOnNode(
        current: cur, nodeId: 'n', nodeRect: node, drawingObjects: objs, dir: -1);
    expect(prev, (objectId: 'e3', isStart: true));
  });

  test('move_endpoint agent tool slides the endpoint', () async {
    final canvas = CanvasBloc();
    final selection = SelectionBloc();
    addTearDown(canvas.close);
    addTearDown(selection.close);
    _seed(canvas, relEnd: const Offset(0.5, 0.0));
    await _pump();

    final dispatcher =
        ToolDispatcher(canvasBloc: canvas, selectionBloc: selection);
    final result = dispatcher.dispatch(ToolCall(
      id: 't1',
      name: 'move_endpoint',
      args: const {'edgeId': 'e1', 'endpoint': 'end', 'steps': 2},
    ));
    await _pump();
    expect(result.ok, isTrue);
    final a = canvas.state.drawingObjects['e1'] as ArrowObject;
    expect(a.endAttachment!.relativePosition.dx, greaterThan(0.5));
    expect(a.endAttachment!.relativePosition.dy, 0.0);
  });
}
