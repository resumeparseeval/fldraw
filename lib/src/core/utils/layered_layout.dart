import 'dart:math';
import 'dart:ui';

/// A node fed to [LayeredLayout]: an id plus its on-screen size in world units.
class LayoutNode {
  final String id;
  final Size size;
  const LayoutNode(this.id, this.size);
}

/// Result of a layout run: new top-left offsets keyed by node id.
typedef LayoutResult = Map<String, Offset>;

/// Layered (Sugiyama-style) graph layout that places nodes in ranks following
/// edge direction and reorders within ranks to minimize edge crossings.
///
/// Top-to-bottom only (ranks stacked vertically, edges flowing down), which is
/// what the app exposes today. The pipeline is the classic four-phase Sugiyama:
///
///   1. Break cycles (DFS) so ranking sees a DAG.
///   2. Assign ranks by longest path.
///   3. Insert virtual nodes so each edge spans one rank (keeps the crossing
///      math and routing well-defined for long edges).
///   4. Reduce crossings within ranks (median heuristic, up/down sweeps).
///   5. Assign x (within rank) and y (per rank) coordinates.
///
/// Validated on the dense "consciousness" diagram: ~44 → ~7 adjacent-rank
/// crossings (~84% reduction). Node repositioning is what actually
/// un-convolutes a diagram; port reassignment alone can't.
class LayeredLayout {
  /// Horizontal gap between adjacent nodes in the same rank (world units).
  final double nodeSpacing;

  /// Vertical gap between ranks (world units).
  final double rankSpacing;

  /// Top-left origin of the laid-out block.
  final Offset origin;

  const LayeredLayout({
    this.nodeSpacing = 48,
    this.rankSpacing = 80,
    this.origin = Offset.zero,
  });

