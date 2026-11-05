// Visible fictitious DEV scenarios (setup, debugging, selection).
// No hidden confirmatory scenario here. Visible truths.
import 'dart:math';
import 'types.dart';

int _min(int day, int h, int m) => day * 1440 + h * 60 + m;

/// Fixed toy no. 1: 6 reports, 3 incidents (expected values hand-computed).
/// Identical positions per incident (toy). Perfect hints.
Scenario toyFixed1() {
  final reports = [
    Report(
        id: 'R1',
        text: 'nid de poule rue des lilas chaussee abimee',
        category: 'nid-de-poule',
        x: 1.0,
        y: 1.0,
        t: _min(0, 8, 20),
        severityHint: 2,
        exposureHint: 1),
    Report(
        id: 'R2',
        text: 'nid de poule rue des lilas chaussee trou',
        category: 'nid-de-poule',
        x: 1.0,
        y: 1.0,
        t: _min(0, 8, 50),
        severityHint: 2,
        exposureHint: 1),
    Report(
        id: 'R3',
        text: 'fuite eau importante avenue centrale trottoir inonde',
        category: 'fuite-eau',
        x: 3.0,
        y: 3.0,
        t: _min(0, 9, 20),
        severityHint: 3,
        exposureHint: 2),
    Report(
        id: 'R4',
        text: 'fuite eau importante avenue centrale trottoir deborde',
        category: 'fuite-eau',
        x: 3.0,
        y: 3.0,
        t: _min(0, 10, 0),
        severityHint: 3,
        exposureHint: 2),
    Report(
        id: 'R5',
        text: 'branche arbre tombee parc vert chemin bloque',
        category: 'arbre',
        x: 4.0,
        y: 1.0,
        t: _min(0, 10, 40),
        severityHint: 1,
        exposureHint: 0),
    Report(
        id: 'R6',
        text: 'branche arbre tombee parc vert chemin coupe',
        category: 'arbre',
        x: 4.0,
        y: 1.0,
        t: _min(0, 11, 20),
        severityHint: 1,
        exposureHint: 0),
  ];
  final truth = [
    TruthIncident(
        id: 'T-A',
        reportIds: {'R1', 'R2'},
        severity: 2,
        exposure: 1,
        domain: 'voirie',
        x: 1.0,
        y: 1.0,
        firstArrival: _min(0, 8, 20),
        durationMult: 1.0),
    TruthIncident(
        id: 'T-B',
        reportIds: {'R3', 'R4'},
        severity: 3,
        exposure: 2,
        domain: 'reseaux',
        x: 3.0,
        y: 3.0,
        firstArrival: _min(0, 9, 20),
        durationMult: 1.0),
    TruthIncident(
        id: 'T-C',
        reportIds: {'R5', 'R6'},
        severity: 1,
        exposure: 0,
        domain: 'espaces-verts',
        x: 4.0,
        y: 1.0,
        firstArrival: _min(0, 10, 40),
        durationMult: 1.0),
  ];
  return Scenario(
      id: 'jouet-1', label: 'Fixed toy no. 1 (6 reports, 3 inc.)', reports: reports, truth: truth);
}

/// Toy S5: one S5 + one S2, groups separate by construction.
Scenario toyS5() {
  final reports = [
    Report(
        id: 'S1',
        text: 'immeuble effondrement rue du pont personnes piegees urgence',
        category: 'coupure-electrique',
        x: 0.5,
        y: 4.5,
        t: _min(0, 9, 0),
        severityHint: 5,
        exposureHint: 3),
    Report(
        id: 'S2',
        text: 'reverbere eteint allee des tilleuls nuit noire',
        category: 'eclairage',
        x: 4.5,
        y: 0.5,
        t: _min(1, 10, 0),
        severityHint: 2,
        exposureHint: 1),
  ];
  final truth = [
    TruthIncident(
        id: 'T-S5',
        reportIds: {'S1'},
        severity: 5,
        exposure: 3,
        domain: 'reseaux',
        x: 0.5,
        y: 4.5,
        firstArrival: _min(0, 9, 0),
        durationMult: 1.0),
    TruthIncident(
        id: 'T-S2',
        reportIds: {'S2'},
        severity: 2,
        exposure: 1,
        domain: 'voirie',
        x: 4.5,
        y: 0.5,
        firstArrival: _min(1, 10, 0),
        durationMult: 1.0),
  ];
  return Scenario(
      id: 'jouet-s5',
      label: 'Toy S5 (escalation, no dispatch)',
      reports: reports,
      truth: truth);
}

class _Archetype {
  final String category;
  final int severity;
  final int exposure;
  final List<String> variants;
  const _Archetype(this.category, this.severity, this.exposure, this.variants);
}

