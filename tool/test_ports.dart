import 'package:nodeline/src/core/mermaid/mermaid_importer.dart';

void main() {
  final result = MermaidImporter.import('''flowchart TD
    B --> A
    B --> C
    B --> D
    B --> E
    G --> A
    H --> J
    H --> I
    H --> G
    F --> G
    B --> J
    A["abuse alarms"]
    B["patterns"]
    C["gifting"]
    D["time"]
    E["attention"]
    F["self judgement about own parenting"]
    G["children's preferences for others"]
    H["fabrication by kid"]
    I["eg. neighbor allows me to xyz"]
    J["neighbor is seen as authority figure"]''');

  final objects = result['drawingObjects'] as List;
  final arrows = objects.where((o) => o['type'] == 'arrow').toList();
  final nodeIdToLabel = <String, String>{};
  for (final o in objects) {
    if (o['type'] == 'rectangle') nodeIdToLabel[o['id'] as String] = o['text'] as String? ?? '';
  }

  final endPorts = <String, List<List<double>>>{};
  for (final a in arrows) {
    final endAtt = a['endAttachment'];
    if (endAtt != null) {
      final id = endAtt['objectId'] as String;
      final rp = (endAtt['relativePosition'] as List).cast<double>();
      endPorts.putIfAbsent(id, () => []).add(rp);
    }
  }

  print('End port assignments per target node:');
  for (final entry in endPorts.entries) {
    final label = nodeIdToLabel[entry.key] ?? entry.key.substring(0, 8);
    final ports = entry.value;
    final portStrs = ports.map((p) => '(${p[0].toStringAsFixed(2)},${p[1].toStringAsFixed(2)})').toList();
    final duplicates = portStrs.length != portStrs.toSet().length;
    print('  ${label.padRight(35)}: ${portStrs.join(', ')}${duplicates ? ' <-- DUPLICATES!' : ''}');
  }
}