  /// Computes new top-left offsets for [nodes] given directed [edges]
  /// (each edge is a `(fromId, toId)` record). Ids in [edges] that are not in
  /// [nodes] are ignored.
  LayoutResult layout(List<LayoutNode> nodes, List<(String, String)> edges) {
    if (nodes.isEmpty) return {};
    final nodeIds = {for (final n in nodes) n.id};
    final sizeOf = {for (final n in nodes) n.id: n.size};

    // Keep only edges whose endpoints both exist and aren't self-loops.
    final realEdges = edges
        .where((e) => e.$1 != e.$2 && nodeIds.contains(e.$1) && nodeIds.contains(e.$2))
        .toList();

    // ── 1. Break cycles via DFS; back-edges are reversed for ranking. ──────
    final adj = <String, List<String>>{for (final n in nodeIds) n: []};
    for (final e in realEdges) {
      adj[e.$1]!.add(e.$2);
    }
    final stateMap = <String, int>{}; // 0/null=unvisited, 1=in-stack, 2=done
    final acyclic = <(String, String)>[];
    void dfs(String u) {
      stateMap[u] = 1;
      for (final v in adj[u]!) {
        if (stateMap[v] == 1) {
          acyclic.add((v, u)); // reverse back-edge
        } else {
          acyclic.add((u, v));
          if (stateMap[v] != 2) dfs(v);
        }
      }
      stateMap[u] = 2;
    }

    for (final n in nodeIds) {
      if (stateMap[n] != 2) dfs(n);
    }

    // A stable traversal order gives equal-scoring sibling arrangements a
    // meaningful tie-break: preserve the caller's outgoing edge order instead
    // of inheriting an arbitrary set/topological iteration order.
    final discoveryOrder = <String, int>{};
    var discoveryIndex = 0;
    void discover(String id) {
      if (discoveryOrder.containsKey(id)) return;
      discoveryOrder[id] = discoveryIndex++;
      for (final child in adj[id]!) {
        discover(child);
      }
    }
    final hasIncoming = {for (final edge in realEdges) edge.$2};
    for (final node in nodes) {
      if (!hasIncoming.contains(node.id)) discover(node.id);
    }
    for (final node in nodes) {
      discover(node.id);
    }

    // ── 2. Rank assignment: longest path over the acyclic edge set. ────────
    final rank = <String, int>{for (final n in nodeIds) n: 0};
    final outA = <String, List<String>>{for (final n in nodeIds) n: []};
    final indeg = <String, int>{for (final n in nodeIds) n: 0};
    for (final e in acyclic) {
      outA[e.$1]!.add(e.$2);
      indeg[e.$2] = indeg[e.$2]! + 1;
    }
    final work = Map<String, int>.from(indeg);
    final stack = [...nodeIds.where((n) => work[n] == 0)];
    final topo = <String>[];
    while (stack.isNotEmpty) {
      final u = stack.removeLast();
      topo.add(u);
      for (final v in outA[u]!) {
        work[v] = work[v]! - 1;
        if (work[v] == 0) stack.add(v);
      }
    }
    for (final u in topo) {
      for (final v in outA[u]!) {
        if (rank[v]! < rank[u]! + 1) rank[v] = rank[u]! + 1;
      }
    }
    final maxRank = rank.values.fold(0, max);

    // ── 3. Virtual nodes so each acyclic edge spans exactly one rank. ──────
    final ranks = <int, List<String>>{for (var i = 0; i <= maxRank; i++) i: []};
    for (final node in nodes) {
      ranks[rank[node.id]!]!.add(node.id);
    }
    for (final rankNodes in ranks.values) {
      rankNodes.sort(
        (a, b) => discoveryOrder[a]!.compareTo(discoveryOrder[b]!),
      );
    }
    var vc = 0;
    final chains = <List<String>>[];
    for (final e in acyclic) {
      final a = e.$1, b = e.$2;
      final ra = rank[a]!, rb = rank[b]!;
      if (rb - ra <= 1) {
        chains.add([a, b]);
      } else {
        final chain = <String>[a];
        for (var l = ra + 1; l < rb; l++) {
          final vn = '__v${vc++}';
          rank[vn] = l;
          ranks[l]!.add(vn);
          chain.add(vn);
        }
        chain.add(b);
        chains.add(chain);
      }
    }

    // ── 4. Crossing reduction: median heuristic, up/down sweeps. ───────────
    final order = <int, List<String>>{
      for (var i = 0; i <= maxRank; i++) i: List<String>.from(ranks[i]!)
    };
    final down = <String, List<String>>{};
    final up = <String, List<String>>{};
    final adjacentEdges = <int, List<(String, String)>>{};
    for (final chain in chains) {
      for (var i = 0; i < chain.length - 1; i++) {
        (down[chain[i]] ??= []).add(chain[i + 1]);
        (up[chain[i + 1]] ??= []).add(chain[i]);
        (adjacentEdges[rank[chain[i]]!] ??= []).add((chain[i], chain[i + 1]));
      }
    }

    double median(List<String> neighbors, List<String> fixed) {
      if (neighbors.isEmpty) return -1;
      final ps = neighbors
          .map((n) => fixed.indexOf(n))
          .where((p) => p >= 0)
          .toList()
        ..sort();
      if (ps.isEmpty) return -1;
      return ps[ps.length ~/ 2].toDouble();
    }

    void sortByMedian(List<String> cur, Map<String, double> med) {
      // Stable: nodes with no fixed neighbors (-1) keep their relative order.
      final indexed = [
        for (var i = 0; i < cur.length; i++) (cur[i], med[cur[i]]!, i)
      ];
      indexed.sort((a, b) {
        final ma = a.$2, mb = b.$2;
        if (ma == -1 && mb == -1) return a.$3.compareTo(b.$3);
        if (ma == -1) return a.$3.compareTo(b.$3); // keep position-ish
        if (mb == -1) return a.$3.compareTo(b.$3);
        final c = ma.compareTo(mb);
        return c != 0 ? c : a.$3.compareTo(b.$3);
      });
      for (var i = 0; i < cur.length; i++) {
        cur[i] = indexed[i].$1;
      }
    }

    int crossingsBetween(int upperRank) {
      if (upperRank < 0 || upperRank >= maxRank) return 0;
      final edges = adjacentEdges[upperRank] ?? const [];
      final upperPosition = {
        for (final (index, id) in order[upperRank]!.indexed) id: index,
      };
      final lowerPosition = {
        for (final (index, id) in order[upperRank + 1]!.indexed) id: index,
      };
      var crossings = 0;
      for (var i = 0; i < edges.length; i++) {
        for (var j = i + 1; j < edges.length; j++) {
          final first = edges[i];
          final second = edges[j];
          if (first.$1 == second.$1 || first.$2 == second.$2) continue;
          final upperDelta = upperPosition[first.$1]! - upperPosition[second.$1]!;
          final lowerDelta = lowerPosition[first.$2]! - lowerPosition[second.$2]!;
          if (upperDelta * lowerDelta < 0) crossings++;
        }
      }
      return crossings;
    }

    int crossingsAround(int rankIndex) =>
        crossingsBetween(rankIndex - 1) + crossingsBetween(rankIndex);

    int totalCrossings() {
      var total = 0;
      for (var rankIndex = 0; rankIndex < maxRank; rankIndex++) {
        total += crossingsBetween(rankIndex);
      }
      return total;
    }

    void transposeRank(int rankIndex) {
      final current = order[rankIndex]!;
      if (current.length < 2) return;
      var improved = true;
      while (improved) {
        improved = false;
        for (var i = 0; i < current.length - 1; i++) {
          final before = crossingsAround(rankIndex);
          final left = current[i];
          current[i] = current[i + 1];
          current[i + 1] = left;
          final after = crossingsAround(rankIndex);
          if (after < before) {
            improved = true;
          } else {
            final right = current[i];
            current[i] = current[i + 1];
            current[i + 1] = right;
          }
        }
      }
    }

    var bestCrossings = totalCrossings();
    var bestOrder = <int, List<String>>{
      for (var rankIndex = 0; rankIndex <= maxRank; rankIndex++)
        rankIndex: List<String>.from(order[rankIndex]!),
    };

    void retainBestOrder() {
      final crossings = totalCrossings();
      if (crossings >= bestCrossings) return;
      bestCrossings = crossings;
      bestOrder = <int, List<String>>{
        for (var rankIndex = 0; rankIndex <= maxRank; rankIndex++)
          rankIndex: List<String>.from(order[rankIndex]!),
      };
    }

    for (var iter = 0; iter < 8; iter++) {
      for (var l = 1; l <= maxRank; l++) {
        final fixed = order[l - 1]!;
        final cur = order[l]!;
        sortByMedian(
            cur, {for (final n in cur) n: median(up[n] ?? const [], fixed)});
      }
      for (var l = 0; l <= maxRank; l++) {
        transposeRank(l);
      }
      retainBestOrder();

      for (var l = maxRank - 1; l >= 0; l--) {
        final fixed = order[l + 1]!;
        final cur = order[l]!;
        sortByMedian(
            cur, {for (final n in cur) n: median(down[n] ?? const [], fixed)});
      }
      // Classic Sugiyama transpose phase: keep an adjacent swap only when it
      // lowers the exact crossing count around that rank. Median sweeps find a
      // good global order; transposition removes their remaining local
      // inversions without making another rank worse.
      for (var l = 0; l <= maxRank; l++) {
        transposeRank(l);
      }
      retainBestOrder();
    }

    // Median sweeps are heuristic and can make a later pass worse. Use the
    // lowest-crossing ordering encountered, not simply the final pass.
    for (var l = 0; l <= maxRank; l++) {
      order[l]!
        ..clear()
        ..addAll(bestOrder[l]!);
    }

    // ── 5. Coordinate assignment. ──────────────────────────────────────────
    // Virtual nodes get a slim width so long edges don't reserve full columns.
    const virtualWidth = 24.0;
    double widthOf(String id) =>
        id.startsWith('__v') ? virtualWidth : (sizeOf[id]?.width ?? 80);
    double heightOf(String id) =>
        id.startsWith('__v') ? 0 : (sizeOf[id]?.height ?? 40);

    // Rank y = stacked rank heights + spacing.
    final rankHeight = <int, double>{};
    for (var l = 0; l <= maxRank; l++) {
      double h = 0;
      for (final id in order[l]!) {
        h = max(h, heightOf(id));
      }
      rankHeight[l] = h;
    }
    final rankY = <int, double>{};
    double y = origin.dy;
    for (var l = 0; l <= maxRank; l++) {
      rankY[l] = y;
      y += rankHeight[l]! + rankSpacing;
    }

    // ── x-coordinate assignment ─────────────────────────────────────────────
    // Center x per node (so edges can be compared by center). Start with a
    // simple left→right packing, then iteratively pull each node toward the
    // average center-x of its neighbors in adjacent ranks (barycenter), while
    // resolving overlaps left→right. This straightens edges and removes most of
    // the diagonal crossings the orthogonal router would otherwise weave.
    final centerX = <String, double>{};
    for (var l = 0; l <= maxRank; l++) {
      double x = origin.dx;
      for (final id in order[l]!) {
        final w = widthOf(id);
        centerX[id] = x + w / 2;
        x += w + nodeSpacing;
      }
    }

    double avgNeighborX(String id) {
      final ns = [...?up[id], ...?down[id]];
      if (ns.isEmpty) return centerX[id]!;
      double sum = 0;
      var n = 0;
      for (final m in ns) {
        final c = centerX[m];
        if (c != null) {
          sum += c;
          n++;
        }
      }
      return n == 0 ? centerX[id]! : sum / n;
    }

    // Resolve overlaps within a rank, keeping order, by pushing right.
    void resolveRank(List<String> rankIds) {
      for (var i = 1; i < rankIds.length; i++) {
        final prev = rankIds[i - 1], cur = rankIds[i];
        final minGap = widthOf(prev) / 2 + nodeSpacing + widthOf(cur) / 2;
        if (centerX[cur]! < centerX[prev]! + minGap) {
          centerX[cur] = centerX[prev]! + minGap;
        }
      }
    }

    for (var iter = 0; iter < 12; iter++) {
      // Alternate sweep direction for balance.
      final order2 = iter.isEven
          ? [for (var l = 0; l <= maxRank; l++) l]
          : [for (var l = maxRank; l >= 0; l--) l];
      for (final l in order2) {
        final ids = order[l]!;
        for (final id in ids) {
          centerX[id] = avgNeighborX(id);
        }
        resolveRank(ids);
      }
    }

    // Convert center-x back to top-left offsets for real nodes only.
    final result = <String, Offset>{};
    for (var l = 0; l <= maxRank; l++) {
      for (final id in order[l]!) {
        if (id.startsWith('__v')) continue;
        final w = widthOf(id);
        final yc = rankY[l]! + (rankHeight[l]! - heightOf(id)) / 2;
        result[id] = Offset(centerX[id]! - w / 2, yc);
      }
    }
    return result;
  }
}
