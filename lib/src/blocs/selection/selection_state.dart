part of 'selection_bloc.dart';

/// A specific endpoint of an edge (arrow/line) that the user has picked, so it
/// can be slid along its node edge with the arrow keys. [isStart] selects the
/// edge's start endpoint when true, otherwise its end endpoint.
typedef SelectedEndpoint = ({String objectId, bool isStart});

class SelectionState extends Equatable {
  final Set<String> selectedNodeIds;
  final Set<String> selectedDrawingObjectIds;
  /// The id of the drawing object currently hovered by the pointer, or null.
  final String? hoveredDrawingObjectId;
  /// A specific edge endpoint the user has picked for arrow-key movement, or
  /// null. Independent of [selectedDrawingObjectIds].
  final SelectedEndpoint? selectedEndpoint;

  const SelectionState({
    this.selectedNodeIds = const {},
    this.selectedDrawingObjectIds = const {},
    this.hoveredDrawingObjectId,
    this.selectedEndpoint,
  });

  SelectionState copyWith({
    Set<String>? selectedNodeIds,
    Set<String>? selectedDrawingObjectIds,
    String? hoveredDrawingObjectId,
    bool clearHoveredDrawingObjectId = false,
    SelectedEndpoint? selectedEndpoint,
    bool clearSelectedEndpoint = false,
  }) {
    return SelectionState(
      selectedNodeIds: selectedNodeIds ?? this.selectedNodeIds,
      selectedDrawingObjectIds:
      selectedDrawingObjectIds ?? this.selectedDrawingObjectIds,
      hoveredDrawingObjectId: clearHoveredDrawingObjectId
          ? null
          : (hoveredDrawingObjectId ?? this.hoveredDrawingObjectId),
      selectedEndpoint: clearSelectedEndpoint
          ? null
          : (selectedEndpoint ?? this.selectedEndpoint),
    );
  }

  @override
  List<Object?> get props => [
        selectedNodeIds,
        selectedDrawingObjectIds,
        hoveredDrawingObjectId,
        selectedEndpoint,
      ];
}