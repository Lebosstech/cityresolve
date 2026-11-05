// VISIBLE exploratory CityResolve tests (independent of any confirmatory
// scenario). They publish the real behaviour, including the confirmed limits
// of the classic engine. No scenario is tuned to pass.
// Run: dart run test/test_exploratoire.dart
import '../lib/grouping.dart';
import '../lib/incidents.dart';
import '../lib/optimizer.dart';
import '../lib/oracle.dart';
import '../lib/policy.dart';
import '../lib/scenarios.dart';
import '../lib/simulator.dart';
import '../lib/types.dart';

int _ok = 0, _limit = 0;

void observe(String name, bool ideal, String detail) {
  if (ideal) {
    _ok++;
    print('OK     $name :: $detail');
  } else {
    _limit++;
    print('LIMIT $name :: $detail');
  }
}

const dDist = 250.0, dDt = 6.0, dSim = 0.75;

List<Incident> incsOf(List<Report> reps) {
  final g = groupReports(reps, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
  return aggregate(g, {for (final r in reps) r.id: r});
}

void main() {
  final teams = defaultTeams();

  // E1. Two close incidents, almost identical descriptions.
  {
    final reps = [
      Report(id: 'A1', text: 'fuite eau rue basse trottoir inonde canalisation', category: 'fuite-eau', x: 2.0, y: 2.0, t: 500, severityHint: 3, exposureHint: 1),
      Report(id: 'A2', text: 'fuite eau rue basse trottoir inonde cassee', category: 'fuite-eau', x: 2.05, y: 2.0, t: 520, severityHint: 3, exposureHint: 1),
      Report(id: 'B1', text: 'fuite eau rue basse trottoir inonde importante', category: 'fuite-eau', x: 2.1, y: 2.0, t: 510, severityHint: 2, exposureHint: 1),
    ];
    final g = groupReports(reps, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    // Phase 2 regression: the classic merge remains (done), but it
    // must be FLAGGED uncertain instead of being imposed silently.
    observe('E1 borderline merge flagged uncertain (not imposed silently)',
        g.length == 1 && g.single.uncertain,
        '${g.length} group(s) for 2 true incidents 100 m apart, uncertain=${g.single.uncertain}, reasons=${g.single.uncertaintyReasons}');
  }

  // E2. Same incident, completely different words (synonyms).
  {
    final reps = [
      Report(id: 'A1', text: 'trou chaussee dangereux voitures', category: 'nid-de-poule', x: 1.0, y: 1.0, t: 500, severityHint: 2, exposureHint: 1),
      Report(id: 'A2', text: 'excavation bitume perilleuse automobiles', category: 'nid-de-poule', x: 1.0, y: 1.0, t: 510, severityHint: 2, exposureHint: 1),
    ];
    final g = groupReports(reps, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final amb = ambiguousPairs(reps, g,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    // Phase 2 regression: the classic split remains, but the pair
    // must be flagged ambiguous (same place/time, disjoint vocabulary).
    observe('E2 separation flagged ambiguous (not imposed silently)',
        g.length == 2 && amb.isNotEmpty,
        '${g.length} group(s), Jaccard=${jaccard(reps[0].text, reps[1].text).toStringAsFixed(2)}, ambiguous=${amb.map((a) => a['reason']).toList()}');
  }

  // E3. Incomplete report (empty text, no hint).
  {
    final reps = [
      Report(id: 'V1', text: '', category: 'autre', x: 1.0, y: 1.0, t: 500),
      Report(id: 'V2', text: '', category: 'autre', x: 1.02, y: 1.0, t: 510),
    ];
    final g = groupReports(reps, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final incs = incsOf(reps);
    observe('E3a two empty texts not merged at random', g.length == 2,
        '${g.length} group(s): Jaccard("","")=0.0 (no evidence), no merge without information');
    observe('E3b unknown severity flagged as such',
        incs.every((i) => i.severity == null && i.severityStatus == statusInconnue),
        'incidents sev=${incs.map((i) => i.severity).toList()} statuses=${incs.map((i) => i.severityStatus).toList()} (no category default), unknown exposure, decision E=${incs.first.exposureForDecision}');
    print('       E3 detail: group confidence=${g.first.confidence}, singleton=${g.first.singleton}');
  }

  // E4. Contradictory geographical information (same text, opposite corners).
  {
    final reps = [
      Report(id: 'G1', text: 'nid poule rue basse chaussee trou abimee', category: 'nid-de-poule', x: 0.2, y: 0.2, t: 500, severityHint: 2, exposureHint: 1),
      Report(id: 'G2', text: 'nid poule rue basse chaussee trou abimee', category: 'nid-de-poule', x: 4.8, y: 4.8, t: 505, severityHint: 2, exposureHint: 1),
    ];
    final g = groupReports(reps, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final amb4 = ambiguousPairs(reps, g,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    // Local patch: the separation remains (two real incidents can
    // share a text), but it must be FLAGGED as a distant duplicate
    // to verify, not imposed silently.
    observe('E4 geographical contradiction flagged (separation + alert)',
        g.length == 2 && amb4.isNotEmpty,
        '${g.length} incident(s) for the same text 6.5 km apart, ambiguous=${amb4.map((a) => a['reason']).toList()}');
  }

  // E5. Unknown severity (hint absent, category given).
  {
    final r = Report(id: 'S?', text: 'fuite signalee sans precision', category: 'fuite-eau', x: 2.0, y: 2.0, t: 500);
    final incs = incsOf([r]);
    observe('E5 unknown severity kept (no invented default)',
        incs.single.severity == null && incs.single.severityStatus == statusInconnue,
        'severityHint=null -> severity=${incs.single.severity}, status=${incs.single.severityStatus} (category fuite-eau has no effect on severity)');
  }

  // E6. S5 incident: escalation, never dispatched.
  {
    final sc = toyS5();
    final incs = incsOf(sc.reports);
    final p = optimizeExact(incidents: incs, teams: teams);
    final s5 = incs.firstWhere((i) => i.severity != null && i.severity! >= 5);
    observe('E6 S5 escalated and not dispatched',
        p.escalations.contains(s5.id) && !p.tasks.any((t) => t.incidentId == s5.id),
        'escalations=${p.escalations}, S5 deadline=${s5.deadline} (-1 = escalation)');
  }

  // E7. Feasible as estimated, budget exceeded as realised (DEV seed 7).
  {
    final sc = generateDev(seed: 7);
    final g = groupReports(sc.reports, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final incs = aggregate(g, {for (final r in sc.reports) r.id: r});
    final p = optimizeExact(incidents: incs, teams: teams);
    final sm = simulate(plan: p, proposed: incs, truth: sc.truth, teams: teams);
    observe('E7 realised budget overrun without fully cancelling Q',
        sm.q != 0.0,
        'estimated=${p.totalCost.toStringAsFixed(1)}/$budgetUnits, realised=${sm.totalCost.toStringAsFixed(1)}, Q=${sm.q}, violations=${sm.violations} (Q=0 cliff imposed by SPEC D-SIMU §7 / V1.5 §3, not an isolated bug)');
  }

  // E8. New information without unjustified change (duplicate).
  {
    final sc = toyFixed1();
    final i0 = incsOf(sc.reports);
    final p0 = optimizeExact(incidents: i0, teams: teams);
    final reps = [...sc.reports, Report(id: 'R7', text: 'nid de poule rue des lilas chaussee abimee', category: 'nid-de-poule', x: 1.0, y: 1.0, t: 530, severityHint: 2, exposureHint: 1)];
    final i1 = incsOf(reps);
    final nec = judgeRevision(oldPlan: p0, oldIncidents: i0, updated: i1, teams: teams);
    observe('E8 duplicate without unjustified revision', nec.code == 'U' && !nec.necessary,
        'oracle=${nec.code} (${nec.detail})');
  }

  // E9. Insufficient-content guardrail (pushed to main): two
  // empty texts at the same place and time do not merge, and the
  // empty singleton is flagged to verify instead of being imposed silently.
  {
    final reps = [
      Report(id: 'V1', text: '', category: 'autre', x: 1.0, y: 1.0, t: 500),
      Report(id: 'V2', text: '', category: 'autre', x: 1.0, y: 1.0, t: 510),
      Report(id: 'N1', text: 'nid poule rue lilas chaussee degradee', category: 'nid-de-poule', x: 1.0, y: 1.0, t: 505),
    ];
    final g = groupReports(reps, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final vides = g.where((gr) => gr.reportIds.any((id) => id.startsWith('V')));
    observe('E9 two empty texts not merged and flagged guardrail',
        g.length == 3 &&
            vides.length == 2 &&
            vides.every((gr) =>
                gr.singleton &&
                gr.uncertaintyReasons.contains(guardrailReason)),
        '${g.length} group(s), empty reasons=${vides.map((gr) => gr.uncertaintyReasons).toList()}');
  }

  print('== EXPLORATORY: $_ok OK, $_limit CONFIRMED LIMIT(S) ==');
  print('LIMIT items are measured, published behaviours, not hidden failures.');
}
