import 'dart:convert';
import 'lib/grouping.dart';
import 'lib/scenarios.dart';
import 'lib/types.dart';
void main() {
  final scs = [toyFixed1(), generateDev(seed: 7)];
  for (final sc in scs) {
    final g = groupReports(sc.reports, distMaxM: 250, deltaTMaxH: 6, simMin: 0.75);
    print('${sc.id} ${jsonEncode(g.map((x) => x.reportIds).toList())}');
  }
  final e2 = [
    Report(id: 'A1', text: 'trou chaussee dangereux voitures', category: 'nid-de-poule', x: 1.0, y: 1.0, t: 500, severityHint: 2, exposureHint: 1),
    Report(id: 'A2', text: 'excavation bitume perilleuse automobiles', category: 'nid-de-poule', x: 1.0, y: 1.0, t: 510, severityHint: 2, exposureHint: 1),
  ];
  final g2 = groupReports(e2, distMaxM: 250, deltaTMaxH: 6, simMin: 0.75);
  print('e2 ${jsonEncode(g2.map((x) => x.reportIds).toList())} amb=${jsonEncode(ambiguousPairs(e2, g2, distMaxM: 250, deltaTMaxH: 6, simMin: 0.75))}');
}
