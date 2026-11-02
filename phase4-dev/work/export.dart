// Exportateur DEV visible uniquement. Aucun scénario confirmatoire caché.
// Sources : lib/scenarios.dart (jouet-1, dev-7) et
// test_exploratoire.dart (E1, E2, copiés verbatim).
// E1 : le code exploratoire dit "2 incidents vrais" mais ne spécifie pas
// la partition. La vérité E1 est donc déclarée non spécifiée, sans invention.
import 'dart:convert';
import 'dart:io';
import 'lib/scenarios.dart';
import 'lib/types.dart';

Map<String, dynamic> scenarioJson(Scenario sc) => {
      'id': sc.id,
      'label': sc.label,
      'seed': sc.seed,
      'reports': sc.reports.map((r) => r.toJson()).toList(),
      'truth': sc.truth.map((t) => t.toJson()).toList(),
      'truth_groups': sc.truth.map((t) => t.reportIds.toList()).toList(),
    };

void main() {
  final jouet = toyFixed1();
  final dev7 = generateDev(seed: 7);
  final e1Reports = [
    Report(id: 'A1', text: 'fuite eau rue basse trottoir inonde canalisation', category: 'fuite-eau', x: 2.0, y: 2.0, t: 500, severityHint: 3, exposureHint: 1),
    Report(id: 'A2', text: 'fuite eau rue basse trottoir inonde cassee', category: 'fuite-eau', x: 2.05, y: 2.0, t: 520, severityHint: 3, exposureHint: 1),
    Report(id: 'B1', text: 'fuite eau rue basse trottoir inonde importante', category: 'fuite-eau', x: 2.1, y: 2.0, t: 510, severityHint: 2, exposureHint: 1),
  ];
  final e2Reports = [
    Report(id: 'A1', text: 'trou chaussee dangereux voitures', category: 'nid-de-poule', x: 1.0, y: 1.0, t: 500, severityHint: 2, exposureHint: 1),
    Report(id: 'A2', text: 'excavation bitume perilleuse automobiles', category: 'nid-de-poule', x: 1.0, y: 1.0, t: 510, severityHint: 2, exposureHint: 1),
  ];
  final out = {
    'source': 'Dart visible uniquement : scenarios.dart + test_exploratoire.dart (E1/E2)',
    'note': 'Aucune donnée inventée. E1 truth_groups = null car la partition n est pas spécifiée dans le code.',
    'scenarios': [
      scenarioJson(jouet),
      scenarioJson(dev7),
      {
        'id': 'e1-diagnostic',
        'label': 'E1 exploratoire (3 sign., fusion limite)',
        'seed': null,
        'reports': e1Reports.map((r) => r.toJson()).toList(),
        'truth': null,
        'truth_groups': null,
        'truth_note': '2 incidents vrais mentionnés, partition non spécifiée dans le code : pas de F1 pour E1.',
      },
      {
        'id': 'e2-synonymes',
        'label': 'E2 exploratoire (2 sign., même incident, vocabulaire disjoint)',
        'seed': null,
        'reports': e2Reports.map((r) => r.toJson()).toList(),
        'truth': [
          {'id': 'T-E2', 'reportIds': ['A1', 'A2'], 'severity': 2, 'exposure': 1, 'domain': 'voirie', 'x': 1.0, 'y': 1.0, 'firstArrival': 500, 'durationMult': 1.0}
        ],
        'truth_groups': [['A1', 'A2']],
        'truth_note': 'Un seul incident vrai, d après le commentaire du code exploratoire (même incident, mots différents).',
      },
    ],
  };
  File('data/scenarios.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(out));
  print('scenarios: jouet-1=${jouet.reports.length} reports, ${jouet.truth.length} truth; '
      'dev-7=${dev7.reports.length} reports, ${dev7.truth.length} truth; '
      'e1=${e1Reports.length}; e2=${e2Reports.length}');
}