/// Variants: 6 core words + 1 distinct word => pairwise Jaccard = 6/8.
/// Distinct incidents separated by >1.8 km => perfect grouping guaranteed
/// under the default parameters (250 m, 6 h, 0.75).
const _archetypes = [
  _Archetype('nid-de-poule', 1, 0, [
    'nid poule rue basse chaussee trou abimee',
    'nid poule rue basse chaussee trou dangereux',
    'nid poule rue basse chaussee trou grand',
    'nid poule rue basse chaussee trou signale',
  ]),
  _Archetype('fuite-eau', 3, 2, [
    'fuite eau rue haute trottoir inonde importante',
    'fuite eau rue haute trottoir inonde canalisation',
    'fuite eau rue haute trottoir inonde cassee',
    'fuite eau rue haute trottoir inonde passants',
  ]),
  _Archetype('eclairage', 2, 1, [
    'reverberes eteints avenue nord nuit eclairage insecurite',
    'reverberes eteints avenue nord nuit eclairage panne',
    'reverberes eteints avenue nord nuit eclairage danger',
    'reverberes eteints avenue nord nuit eclairage reparations',
  ]),
  _Archetype('arbre', 2, 1, [
    'branche arbre tombee square est chemin bloque',
    'branche arbre tombee square est chemin violent',
    'branche arbre tombee square est chemin coupe',
    'branche arbre tombee square est chemin promeneurs',
  ]),
  _Archetype('coupure-electrique', 4, 2, [
    'coupure electrique quartier ouest courant immeubles prives',
    'coupure electrique quartier ouest courant immeubles coupe',
    'coupure electrique quartier ouest courant immeubles ascenseurs',
    'coupure electrique quartier ouest courant immeubles generale',
  ]),
  _Archetype('chaussée', 2, 1, [
    'travaux chaussee boulevard sud deviation circulation indiquee',
    'travaux chaussee boulevard sud deviation circulation difficile',
    'travaux chaussee boulevard sud deviation circulation eventree',
    'travaux chaussee boulevard sud deviation circulation dangereuse',
  ]),
  _Archetype('fuite-eau', 2, 1, [
    'fontaine coule place centre eau flaque gaspillee',
    'fontaine coule place centre eau flaque robinet',
    'fontaine coule place centre eau flaque grandit',
    'fontaine coule place centre eau flaque arret',
  ]),
  _Archetype('nid-de-poule', 1, 0, [
    'trottoir degrade impasse moulins dalles soulevees chute',
    'trottoir degrade impasse moulins dalles soulevees pieton',
    'trottoir degrade impasse moulins dalles soulevees manquantes',
    'trottoir degrade impasse moulins dalles soulevees reparation',
  ]),
];

/// Visible DEV generator: 20 reports, 8 incidents (fixed seed).
Scenario generateDev({required int seed}) {
  final rng = Random(seed);
  const sizes = [4, 3, 3, 3, 2, 2, 2, 1];
  const centers = [
    [0.6, 0.6],
    [2.5, 0.7],
    [4.3, 0.8],
    [0.7, 2.5],
    [2.5, 2.5],
    [4.3, 2.6],
    [1.5, 4.3],
    [3.6, 4.2],
  ];
  const firstDays = [0, 1, 2, 0, 3, 1, 4, 2];
  final reports = <Report>[];
  final truth = <TruthIncident>[];
  var n = 0;
  const mults = [1.0, 0.8, 1.25];
  for (var i = 0; i < 8; i++) {
    final a = _archetypes[i];
    final cx = centers[i][0], cy = centers[i][1];
    final day = firstDays[i];
    final t0 = day * 1440 + 8 * 60 + rng.nextInt(120);
    final ids = <String>{};
    var tMin = 1 << 30;
    for (var k = 0; k < sizes[i]; k++) {
      n++;
      final id = 'D$n';
      ids.add(id);
      final unknown = rng.nextDouble() < 0.2;
      final t = t0 + rng.nextInt(240); // ≤ 14:00, service hours
      if (t < tMin) tMin = t;
      reports.add(Report(
        id: id,
        text: a.variants[rng.nextInt(a.variants.length)],
        category: a.category,
        x: (cx + (rng.nextDouble() - 0.5) * 0.12)
            .clamp(0.05, 4.95)
            .toDouble(),
        y: (cy + (rng.nextDouble() - 0.5) * 0.12)
            .clamp(0.05, 4.95)
            .toDouble(),
        t: t,
        severityHint: a.severity,
        exposureHint: unknown ? null : a.exposure,
      ));
    }
    final dom = {
      'nid-de-poule': 'voirie',
      'fuite-eau': 'reseaux',
      'eclairage': 'voirie',
      'arbre': 'espaces-verts',
      'coupure-electrique': 'reseaux',
      'chaussée': 'voirie',
    }[a.category]!;
    truth.add(TruthIncident(
        id: 'V${i + 1}',
        reportIds: ids,
        severity: a.severity,
        exposure: a.exposure,
        domain: dom,
        x: cx,
        y: cy,
        firstArrival: tMin,
        durationMult: mults[i % 3]));
  }
  return Scenario(
      id: 'dev-$seed',
      label: 'Visible DEV seed $seed (20 reports, 8 inc.)',
      reports: reports,
      truth: truth,
      seed: seed);
}
