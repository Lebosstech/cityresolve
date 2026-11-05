// CityResolve DEV tests: real execution, expected values computed by
// hand (see comments). Zero dependencies: `dart run test/test_all.dart`.
// Non-zero exit code if a test fails.
import 'dart:convert';
import 'dart:io';

import '../lib/audit.dart';
import '../lib/dashboard.dart';
import '../lib/grouping.dart';
import '../lib/incidents.dart';
import '../lib/media.dart';
import '../lib/meta_connector.dart';
import '../lib/metrics.dart';
import '../lib/optimizer.dart';
import '../lib/oracle.dart';
import '../lib/scenarios.dart';
import '../lib/security.dart';
import '../lib/server_lock.dart';
import '../lib/simulator.dart';
import '../lib/store.dart';
import '../lib/types.dart';

int _pass = 0, _fail = 0;

void check(bool cond, String name, [String detail = '']) {
  if (cond) {
    _pass++;
    print('PASS $name');
  } else {
    _fail++;
    print('FAIL $name :: $detail');
  }
}

bool approx(double a, double b, [double e = 1e-6]) =>
    (a - b).abs() <= e;

const double dDist = 250.0, dDt = 6.0, dSim = 0.75;

Future<void> main() async {
  final teams = defaultTeams();

  // 1. Two reports of the same incident -> same group.
  {
    final sc = toyFixed1();
    final g = groupReports(sc.reports,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final gR1 =
        g.firstWhere((x) => x.reportIds.contains('R1')).reportIds.toSet();
    check(gR1.contains('R2'), 'T1 same incident grouped', gR1.toString());
  }

  // 2. Close but different incidents -> separate groups.
  {
    final sc = toyFixed1();
    final g = groupReports(sc.reports,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(g.length == 3, 'T2a 3 groups jouet-1', '${g.length}');
    // Same place/time, disjoint vocabularies (Jaccard 1/13 < 0.75).
    final reps = [
      Report(
          id: 'A',
          text: 'nid poule rue basse chaussee trou abimee',
          category: 'nid-de-poule',
          x: 2.0,
          y: 2.0,
          t: 500),
      Report(
          id: 'B',
          text: 'fuite eau rue haute canalisation cassee enorme',
          category: 'fuite-eau',
          x: 2.0,
          y: 2.0,
          t: 500),
    ];
    final g2 = groupReports(reps,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(g2.length == 2, 'T2b disjoint vocabularies separated',
        '${g2.length}');
  }

  // 3. Unknown exposure: kept, decision E=4, consistent weight.
  {
    final r = Report(
        id: 'R',
        text: 'trou chaussee rue principale danger',
        category: 'autre',
        x: 1.0,
        y: 1.0,
        t: 500,
        severityHint: 2);
    final incs = aggregate(
        [Group(id: 'G1', reportIds: ['R'], confidence: 0, singleton: true)],
        {'R': r});
    final i = incs.single;
    // By hand: w = 0.65*(2/4) + 0.35*(4/4) = 0.325 + 0.35 = 0.675.
    check(i.exposure == null && i.exposureUnknown, 'T3a unknown kept');
    check(i.exposureForDecision == 4, 'T3b decision E=4');
    check(approx(i.weight, 0.675), 'T3c weight = 0.675', '${i.weight}');
  }

  // 4. No competent team -> explicit reason.
  {
    final incs = [
      Incident(
          id: 'IX',
          reportIds: ['R'],
          severity: 3,
          exposure: 1,
          domain: 'reseaux',
          x: 1.0,
          y: 1.0,
          firstSeen: 500,
          confidence: 1.0)
    ];
    final t2 = [Team('t1', {'voirie'}), Team('t2', {'espaces-verts'})];
    final p = optimizeExact(incidents: incs, teams: t2);
    check(
        p.tasks.isEmpty &&
            (p.unassigned['IX'] ?? '').contains('no competent team'),
        'T4 no competent team',
        p.unassigned.toString());
  }

  // 5. Insufficient budget: optimiser respects it, simulator sanctions with Q=0.
  {
    final reps = [
      for (var k = 0; k < 4; k++)
        Report(
            id: 'B$k',
            text: 'fuite majeure secteur $k canalisation rompue urgence',
            category: 'fuite-eau',
            x: k < 2 ? 0.5 : 4.5,
            y: k % 2 == 0 ? 0.5 : 4.5,
            t: 500,
            severityHint: 3,
            exposureHint: 1),
    ];
    final truth = [
      for (var k = 0; k < 4; k++)
        TruthIncident(
            id: 'TB$k',
            reportIds: {'B$k'},
            severity: 3,
            exposure: 1,
            domain: 'reseaux',
            x: k < 2 ? 0.5 : 4.5,
            y: k % 2 == 0 ? 0.5 : 4.5,
            firstArrival: 500,
            durationMult: 1.0),
    ];
    final g = groupReports(reps,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final byId = {for (final r in reps) r.id: r};
    final incs = aggregate(g, byId);
    final po = optimizeExact(incidents: incs, teams: teams);
    check(po.totalCost <= 120.0, 'T5a optimiser respects budget',
        '${po.totalCost}');
    // Forced manual plan: everything on equipe-2 (4x40 site = 160 > 120).
    final forced = Plan(
        tasks: [
          for (var k = 0; k < incs.length; k++)
            Task(
                incidentId: incs[k].id,
                teamId: 'equipe-2',
                order: k + 1,
                startMin: 0,
                endMin: 0,
                travelKm: 0,
                cost: 0),
        ],
        unassigned: {},
        escalations: [],
        totalCost: 0,
        q: 0,
        feasible: true,
        violations: [],
        justifications: {});
    final sm =
        simulate(plan: forced, proposed: incs, truth: truth, teams: teams);
    check(!sm.feasible && sm.q == 0.0, 'T5b violation => Q=0',
        'q=${sm.q} v=${sm.violations}');
    check(sm.violations.any((v) => v.startsWith('budget exceeded')),
        'T5c budget reason', sm.violations.toString());
  }

  // 6. Deadline exceeded -> unassigned with reason.
  {
    final r = Report(
        id: 'L',
        text: 'coupure electrique immeuble ascenseur bloque soir',
        category: 'coupure-electrique',
        x: 4.5,
        y: 4.5,
        t: 9540, // D6 15:00, S4 => deadline D6 19:00, end of service 16:00
        severityHint: 4,
        exposureHint: 1);
    final incs = aggregate(
        [Group(id: 'G1', reportIds: ['L'], confidence: 0, singleton: true)],
        {'L': r});
    final p = optimizeExact(incidents: incs, teams: teams);
    check(
        p.tasks.isEmpty &&
            (p.unassigned['I1'] ?? '').contains('deadline unreachable'),
        'T6 deadline unreachable',
        p.unassigned.toString());
  }

  // 7. S5 excluded from automatic dispatch, escalated.
  {
    final sc = toyS5();
    final g = groupReports(sc.reports,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(g.length == 2, 'T7a 2 groups', '${g.length}');
    final byId = {for (final r in sc.reports) r.id: r};
    final incs = aggregate(g, byId);
    final p = optimizeExact(incidents: incs, teams: teams);
    final s5 = incs.firstWhere((i) => i.severity != null && i.severity! >= 5);
    check(p.escalations.contains(s5.id), 'T7b S5 escalated',
        p.escalations.toString());
    check(!p.tasks.any((t) => t.incidentId == s5.id),
        'T7c S5 never dispatched');
    check(approx(p.q, 100.0), 'T7d Q=100 on remaining S2', '${p.q}');
  }

  // 8. New information changing a decision (equipe-1 outage).
  {
    final sc = toyFixed1();
    final byId = {for (final r in sc.reports) r.id: r};
    final g = groupReports(sc.reports,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final incs = aggregate(g, byId);
    final p0 = optimizeExact(incidents: incs, teams: teams);
    final t2only = [teams[1]];
    final nec = judgeRevision(
        oldPlan: p0, oldIncidents: incs, updated: incs, teams: t2only);
    check(nec.code == 'N1' && nec.necessary, 'T8a N1 team down',
        nec.code);
    final p1 = optimizeExact(incidents: incs, teams: t2only);
    // By hand: A+B completed, C (EV) impossible : Q = 100*(0.4125+0.6625)/1.2375.
    check(approx(p1.q, 86.8687, 0.01), 'T8b Q=86.87', '${p1.q}');
    final cInc = incs.firstWhere((i) => i.domain == 'espaces-verts');
    check((p1.unassigned[cInc.id] ?? '').contains('no competent team'),
        'T8c C unassigned', p1.unassigned.toString());
  }

  // 9. New information requiring no change (duplicate).
  {
    final sc = toyFixed1();
    final byId = {for (final r in sc.reports) r.id: r};
    final g0 = groupReports(sc.reports,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final i0 = aggregate(g0, byId);
    final p0 = optimizeExact(incidents: i0, teams: teams);
    final dup = Report(
        id: 'R7',
        text: 'nid de poule rue des lilas chaussee abimee',
        category: 'nid-de-poule',
        x: 1.0,
        y: 1.0,
        t: 530,
        severityHint: 2,
        exposureHint: 1);
    final reps = [...sc.reports, dup];
    final byId2 = {for (final r in reps) r.id: r};
    final g1 = groupReports(reps,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final i1 = aggregate(g1, byId2);
    final nec = judgeRevision(
        oldPlan: p0, oldIncidents: i0, updated: i1, teams: teams);
    check(nec.code == 'U' && !nec.necessary, 'T9 stability U', nec.code);
  }

  // 10. Reproducibility with identical seed.
  {
    final a = generateDev(seed: 7);
    final b = generateDev(seed: 7);
    final ja = jsonEncode(a.reports.map((r) => r.toJson()).toList());
    final jb = jsonEncode(b.reports.map((r) => r.toJson()).toList());
    check(ja == jb, 'T10a identical scenario');
    Plan planOf(Scenario s) {
      final byId = {for (final r in s.reports) r.id: r};
      final gg = groupReports(s.reports,
          distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
      return optimizeExact(
          incidents: aggregate(gg, byId), teams: teams);
    }

    check(jsonEncode(planOf(a).toJson()) == jsonEncode(planOf(b).toJson()),
        'T10b identical plan');
  }

  // 11. Jouet-1: F1=1 (TP=3), plan Q=100, cost=92, sim Q=100, B-cubed=1.
  {
    final sc = toyFixed1();
    final g = groupReports(sc.reports,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final byId = {for (final r in sc.reports) r.id: r};
    final incs = aggregate(g, byId);
    final prf = pairwiseF1(
        sc.truth.map((t) => t.reportIds).toList(),
        g.map((x) => x.reportIds).toList());
    check(prf.tp == 3 && prf.fp == 0 && prf.fn == 0 && prf.f1 == 1.0,
        'T11a F1=1 (3/0/0)', prf.toJson().toString());
    final p = optimizeExact(incidents: incs, teams: teams);
    // By hand: T1 A(24)+C(16), T2 B(52) => 92; everything completed => Q=100.
    check(approx(p.q, 100.0), 'T11b plan Q=100', '${p.q}');
    check(approx(p.totalCost, 92.0), 'T11c cost=92', '${p.totalCost}');
    check(p.tasks.length == 3, 'T11d 3 tasks', '${p.tasks.length}');
    final sm =
        simulate(plan: p, proposed: incs, truth: sc.truth, teams: teams);
    check(sm.feasible && approx(sm.q ?? -1, 100.0), 'T11e simulated Q=100',
        'q=${sm.q} v=${sm.violations}');
    check(
        sm.outcomes.every((o) => o.result == 1), 'T11f R=1 everywhere');
    final trueOf = <String, int>{};
    for (var i = 0; i < sc.truth.length; i++) {
      for (final id in sc.truth[i].reportIds) {
        trueOf[id] = i;
      }
    }
    final predOf = <String, int>{};
    for (var i = 0; i < g.length; i++) {
      for (final id in g[i].reportIds) {
        predOf[id] = i;
      }
    }
    check(bCubedF1(trueOf, predOf) == 1.0, 'T11g B-cubed=1');
    check(macroF1([prf]) == 1.0 && microF1([prf]).f1 == 1.0,
        'T11h macro/micro=1');
  }

  // 12. Generated: perfect grouping by construction (seeds 7, 42).
  {
    for (final seed in [7, 42]) {
      final sc = generateDev(seed: seed);
      check(sc.reports.length == 20 && sc.truth.length == 8,
          'T12a 20/8 seed $seed');
      final g = groupReports(sc.reports,
          distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
      final prf = pairwiseF1(
          sc.truth.map((t) => t.reportIds).toList(),
          g.map((x) => x.reportIds).toList());
      check(prf.f1 == 1.0, 'T12b F1=1 seed $seed', prf.toJson().toString());
      final byId = {for (final r in sc.reports) r.id: r};
      final incs = aggregate(g, byId);
      final p = optimizeExact(incidents: incs, teams: teams);
      check(p.totalCost <= 120.0, 'T12c budget seed $seed',
          '${p.totalCost}');
      final sm =
          simulate(plan: p, proposed: incs, truth: sc.truth, teams: teams);
      check(sm.q != null, 'T12d Q defined seed $seed', '${sm.q}');
    }
  }

  // 13. Meta connector: disabled by default, never simulated.
  {
    final c = MetaConnector.fromEnvironment({});
    check(c.state == MetaState.unconfigured, 'T13a unconfigured');
    var threw = false;
    try {
      groupWithMeta(c, []);
    } catch (_) {
      threw = true;
    }
    check(threw, 'T13b refused with no simulated call');
  }

  // 14. Manual report outside ground truth: no impurity, no phantom violation.
  {
    final sc = toyFixed1();
    final g = groupReports(sc.reports,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final byId = {for (final r in sc.reports) r.id: r};
    final incs = aggregate(g, byId);
    final a = incs.firstWhere((i) => i.reportIds.contains('R1'));
    final withManual = Incident(
        id: a.id,
        reportIds: [...a.reportIds, 'M999'],
        severity: a.severity,
        exposure: a.exposure,
        domain: a.domain,
        x: a.x,
        y: a.y,
        firstSeen: a.firstSeen,
        confidence: a.confidence);
    final plan = Plan(
        tasks: [
          Task(
              incidentId: a.id,
              teamId: 'equipe-1',
              order: 1,
              startMin: 0,
              endMin: 0,
              travelKm: 0,
              cost: 0)
        ],
        unassigned: {},
        escalations: [],
        totalCost: 0,
        q: 0,
        feasible: true,
        violations: [],
        justifications: {});
    final sm = simulate(
        plan: plan, proposed: [withManual], truth: sc.truth, teams: teams);
    check(sm.outcomes.single.result == 1 && sm.violations.isEmpty,
        'T14a manual merged, not impure', sm.outcomes.single.reason);
    const manualOnly = Incident(
        id: 'IX',
        reportIds: ['M999'],
        severity: 1,
        exposure: null,
        domain: 'voirie',
        x: 1.0,
        y: 1.0,
        firstSeen: 500,
        confidence: 0);
    final plan2 = Plan(
        tasks: [
          Task(
              incidentId: 'IX',
              teamId: 'equipe-1',
              order: 1,
              startMin: 0,
              endMin: 0,
              travelKm: 0,
              cost: 0)
        ],
        unassigned: {},
        escalations: [],
        totalCost: 0,
        q: 0,
        feasible: true,
        violations: [],
        justifications: {});
    final sm2 = simulate(
        plan: plan2, proposed: [manualOnly], truth: sc.truth, teams: teams);
    check(
        sm2.violations.isEmpty &&
            sm2.outcomes.single.reason.contains('outside ground truth'),
        'T14b manual alone unscored, no violation',
        '${sm2.violations} ${sm2.outcomes.single.reason}');
  }

  // 14c. Empty texts: no invented similarity.
  check(jaccard('', '') == 0.0 && jaccard('', 'trou chaussee') == 0.0,
      'T14c empty Jaccard = 0');

  // 15. Journal: resume after restart (JSONL file).
  {
    final dir = Directory.systemTemp.createTempSync('cityresolve_audit');
    final path = '${dir.path}/journal.jsonl';
    AuditLog(path: path).append('test.un', {'n': 1});
    final resumed = AuditLog(path: path);
    check(resumed.entries.length == 1, 'T15a journal re-read', '${resumed.entries.length}');
    resumed.append('test.deux', {'n': 2});
    check(resumed.entries.last['seq'] == 2, 'T15b sequence continues',
        '${resumed.entries.last['seq']}');
    dir.deleteSync(recursive: true);
  }

  // 16. Q-cliff case, DEV seed 7 (step D): estimated 118.4 -> realised 142.2.
  {
    final sc = generateDev(seed: 7);
    final g = groupReports(sc.reports,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final byId = {for (final r in sc.reports) r.id: r};
    final incs = aggregate(g, byId);
    final p = optimizeExact(incidents: incs, teams: teams);
    check(approx(p.totalCost, 118.4047, 0.01), 'T16a estimated cost 118.4',
        '${p.totalCost}');
    final sm =
        simulate(plan: p, proposed: incs, truth: sc.truth, teams: teams);
    check(approx(sm.totalCost, 142.2, 0.01), 'T16b realised cost 142.2',
        '${sm.totalCost}');
    check(!sm.feasible && sm.q == 0.0, 'T16c Q cliff = 0 (policy)',
        'q=${sm.q} v=${sm.violations}');
  }

  // 17. Meta without key: explicit refusals, no simulated result.
  {
    final c = MetaConnector.fromEnvironment({});
    check(c.state == MetaState.unconfigured, 'T17a unconfigured without key');
    var refused = 0;
    try {
      await extractStructuredWithMeta(
          c, Report(id: 'X', text: 'trou', category: 'autre', x: 1, y: 1, t: 1));
    } on MetaException {
      refused++;
    }
    try {
      await proposeMatchingWithMeta(c, []);
    } on MetaException {
      refused++;
    }
    check(refused == 2, 'T17b extraction+matching refused', '$refused/2');
    final (vc, rec) = await c.verify();
    check(vc.state == MetaState.unconfigured && rec.status == 'refuse',
        'T17c verify without key = refusal logged', rec.status);
  }

  // 18. Local persistence: round-trip, .bak rotation, recovery.
  {
    final dir = Directory.systemTemp.createTempSync('cityresolve_store');
    final store = JsonStore(dir.path);
    store.save({'format': 1, 'reportSeq': 101});
    var load = store.load();
    check(load.doc?['reportSeq'] == 101, 'T18a state re-read', '${load.doc}');
    store.save({'format': 1, 'reportSeq': 102});
    File('${dir.path}/state.json').writeAsStringSync('{corrompu');
    load = store.load();
    check(load.recoveredFromBackup && load.doc?['reportSeq'] == 101,
        'T18b .bak recovery after corruption', '${load.doc}');
    dir.deleteSync(recursive: true);
  }

  // 19. Unknown/contradictory severity: kept, never dispatched.
  {
    final r = Report(
        id: 'U1', text: 'fuite signalee', category: 'fuite-eau', x: 1, y: 1, t: 500);
    final incs = aggregate(
        [Group(id: 'G1', reportIds: ['U1'], confidence: 0, singleton: true)],
        {'U1': r});
    final i = incs.single;
    check(i.severity == null && i.severityStatus == statusInconnue,
        'T19a unknown severity kept (no category default)',
        'sev=${i.severity} status=${i.severityStatus}');
    check(i.deadline == -2, 'T19b no deadline invented', '${i.deadline}');
    final p = optimizeExact(incidents: incs, teams: teams);
    check(p.tasks.isEmpty && (p.unassigned[i.id] ?? '').contains('unknown severity'),
        'T19c unknown not dispatched', p.unassigned.toString());
    check(p.escalations.isEmpty, 'T19d unknown not escalated S5');
    final reps = [
      Report(id: 'C1', text: 'a', category: 'autre', x: 1, y: 1, t: 500, severityHint: 1),
      Report(id: 'C2', text: 'b', category: 'autre', x: 1, y: 1, t: 510, severityHint: 4),
    ];
    final cIncs = aggregate([
      Group(id: 'G1', reportIds: ['C1', 'C2'], confidence: 0.5, singleton: false)
    ], {for (final x in reps) x.id: x});
    check(
        cIncs.single.severity == null &&
            cIncs.single.severityStatus == statusContradictoire &&
            cIncs.single.severityValues.length == 2,
        'T19e explicit contradiction not erased',
        '${cIncs.single.severityStatus} ${cIncs.single.severityValues}');
    final eReps = [
      Report(id: 'E1', text: 'a', category: 'autre', x: 1, y: 1, t: 500, severityHint: 2),
      Report(id: 'E2', text: 'b', category: 'autre', x: 1, y: 1, t: 510, severityHint: 3),
    ];
    final eIncs = aggregate([
      Group(id: 'G1', reportIds: ['E1', 'E2'], confidence: 0.5, singleton: false)
    ], {for (final x in eReps) x.id: x});
    check(eIncs.single.severity == 3 && eIncs.single.severityStatus == statusEstimee,
        'T19f close values = estimated (max)', '${eIncs.single.severityStatus}');
  }

  // 20. Uncertain groupings flagged (E1/E2 regressions).
  {
    final e1 = [
      Report(id: 'A1', text: 'fuite eau rue basse trottoir inonde canalisation', category: 'fuite-eau', x: 2.0, y: 2.0, t: 500, severityHint: 3, exposureHint: 1),
      Report(id: 'A2', text: 'fuite eau rue basse trottoir inonde cassee', category: 'fuite-eau', x: 2.05, y: 2.0, t: 520, severityHint: 3, exposureHint: 1),
      Report(id: 'B1', text: 'fuite eau rue basse trottoir inonde importante', category: 'fuite-eau', x: 2.1, y: 2.0, t: 510, severityHint: 2, exposureHint: 1),
    ];
    final g1 = groupReports(e1, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(g1.length == 1 && g1.single.uncertain,
        'T20a borderline merge E1 flagged uncertain',
        '${g1.length} groupe, raisons=${g1.single.uncertaintyReasons}');
    final e2 = [
      Report(id: 'A1', text: 'trou chaussee dangereux voitures', category: 'nid-de-poule', x: 1.0, y: 1.0, t: 500, severityHint: 2, exposureHint: 1),
      Report(id: 'A2', text: 'excavation bitume perilleuse automobiles', category: 'nid-de-poule', x: 1.0, y: 1.0, t: 510, severityHint: 2, exposureHint: 1),
    ];
    final g2 = groupReports(e2, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final amb = ambiguousPairs(e2, g2,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(g2.length == 2 && amb.any((a) => a['a'] == 'A1' && a['b'] == 'A2'),
        'T20b separation E2 flagged ambiguous', '$amb');
  }

  // 21. Meta connector against a LOCAL test HTTP stub (plumbing,
  // not a Meta result): verification, extraction, timeout, bad key.
  {
    final stub = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sub = stub.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      req.response.headers.contentType = ContentType.json;
      if (req.headers.value('authorization') != 'Bearer test-key' &&
          req.headers.value('authorization') != 'Bearer empty-key') {
        req.response.statusCode = 401;
        req.response.write('{"error":"bad key"}');
      } else if (req.uri.path == '/v1/models') {
        if (req.headers.value('authorization') == 'Bearer empty-key') {
          req.response.write(jsonEncode({'data': []}));
        } else {
          req.response.write(jsonEncode({
            'data': [
              {'id': 'Llama-Test-1'}
            ]
          }));
        }
      } else if (body.contains('LENT')) {
        await Future.delayed(const Duration(seconds: 2));
        req.response.write('{}');
      } else if (body.contains('groupes') || body.contains('regroupement') || body.contains('Rapprochement')) {
        req.response.write(jsonEncode({
          'completion_message': {
            'content': {
              'text': jsonEncode({
                'groupes': [
                  {
                    'reportIds': ['R1', 'R2'],
                    'justification': 'local test stub',
                    'incertitude': 0.1
                  }
                ]
              })
            }
          },
          'usage': {'total_tokens': 42}
        }));
      } else {
        req.response.write(jsonEncode({
          'completion_message': {
            'content': {
              'text': jsonEncode({
                'probleme': 'stub',
                'description': 'local test stub',
                'localisationMentionnee': null,
                'graviteExprimee': null,
                'expositionMentionnee': null,
                'incertitudes': ['severity not expressed'],
                'elementsNonVerifies': []
              })
            }
          },
          'usage': {'total_tokens': 10}
        }));
      }
      await req.response.close();
    });
    final env = {
      'LLAMA_API_KEY': 'test-key',
      'CITYRESOLVE_META_BASE_URL': 'http://127.0.0.1:${stub.port}/v1',
    };
    final connector = MetaConnector.fromEnvironment(env);
    final (vc, vrec) = await connector.verify();
    check(vc.state == MetaState.verified && vc.models.contains('Llama-Test-1'),
        'T21a verify stub -> real models from the response', '${vc.models}');
    check(vrec.status == 'ok' && vrec.latencyMs >= 0, 'T21b call logged');
    final rep = Report(
        id: 'R1', text: 'trou rue basse', category: 'autre', x: 1, y: 1, t: 500);
    final ext = await extractStructuredWithMeta(vc, rep);
    check(ext['graviteExprimee'] == null && (ext['incertitudes'] as List).isNotEmpty,
        'T21c extraction parsed, uncertainty kept', '$ext');
    final reps = [
      rep,
      Report(id: 'R2', text: 'trou rue basse bis', category: 'autre', x: 1, y: 1, t: 510),
    ];
    final mg = await proposeMatchingWithMeta(vc, reps);
    check(mg.length == 1 && mg.single.method == 'meta' && mg.single.reportIds.length == 2,
        'T21d matching -> Group method=meta', '${mg.map((g) => g.toJson())}');
    var timeoutSeen = false;
    try {
      await extractStructuredWithMeta(
          vc,
          Report(id: 'LENT', text: 'LENT', category: 'autre', x: 1, y: 1, t: 1),
          timeout: const Duration(milliseconds: 200));
    } on MetaException {
      timeoutSeen = true;
    }
    check(timeoutSeen, 'T21e timeout -> explicit MetaException');
    final bad = MetaConnector.fromEnvironment(
        {...env, 'LLAMA_API_KEY': 'wrong-key'});
    final (bc, _) = await bad.verify();
    check(bc.state == MetaState.accessError, 'T21f bad key -> access error');
    final empty = MetaConnector.fromEnvironment(
        {...env, 'LLAMA_API_KEY': 'empty-key'});
    final (ec, _) = await empty.verify();
    check(ec.state == MetaState.accessError && ec.models.isEmpty,
        'T21g key accepted but 0 authorised models -> access unavailable');
    await sub.cancel();
    await stub.close(force: true);
  }

  // 22. Meta Model API official provider regression.
  {
    final def = MetaConnector.fromEnvironment({});
    check(def.baseUrl == 'https://api.meta.ai/v1',
        'T22a official api.meta.ai base by default', def.baseUrl);
    check(def.baseUrl != 'https://api.llama.com/v1',
        'T22b old llama.com domain not used');
    final primary = MetaConnector.fromEnvironment({
      'MODEL_API_KEY': 'cle-primaire',
      'LLAMA_API_KEY': 'cle-legacy',
    });
    check(primary.keySource == 'MODEL_API_KEY',
        'T22c MODEL_API_KEY takes priority over alias', '${primary.keySource}');
    final alias = MetaConnector.fromEnvironment({'LLAMA_API_KEY': 'cle-legacy'});
    check(alias.keySource == 'LLAMA_API_KEY',
        'T22d explicit legacy alias as fallback', '${alias.keySource}');
    check(
        metaHttpErrorLabel(401).contains('authentication refused') &&
            metaHttpErrorLabel(402).contains('payment/billing required') &&
            metaHttpErrorLabel(403).contains('insufficient authorization') &&
            metaHttpErrorLabel(404).contains('resource or model not found') &&
            metaHttpErrorLabel(429).contains('rate limit exceeded') &&
            metaHttpErrorLabel(503).contains('temporary service error'),
        'T22e HTTP errors distinguished');
  }

  // 23. Single-instance lock (local patch): second server refused.
  {
    final tmp = Directory.systemTemp.createTempSync('cityresolve-lock-');
    try {
      final first = tryAcquireServerLock(tmp.path);
      check(first.acquired, 'T23a first server acquires the lock');
      final second = tryAcquireServerLock(tmp.path);
      check(!second.acquired && second.holderPid == pid,
          'T23b second server refused, first PID reported',
          'holderPid=${second.holderPid}');
      releaseServerLock(first.path);
      final third = tryAcquireServerLock(tmp.path);
      check(third.acquired, 'T23c lock released then re-acquired');
      releaseServerLock(third.path);
    } finally {
      tmp.deleteSync(recursive: true);
    }
  }

  // 24. Insufficient-content guardrail (pushed to main).
  {
    Report rep(String id, String text) => Report(
        id: id, text: text, category: 'autre', x: 1.0, y: 1.0, t: 500);
    // T24a : two empty texts do not merge.
    final gVide = groupReports([rep('V1', ''), rep('V2', '')],
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(gVide.length == 2 && gVide.every((g) => g.singleton),
        'T24a two empty texts do not merge', gVide.toString());
    check(gVide.every((g) =>
        g.uncertain && g.uncertaintyReasons.contains(guardrailReason)),
        'T24a-bis empty singletons flagged guardrail',
        gVide.map((g) => g.uncertaintyReasons).toString());
    // T24b: empty text vs non-empty text does not merge.
    final gMix = groupReports(
        [rep('V1', ''), rep('N1', 'nid poule rue lilas chaussee degradee')],
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(gMix.length == 2 && gMix.every((g) => g.singleton),
        'T24b empty vs non-empty does not merge', gMix.toString());
    // T24c: a single character does not merge (even identical on both sides).
    final gChar = groupReports([rep('C1', 'a'), rep('C2', 'a')],
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(gChar.length == 2 && gChar.every((g) => g.singleton),
        'T24c a single character does not merge', gChar.toString());
    // T24d: punctuation/spaces alone do not merge.
    final gPonct = groupReports([rep('P1', '!!!'), rep('P2', '   ')],
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(gPonct.length == 2 && gPonct.every((g) => g.singleton),
        'T24d punctuation alone does not merge', gPonct.toString());
    // T24e: normal text unaffected (two identical normal texts merge).
    final gNorm = groupReports(
        [
          rep('N1', 'nid poule rue lilas chaussee degradee'),
          rep('N2', 'nid poule rue lilas chaussee degradee')
        ],
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(gNorm.length == 1 && !gNorm.single.singleton,
        'T24e normal text unaffected', gNorm.toString());
    // T24f: the post-model filter cancels a merge proposed by a
    // model (inc-empty case of phase4-hard: two empty ones merged).
    final fakeMeta = [
      Group(
          id: 'G1',
          reportIds: ['V1', 'V2'],
          confidence: 0.0,
          singleton: false,
          method: 'meta',
          uncertain: true,
          uncertaintyReasons: ['model uncertainty 1.00'],
          justification: 'no positive evidence'),
      Group(
          id: 'G2',
          reportIds: ['N1'],
          confidence: 0.0,
          singleton: true,
          method: 'meta'),
    ];
    final filtered = applyContentGuardrail(
        [rep('V1', ''), rep('V2', ''), rep('N1', 'nid poule rue lilas')],
        fakeMeta);
    check(filtered.cancelledMerges == 1,
        'T24f one cancelled merge counted', '${filtered.cancelledMerges}');
    check(filtered.groups.length == 3 &&
        filtered.groups.every((g) => g.singleton),
        'T24f cancelled merge -> 3 singletons', filtered.groups.toString());
    check(filtered.groups
            .where((g) => g.reportIds.first.startsWith('V'))
            .every((g) => g.uncertaintyReasons.contains(guardrailReason)),
        'T24f cancelled singletons flagged guardrail',
        filtered.groups.map((g) => g.uncertaintyReasons).toString());
    // T24g : the filtre does not touch a normal group.
    final kept = applyContentGuardrail(
        [
          rep('N1', 'nid poule rue lilas chaussee degradee'),
          rep('N2', 'nid poule rue lilas chaussee degradee')
        ],
        [
          Group(
              id: 'G1',
              reportIds: ['N1', 'N2'],
              confidence: 0.9,
              singleton: false,
              method: 'meta',
              justification: 'same pothole')
        ]);
    check(kept.cancelledMerges == 0 && kept.groups.length == 1,
        'T24g normal group kept', kept.groups.toString());
  }

  // 25. Units / statuses / time-gate patch (pushed to main).
  {
    Report repCat(String id, String text, String category, double x,
            double y, int t,
            {int? sev, int? exp}) =>
        Report(
            id: id,
            text: text,
            category: category,
            x: x,
            y: y,
            t: t,
            severityHint: sev,
            exposureHint: exp);
    Group fakeGroup(List<String> ids) => Group(
        id: 'G1',
        reportIds: ids,
        confidence: 0.9,
        singleton: ids.length == 1,
        method: 'meta',
        justification: 'model proposal');
    // T25a: the server listing gives the units, everywhere.
    final listing = metaListingWithUnits([
      repCat('B1', 'nid poule rue lilas chaussee degradee', 'nid-de-poule',
          1.0, 1.0, 500),
      repCat('B2', 'nid poule rue lilas chaussee degradee important',
          'nid-de-poule', 1.0, 1.0, 4820),
    ]);
    check(listing.contains('km') && listing.contains('min') &&
        listing.contains('4320 min = 3.0 days') &&
        listing.contains('0.00 km'),
        'T25a listing with explicit units', listing);
    // T25b: the time gate splits distinct-time (3 days, local).
    final temps = [
      repCat('B1', 'nid poule rue lilas chaussee degradee', 'nid-de-poule',
          1.0, 1.0, 500),
      repCat('B2', 'nid poule rue lilas chaussee degradee important',
          'nid-de-poule', 1.0, 1.0, 4820),
    ];
    final gated = applyMetaTimeGate(temps, [fakeGroup(['B1', 'B2'])]);
    check(gated.splitGroups == 1 && gated.groups.length == 2 &&
        gated.groups.every((g) => g.singleton),
        'T25b time gate splits distinct-time', gated.toString());
    check(gated.groups.every((g) =>
        g.uncertaintyReasons.any((r) => r.contains('meta-time-gate'))),
        'T25b-bis splits traced meta-time-gate',
        gated.groups.map((g) => g.uncertaintyReasons).toString());
    // T25c: the extended exception does NOT split a persistent network outage
    // (5000 min < 10080 min).
    final etendu = [
      repCat('P1', 'coupure electrique quartier ouest', 'coupure-electrique',
          1.0, 1.0, 500),
      repCat('P2', 'coupure electrique quartier ouest ascenseurs',
          'coupure-electrique', 1.0, 1.0, 5500),
    ];
    final kept = applyMetaTimeGate(etendu, [fakeGroup(['P1', 'P2'])]);
    check(kept.splitGroups == 0 && kept.groups.length == 1 &&
        !kept.groups.single.singleton,
        'T25c extended event not split', kept.toString());
    // T25d: mixed category -> conservative local threshold (split).
    final mixte = [
      repCat('M1', 'nid poule rue lilas', 'nid-de-poule', 1.0, 1.0, 500),
      repCat('M2', 'coupure electrique quartier ouest', 'coupure-electrique',
          1.0, 1.0, 1000),
    ];
    final mixGated = applyMetaTimeGate(mixte, [fakeGroup(['M1', 'M2'])]);
    check(mixGated.splitGroups == 1,
        'T25d mixed category -> local threshold', mixGated.toString());
    // T25e: contradictory status (resolved vs ongoing).
    final contra = [
      repCat('A1', 'fuite eau rue basse trottoir sec travaux termines fuite resolue',
          'fuite-eau', 2.0, 2.0, 500, sev: 2, exp: 1),
      repCat('A2', 'fuite eau rue basse trottoir inonde eau coule',
          'fuite-eau', 2.0, 2.0, 520, sev: 3, exp: 2),
    ];
    final flagged = applyGroupStatuses(contra, [fakeGroup(['A1', 'A2'])]);
    check(flagged.contradictoryGroups == 1,
        'T25e contradictory group counted', flagged.toString());
    check(flagged.groups.length == 1 &&
        flagged.groups.single.reportIds.toSet().containsAll(['A1', 'A2']),
        'T25e-bis status does not split the group',
        flagged.groups.toString());
    check(flagged.groups.single.uncertain &&
        flagged.groups.single.uncertaintyReasons
            .any((r) => r.contains('status-conflicting')),
        'T25e-ter group flagged status-conflicting',
        flagged.groups.single.uncertaintyReasons.toString());
    // T25f : multi-problem flag (E1) ; simple case not flagged.
    final multi = [
      repCat('E1', 'nid poule rue lilas chaussee degradee reverbere eteint',
          'nid-de-poule', 1.0, 1.0, 500),
      repCat('E2', 'nid poule rue lilas chaussee degradee', 'nid-de-poule',
          1.0, 1.0, 510),
    ];
    final mFlag = applyGroupStatuses(multi, [fakeGroup(['E1', 'E2'])]);
    check(mFlag.multiProblemGroups == 1,
        'T25f multi-problem group counted', mFlag.toString());
    check(mFlag.groups.single.uncertaintyReasons
        .any((r) => r.contains('multi-problem-flag') && r.contains('E1')),
        'T25f-bis flag cites E1',
        mFlag.groups.single.uncertaintyReasons.toString());
    final simple = applyGroupStatuses(
        multi, [fakeGroup(['E2'])]);
    check(simple.multiProblemGroups == 0 && simple.contradictoryGroups == 0,
        'T25f-ter simple case not flagged', simple.toString());
    // T25g : the statuses alone do not change the reportIds.
    final keptIds = applyGroupStatuses(multi, [fakeGroup(['E1', 'E2'])]);
    check(keptIds.groups.single.reportIds.length == 2,
        'T25g statuses keep the reportIds', keptIds.toString());
    // T25h: E4 non-regression (distant duplicate flagged, not merged).
    final e4 = [
      repCat('R1', 'nid poule rue lilas', 'nid-de-poule', 1.0, 1.0, 500),
      repCat('R2', 'nid poule rue lilas', 'nid-de-poule', 7.5, 1.0, 510),
    ];
    final gE4 = groupReports(e4,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final amb = ambiguousPairs(e4, gE4,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(gE4.length == 2,
        'T25h E4 separated, not merged', gE4.toString());
    check(amb.any((a) =>
        (a['reason'] as String).contains('distant duplicate to verify')),
        'T25h-bis E4 distant duplicate flagged', amb.toString());
  }

  // 26. Multi-problem splitting (local patch, pushed to main).
  {
    Report repS(String id, String text) => Report(
        id: id,
        text: text,
        category: 'nid-de-poule',
        x: 1.0,
        y: 1.0,
        t: 500,
        severityHint: 2,
        exposureHint: 1);
    // T26a: origin case, E1 two problems + E2 pothole alone.
    final origine = [
      repS('E1', 'nid poule rue lilas chaussee degradee reverbere eteint'),
      Report(
          id: 'E2',
          text: 'nid poule rue lilas chaussee degradee',
          category: 'nid-de-poule',
          x: 1.0,
          y: 1.0,
          t: 510,
          severityHint: 2,
          exposureHint: 1),
    ];
    final gSplit = groupSplitReports(origine,
        distMaxM: dDist, deltaTMaxH: dDt);
    final idsSplit = gSplit.map((g) => g.reportIds).toList();
    check(gSplit.length == 2,
        'T26a origin split into 2 groups', idsSplit.toString());
    check(idsSplit.any((g) =>
            g.toSet().containsAll(['E1:voirie-nid', 'E2:voirie-nid'])) &&
        idsSplit.any((g) => g.length == 1 && g.single == 'E1:eclairage'),
        'T26a-bis "eclairage" survives as its own incident',
        idsSplit.toString());
    final byIdOrig = {for (final r in origine) r.id: r};
    final incSplit = aggregateSplitGroups(gSplit, byIdOrig);
    check(incSplit.length == 2,
        'T26a-ter 2 incidents for the optimiser', incSplit.toString());
    check(incSplit.any((i) => i.reportIds.single == 'E1:eclairage'),
        'T26a-quater "eclairage" incident traceable', incSplit.toString());
    // T26b: a single report with two problems -> 2 incidents.
    final seul = [
      repS('M1', 'fuite eau rue basse trottoir inonde reverbere eteint')
    ];
    final gSeul = groupSplitReports(seul, distMaxM: dDist, deltaTMaxH: dDt);
    check(gSeul.length == 2,
        'T26b single report split into 2', gSeul.toString());
    // T26c: same problem twice -> no splitting.
    final faux = [
      repS('N1', 'nid poule rue lilas chaussee degradee trou grand')
    ];
    final gFaux = groupSplitReports(faux, distMaxM: dDist, deltaTMaxH: dDt);
    check(gFaux.length == 1 && gFaux.single.reportIds.single == 'N1:voirie-nid',
        'T26c false multi-problem not split', gFaux.toString());
    // T26d: vague mention -> no automatic splitting.
    final vague = [
      repS('V1',
          'nid poule rue lilas chaussee degradee quelque chose aussi la nuit')
    ];
    final gVague =
        groupSplitReports(vague, distMaxM: dDist, deltaTMaxH: dDt);
    check(gVague.length == 1,
        'T26d vague not split automatically', gVague.toString());
    // T26e : three problems -> 3 incidents.
    final trois = [
      repS('T1',
          'nid poule rue lilas chaussee degradee reverbere eteint fuite eau trottoir inonde')
    ];
    final gTrois =
        groupSplitReports(trois, distMaxM: dDist, deltaTMaxH: dDt);
    check(gTrois.length == 3,
        'T26e three problems split into 3', gTrois.toString());
    // T26f : post-filter on the classic group [E1, E2].
    final gClass = groupReports(origine,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final post = splitGroupsByFamily(origine, gClass);
    check(post.splitGroups == 1 && post.groups.length == 2,
        'T26f post-filter splits the classic group',
        post.groups.toString());
    // T26g: reversibility, each sub-report finds its origin again.
    final units = expandToSubunits(origine);
    check(units.every((u) => byIdOrig.containsKey(u.originId)) &&
        units.map((u) => u.originId).toSet().containsAll(['E1', 'E2']),
        'T26g origins recoverable', units.map((u) => u.id).toString());
    // T26h: unknown family never merges.
    final inconnus = [
      Report(
          id: 'X1',
          text: 'xyz abc',
          category: 'autre',
          x: 1.0,
          y: 1.0,
          t: 500),
      Report(
          id: 'X2',
          text: 'xyz abc',
          category: 'autre',
          x: 1.0,
          y: 1.0,
          t: 510),
    ];
    final gInc =
        groupSplitReports(inconnus, distMaxM: dDist, deltaTMaxH: dDt);
    check(gInc.length == 2,
        'T26h unknowns never merged', gInc.toString());
  }

  // 27. Server wiring of the splitting (lib): mixed aggregation.
  // The server routing itself (bin/server.dart) is not importable
  // by this lib test harness: it is verified on a real server via
  // the runbook (method 'split', split:true). Here, we prove the contract
  // the server relies on: aggregateMixedGroups, the
  // detection of split ids, and the JSON round-trip persistence.
  {
    Report repS(String id, String text) => Report(
        id: id,
        text: text,
        category: 'nid-de-poule',
        x: 1.0,
        y: 1.0,
        t: 500,
        severityHint: 2,
        exposureHint: 1);
    final origine = [
      repS('E1', 'nid poule rue lilas chaussee degradee reverbere eteint'),
      Report(
          id: 'E2',
          text: 'nid poule rue lilas chaussee degradee',
          category: 'nid-de-poule',
          x: 1.0,
          y: 1.0,
          t: 510,
          severityHint: 2,
          exposureHint: 1),
      repS('P1', 'fuite eau rue basse trottoir inonde'),
    ];
    final byId = {for (final r in origine) r.id: r};
    final gSplit = groupSplitReports(origine.sublist(0, 2),
        distMaxM: dDist, deltaTMaxH: dDt);
    // T27a: a split group aggregated as mixed gives 2 incidents
    // (voirie + eclairage), not 1, and the plain one remains its own incident.
    final plain = [
      Group(
          id: 'G9',
          reportIds: ['P1'],
          confidence: 0.0,
          singleton: true,
          method: 'classique')
    ];
    final mixed = aggregateMixedGroups([...gSplit, ...plain], byId);
    check(mixed.length == 3,
        'T27a mixed split gives 3 incidents', mixed.toString());
    check(mixed.map((i) => i.id).toSet().length == 3,
        'T27a-bis unique incident ids', mixed.toString());
    check(mixed.any((i) => i.reportIds.single == 'E1:eclairage'),
        'T27a-ter "eclairage" survives as its own incident', mixed.toString());
    // T27b: the origin is recoverable from each split incident.
    check(mixed
            .where((i) => i.reportIds.any((id) => id.contains(':')))
            .every((i) => i.reportIds
                .every((id) => byId.containsKey(originIdOfSubunit(id)))),
        'T27b origins recoverable from split incidents',
        mixed.toString());
    // T27c: unsplit path strictly identical to the old one.
    final gPlain = groupReports(origine,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final incClassic = aggregate(gPlain, byId);
    final incMixedPlain = aggregateMixedGroups(gPlain, byId);
    check(
        incClassic.length == incMixedPlain.length &&
            incClassic
                .map((i) => '${i.id}:${i.reportIds.join(',')}:${i.domain}')
                .join('|') ==
                incMixedPlain
                    .map((i) => '${i.id}:${i.reportIds.join(',')}:${i.domain}')
                    .join('|'),
        'T27c unsplit identical to aggregate()',
        '${incClassic.length} vs ${incMixedPlain.length}');
    // T27d: old state without sub-reports stays readable, and a
    // split state survives a JSON round-trip (format 1, unchanged).
    final restoredPlain = gPlain
        .map((g) => Group.fromJson(g.toJson()))
        .toList();
    final restoredSplit = gSplit
        .map((g) => Group.fromJson(g.toJson()))
        .toList();
    check(restoredPlain.every((g) => !groupUsesSplitIds(g)) &&
        restoredSplit.any(groupUsesSplitIds),
        'T27d JSON round-trip keeps split ids',
        restoredSplit.toString());
    check(aggregateMixedGroups(restoredSplit, byId).length == 2,
        'T27d-bis restored split state still gives 2 incidents',
        restoredSplit.toString());
    // T27e: detection of split ids (server predicate).
    check(groupUsesSplitIds(gSplit.first) &&
        !groupUsesSplitIds(plain.first) &&
        groupsUseSplitIds([...gSplit, ...plain]) &&
        !groupsUseSplitIds(plain),
        'T27e split/plain detection correct', '');
    // T27f: matching the truth of a split incident requires
    // projecting to the origin: raw, the intersection is empty.
    final splitInc = mixed.firstWhere(
        (i) => i.reportIds.single == 'E1:eclairage');
    check(splitInc.reportIds.toSet().intersection({'E1'}).isEmpty &&
        splitInc.reportIds
                .map(originIdOfSubunit)
                .toSet()
                .intersection({'E1'})
                .isNotEmpty,
        'T27f truth linked via origin, not via raw id', '');
  }

  // T28: media — validation by magic bytes, never by extension.
  {
    check(validateImageBytes([0xFF, 0xD8, 0xFF, 0x00, 0x10]) == 'jpg',
        'T28a JPEG detected');
    check(
        validateImageBytes(
                [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]) ==
            'png',
        'T28b PNG detected');
    check(validateImageBytes([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]) == 'gif',
        'T28c GIF detected');
    check(
        validateImageBytes([
          0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00,
          0x57, 0x45, 0x42, 0x50
        ]) ==
            'webp',
        'T28d WebP detected');
    var refused = 0;
    try {
      validateImageBytes([0x25, 0x50, 0x44, 0x46]);
    } on MediaValidationError {
      refused++;
    }
    try {
      validateImageBytes([]);
    } on MediaValidationError {
      refused++;
    }
    try {
      validateImageBytes(List<int>.filled(maxPhotoBytes + 1, 0xFF));
    } on MediaValidationError {
      refused++;
    }
    check(refused == 3, 'T28e PDF/empty/oversized refused');
    final id = newMediaId();
    check(isMediaId(id) && !isMediaId('../$id') && !isMediaId('photo.jpg'),
        'T28f strict mediaId (anti-path)', id);
    check(mimeForExt('jpg') == 'image/jpeg' &&
        mimeForExt('png') == 'image/png',
        'T28g MIME mapping');
    var traversal = 0;
    try {
      mediaFile('u', '../evil', 'jpg');
    } on MediaValidationError {
      traversal++;
    }
    try {
      mediaFile('u', id, 'exe');
    } on MediaValidationError {
      traversal++;
    }
    check(traversal == 2, 'T28h traversal/extension blocked');
  }

  // T29: chat request body — images only in the user message.
  {
    final txt = MetaConnector.buildChatRequest(
        model: 'm', system: 's', user: 'u');
    final msgs = txt['messages'] as List;
    check((msgs[1]['content'] as String) == 'u',
        'T29a text alone stays a string');
    final withImg = MetaConnector.buildChatRequest(
        model: 'm',
        system: 's',
        user: 'u',
        images: [
          {'mime': 'image/jpeg', 'base64': 'QUJD'}
        ]);
    final parts = (withImg['messages'] as List)[1]['content'] as List;
    check(
        parts.length == 2 &&
            parts[0]['type'] == 'text' &&
            parts[1]['type'] == 'image_url' &&
            (parts[1]['image_url']['url'] as String)
                .startsWith('data:image/jpeg;base64,'),
        'T29b image as data URL in the user message');
    check(((withImg['messages'] as List)[0]['content'] as String) == 's',
        'T29c system without image (never a 400)');
    final okAnalysis = {
      'observationsVisibles': ['waste near the gutter', 'water present'],
      'problemesPossibles': [
        {
          'famille': 'assainissement',
          'hypothese': 'obstruction possible',
          'confirmation': 'a_verifier'
        }
      ],
      'localisation': null,
      'gravite': null,
      'exposition': null,
      'incertitudes': ['degree of obstruction unconfirmed'],
    };
    check(validateVisualAnalysis(okAnalysis) == null,
        'T29d valid visual contract accepted');
    check(
        validateVisualAnalysis({
              'observationsVisibles': ['x'],
              'problemesPossibles': [],
              'incertitudes': [],
            }) !=
            null,
        'T29e empty uncertainties refused');
    check(
        validateVisualAnalysis({
              'observationsVisibles': [],
              'problemesPossibles': [],
              'incertitudes': ['?'],
            }) !=
            null,
        'T29f empty observations refused');
  }

  // T30: §8 demo — "caniveau + lampadaires": two problems kept.
  {
    final r = Report(
        id: 'DEMO8',
        text:
            'Le caniveau est rempli de déchets et les lampadaires de la rue ne fonctionnent plus depuis plusieurs jours.',
        category: 'autre',
        x: 2.0,
        y: 2.0,
        t: 500);
    final fams = reportProblemFamilies(r);
    check(fams.contains('assainissement') && fams.contains('eclairage'),
        'T30a two families detected', '$fams');
    check(hasMultiProblem(r), 'T30b multi-problem flagged');
    final gs = groupSplitReports([r], distMaxM: 250.0, deltaTMaxH: 6.0);
    check(gs.length == 2 && gs.every((g) => g.method == 'split'),
        'T30c split into 2 split groups',
        gs.map((g) => g.reportIds).toString());
    final incs = aggregateMixedGroups(gs, {'DEMO8': r});
    check(incs.length == 2, 'T30d no problem lost', '${incs.length}');
    final doms = incs.map((i) => i.domain).toSet();
    check(doms.contains('reseaux') && doms.contains('voirie'),
        'T30e distinct domains (assainissement→reseaux)', '$doms');
    check(incs.every((i) => i.severity == null),
        'T30f unknown severity kept on both parts');
  }

  // T31: comparePlans does not crash when a matched incident has no
  // task in the new plan (inject team_down regression, Nov. 2026).
  {
    const oldP = Plan(
        tasks: [
          Task(
              incidentId: 'I1',
              teamId: 'equipe-2',
              order: 1,
              startMin: 500,
              endMin: 600,
              travelKm: 1.0,
              cost: 10.0),
          Task(
              incidentId: 'I2',
              teamId: 'equipe-1',
              order: 1,
              startMin: 500,
              endMin: 600,
              travelKm: 1.0,
              cost: 10.0),
        ],
        unassigned: {},
        escalations: [],
        totalCost: 20.0,
        q: 50.0,
        feasible: true,
        violations: [],
        justifications: {});
    const newP = Plan(
        tasks: [
          Task(
              incidentId: 'I2',
              teamId: 'equipe-1',
              order: 1,
              startMin: 500,
              endMin: 600,
              travelKm: 1.0,
              cost: 10.0),
        ],
        unassigned: {'I1': 'no competent team'},
        escalations: [],
        totalCost: 10.0,
        q: 25.0,
        feasible: true,
        violations: [],
        justifications: {});
    final d = comparePlans(oldP, newP,
        oldReports: {
          'I1': {'R3:eau'},
          'I2': {'R1:voirie-nid'}
        },
        newReports: {
          'I1': {'R3:eau'},
          'I2': {'R1:voirie-nid'}
        });
    check(d.material, 'T31 dropped incident = material change',
        d.detail);
  }

  // T32: rate limiter — sliding window per key.
  {
    var now = DateTime.utc(2026, 1, 1);
    final rl = RateLimiter(now: () => now);
    var ok = 0;
    for (var i = 0; i < 20; i++) {
      if (rl.allow('ip:1.2.3.4', max: 20, window: const Duration(minutes: 10))) {
        ok++;
      }
    }
    check(ok == 20, 'T32a first 20 accepted');
    check(!rl.allow('ip:1.2.3.4', max: 20, window: const Duration(minutes: 10)),
        'T32b 21st refused (429)');
    check(rl.allow('ip:5.6.7.8', max: 20, window: const Duration(minutes: 10)),
        'T32c other IP independent');
    now = now.add(const Duration(minutes: 11));
    check(rl.allow('ip:1.2.3.4', max: 20, window: const Duration(minutes: 10)),
        'T32d window expired, accepted again');
  }

  // T33: municipal auth — open without token, closed with token.
  {
    final open = MunicipalAuth.fromEnvironment({});
    check(!open.enforced && open.isAuthorized(),
        'T33a without token: open mode (local dev)');
    final closed =
        MunicipalAuth.fromEnvironment({'CITYRESOLVE_MUNICIPAL_TOKEN': 'secret-jeton'});
    check(closed.enforced && !closed.isAuthorized(),
        'T33b with token: closed by default');
    check(!closed.checkToken('mauvais') && closed.checkToken('secret-jeton'),
        'T33c token verified, bad one rejected');
    final sid = closed.createSession();
    check(closed.checkSession(sid) && !closed.checkSession('faux'),
        'T33d session created and verified');
    check(closed.isAuthorized(sessionId: sid),
        'T33e session authorised');
    check(closed.isAuthorized(bearerToken: 'secret-jeton') &&
        !closed.isAuthorized(bearerToken: 'x'),
        'T33f bearer accepted/rejected');
    closed.revoke(sid);
    check(!closed.checkSession(sid), 'T33g revocation effective');
  }

  // T34: public input validation.
  {
    check(publicTextError(null) == 'description required' &&
        publicTextError('   ') == 'description required',
        'T34a empty text refused');
    check(publicTextError('nid de poule rue basse') == null,
        'T34b valid text accepted');
    check(
        publicTextError(List.filled(501, 'x').join()) != null &&
            publicTextError(List.filled(500, 'x').join()) == null,
        'T34c exact 500 limit');
    check(isPublicCategory('fuite-eau') && !isPublicCategory('mairie') &&
        !isPublicCategory(''),
        'T34d closed categories');
  }

  // T35: filtered public DTOs + derived tracking statuses.
  {
    Report rep(String id) => Report(
        id: id,
        text: 'trou chaussée',
        category: 'nid-de-poule',
        x: 1.0,
        y: 1.0,
        t: 100,
        severityHint: 2,
        exposureHint: 1,
        source: 'manuel',
        receivedAt: '2026-01-01T00:00:00Z');
    Incident inc(String id, List<String> ids, int? sev) => Incident(
        id: id,
        reportIds: ids,
        severity: sev,
        exposure: 1,
        domain: 'voirie',
        x: 1.0,
        y: 1.0,
        firstSeen: 100,
        confidence: 0.8);
    final r1 = rep('M1');
    final dto = publicReportJson(r1, status: 'enregistre');
    check(!dto.containsKey('severityHint') &&
        !dto.containsKey('exposureHint') &&
        !dto.containsKey('truth') &&
        dto['receivedAt'] == '2026-01-01T00:00:00Z' &&
        dto['fictive'] == true,
        'T35a public DTO filtered (no hints, no truth)');
    final gSolo = Group(
        id: 'G1',
        reportIds: ['M1'],
        confidence: 0,
        singleton: true,
        method: 'classique');
    final gPair = Group(
        id: 'G1',
        reportIds: ['M1', 'M2'],
        confidence: 0.8,
        singleton: false,
        method: 'classique');
    check(
        trackingStatus(r1, [gSolo], [inc('I1', ['M1'], 2)], null) ==
            'enregistre',
        'T35b singleton → recorded');
    check(
        trackingStatus(r1, [gPair], [inc('I1', ['M1', 'M2'], 2)], null) ==
            'regroupe',
        'T35c pair → grouped');
    final plan = Plan(
        tasks: [
          Task(
              incidentId: 'I1',
              teamId: 'equipe-1',
              order: 1,
              startMin: 100,
              endMin: 200,
              travelKm: 1.0,
              cost: 10.0)
        ],
        unassigned: {},
        escalations: [],
        totalCost: 10.0,
        q: 50.0,
        feasible: true,
        violations: [],
        justifications: {});
    check(
        trackingStatus(r1, [gPair], [inc('I1', ['M1', 'M2'], 2)], plan) ==
            'planifie',
        'T35d planned task → planned');
    check(
        trackingStatus(r1, [gPair], [inc('I1', ['M1', 'M2'], 5)], plan) ==
            'escalade-s5',
        'T35e priority S5 → escalation');
    final pub = publicIncidentJson(inc('I1', ['M1', 'M2'], null));
    check(pub['severity'] == null &&
        pub['reportCount'] == 2 &&
        pub['fictive'] == true &&
        !pub.containsKey('weight'),
        'T35f public incident filtered');
  }

  // T36: browser GPS — bounded validation, exposure limited to tracking.
  {
    check(publicGpsError(null, null, null) == null,
        'T36a GPS absent accepted (manual entry)');
    check(publicGpsError(5.32, -4.02, 12.0) == null,
        'T36b valid GPS accepted');
    check(publicGpsError(5.32, null, null) != null,
        'T36c incomplete GPS refused');
    check(publicGpsError(91.0, 0.0, null) != null &&
        publicGpsError(0.0, 200.0, null) != null,
        'T36d out of bounds refused');
    check(publicGpsError(5.32, -4.02, -3.0) != null,
        'T36e negative accuracy refused');
    final r = Report(
        id: 'M9',
        text: 'x',
        category: 'autre',
        x: 2.5,
        y: 2.5,
        t: 500,
        gpsLat: 5.32,
        gpsLon: -4.02,
        gpsAccuracy: 12.0);
    final list = publicReportJson(r, status: 'enregistre');
    check(list['hasGps'] == true && !list.containsKey('gps'),
        'T36f list: presence flagged, coordinates hidden');
    final track =
        publicReportJson(r, status: 'enregistre', includeGps: true);
    final gps = track['gps'] as Map<String, dynamic>;
    check(gps['lat'] == 5.32 && gps['lon'] == -4.02 && gps['accuracy'] == 12.0,
        'T36g tracking: GPS visible to the reporter');
    final plain = Report(
        id: 'M8',
        text: 'x',
        category: 'autre',
        x: 1.0,
        y: 1.0,
        t: 100);
    check(publicReportJson(plain, status: 'enregistre')['hasGps'] == false,
        'T36h without GPS: hasGps false');
  }

  // T37: public scalability — sorting, cursor pagination, bbox, stats.
  {
    Report pr(String id, String? at) => Report(
        id: id,
        text: 't',
        category: 'autre',
        x: 1.0,
        y: 1.0,
        t: 100,
        receivedAt: at);
    final sorted = sortPublicReports(
        [pr('S1', null), pr('M3', '2026-01-03T00:00:00Z'), pr('M1', '2026-01-01T00:00:00Z'), pr('M2', '2026-01-02T00:00:00Z'), pr('S2', null)]);
    check(sorted.map((r) => r.id).join(',') == 'M3,M2,M1,S2,S1',
        'T37a received first, scenarios last',
        sorted.map((r) => r.id).join(','));
    final p1 = paginatePublicReports(sorted, 2, null);
    check(p1.items.map((r) => r.id).join(',') == 'M3,M2' && p1.nextCursor == 'M2',
        'T37b page 1 + cursor');
    final p2 = paginatePublicReports(sorted, 2, p1.nextCursor);
    check(p2.items.map((r) => r.id).join(',') == 'M1,S2' && p2.nextCursor == 'S2',
        'T37c page 2 chained');
    final p3 = paginatePublicReports(sorted, 2, p2.nextCursor);
    check(p3.items.map((r) => r.id).join(',') == 'S1' && p3.nextCursor == null,
        'T37d last page without next cursor');
    check(paginatePublicReports(sorted, 2, 'INCONNU').items.isEmpty,
        'T37e unknown cursor → empty (no jump)');
    Incident ii(String id, double x, double y) => Incident(
        id: id,
        reportIds: [id],
        severity: 2,
        exposure: 1,
        domain: 'voirie',
        x: x,
        y: y,
        firstSeen: 1,
        confidence: 1.0);
    final box = filterIncidentsBbox(
        [ii('A', 1.0, 1.0), ii('B', 4.5, 4.5), ii('C', 2.0, 2.0)],
        0.0, 0.0, 3.0, 3.0, 100);
    check(box.map((i) => i.id).join(',') == 'A,C', 'T37f bbox filter');
    check(filterIncidentsBbox([ii('A', 1.0, 1.0), ii('B', 1.5, 1.5)], 0, 0, 5, 5, 1).length == 1,
        'T37g strict limit');
    final g = Group(
        id: 'G1', reportIds: ['M1', 'M2'], confidence: 1, singleton: false, method: 'classique');
    final st = publicStatsSummary(
        [pr('M1', '2026-01-01T00:00:00Z'), pr('M2', null)], [g], [ii('I1', 1, 1)]);
    check(st['reports'] == 2 && st['incidents'] == 1 && st['groupedReports'] == 2 &&
        st['lastReceivedAt'] == '2026-01-01T00:00:00Z' && st['fictive'] == true,
        'T37h aggregates, counters only', '$st');
  }

  // T38: dashboard — periods, exclusive statuses, activity, search.
  {
    final now = DateTime.utc(2026, 11, 4, 12);
    final b7 = periodBounds(const Period('7d'), now);
    check(b7.end!.difference(b7.start!).inDays == 7 &&
        b7.prevEnd == b7.start &&
        b7.prevStart!.difference(b7.prevEnd!).inDays == -7,
        'T38a 7d window + adjacent previous');
    final ball = periodBounds(const Period('all'), now);
    check(ball.start == null && ball.end == null,
        'T38b all without bounds');
    var badPeriod = 0;
    try {
      parsePeriod('nope', null, null);
    } on FormatException {
      badPeriod++;
    }
    try {
      parsePeriod('custom', '2026-01-02T00:00:00Z', '2026-01-01T00:00:00Z');
    } on FormatException {
      badPeriod++;
    }
    check(badPeriod == 2, 'T38c invalid periods rejected');
    Report rr(String id, String? at) => Report(
        id: id, text: 't', category: 'autre', x: 1, y: 1, t: 1, receivedAt: at);
    final reps = [
      rr('N1', '2026-11-03T12:00:00Z'),
      rr('N2', '2026-11-04T11:00:00Z'),
      rr('O1', '2026-10-20T00:00:00Z'),
      rr('S1', null),
    ];
    final kpi = reportsKpi(reps, b7.start, b7.end, b7.prevStart, b7.prevEnd);
    check(kpi['count'] == 2 && kpi['previousCount'] == 0 && kpi['deltaPct'] == null,
        'T38d 7d window: 2 received, empty reference → no percentage', '$kpi');
    final kAll = reportsKpi(reps, null, null, null, null);
    check(kAll['count'] == 4 && kAll['previousCount'] == null,
        'T38e all includes undated ones');
    Incident ii(String id, int? sev) => Incident(
        id: id, reportIds: [id], severity: sev, exposure: 1,
        domain: 'voirie', x: 1, y: 1, firstSeen: 1, confidence: 1.0);
    final plan = Plan(
        tasks: [
          Task(incidentId: 'I1', teamId: 'equipe-1', order: 1,
              startMin: 1, endMin: 2, travelKm: 1.0, cost: 1.0)
        ],
        unassigned: {'I2': 'motif'},
        escalations: ['I9'],
        totalCost: 1.0, q: 10.0, feasible: true,
        violations: [], justifications: {});
    final bk = incidentStatusBuckets(
        [ii('I1', 2), ii('I2', 3), ii('I9', 5)], plan);
    final bc = {for (final r in (bk['buckets'] as List)) r['status']: r['count']};
    check(bk['total'] == 3 && bc['planifie'] == 1 && bc['non-affecte'] == 1 &&
        bc['escalade-s5'] == 1 && bc['a-analyser'] == 0,
        'T38f exclusive statuses, sum = total', '$bk');
    final bk0 = incidentStatusBuckets([ii('I1', 2)], null);
    final bc0 = {for (final r in (bk0['buckets'] as List)) r['status']: r['count']};
    check(bc0['a-analyser'] == 1, 'T38g without plan → to analyse');
    check(priorityOf(ii('X', 5)) == 'critique' &&
        priorityOf(ii('X', 4)) == 'haute' &&
        priorityOf(ii('X', 3)) == 'moyenne' &&
        priorityOf(ii('X', 1)) == 'faible' &&
        priorityOf(ii('X', null)) == 'a-verifier',
        'T38h priorities derived from declared severity');
    final act = activityItem({'seq': 7, 'at': 't', 'event': 'plan.proposed',
        'details': {'planId': 'PLAN-2', 'tasks': 4, 'q': 61.0}});
    check(act['type'] == 'plan' && act['ref'] == 'PLAN-2',
        'T38i plan activity mapped', '$act');
    final unk = activityItem({'seq': 8, 'at': 't', 'event': 'futur.inconnu'});
    check(unk['label'] == 'futur.inconnu', 'T38j unknown event kept');
    final hits = searchAll('lilas',
        [rr('R1', null), rr('R2', null)],
        [], [ii('I9', 5)], null);
    check(hits.isEmpty, 'T38k honest empty search');
    final hits2 = searchAll('r1',
        [Report(id: 'R1', text: 'nid rue des Lilas', category: 'nid-de-poule',
            x: 1, y: 1, t: 1)],
        [], [], null);
    check(hits2.length == 1 && hits2.single['kind'] == 'report',
        'T38l search by id/text');
  }

  // T39 : municipal pages — splitting, plan, revision, record, patch.
  {
    Report rr2(String id, String text, {int? sev}) => Report(
        id: id, text: text, category: 'autre', x: 1.0, y: 1.0, t: 100,
        severityHint: sev);
    final multi = rr2('E1',
        'nid de poule rue basse, lampadaire eteint depuis jours',
        sev: null);
    final solo = rr2('E2', 'nid de poule rue basse chaussee', sev: 2);
    final reps = [multi, solo];
    final gs = groupSplitReports(reps, distMaxM: 250.0, deltaTMaxH: 6.0);
    final byId = {for (final r in reps) r.id: r};
    final incs = aggregateMixedGroups(gs, byId);
    final over = splitOverviewData(reps, gs, incs, 'split');
    check(over['units'] == 3 && over['incidents'] == incs.length,
        'T39a overview: 3 units, real incidents', '$over');
    check((over['multiProblemReports'] as List).contains('E1') &&
        !(over['multiProblemReports'] as List).contains('E2'),
        'T39b secondary kept (E1), simple not flagged');
    check(over['method'] == 'split' && (over['justifications'] as List).isNotEmpty,
        'T39c real method + justifications, no invented %');
    final det = splitReportDetail(reps, gs, incs, 'E1')!;
    check(det['multiProblem'] == true &&
        (det['subunits'] as List).length == 2 &&
        (det['linkedIncidents'] as List).isNotEmpty,
        'T39d E1 → 2 parts + linked incidents', '$det');
    check(splitReportDetail(reps, gs, incs, 'ZZZ') == null,
        'T39e unknown report → null (no 500)');
    Incident ii2(String id, int? sev) => Incident(
        id: id, reportIds: [id], severity: sev, exposure: 1,
        domain: 'voirie', x: 1, y: 1, firstSeen: 1, confidence: 1.0);
    final po = planOverviewData(
        reports: reps, incidents: [ii2('I1', 2), ii2('I9', 5), ii2('I8', null)],
        plan: null, planValidation: null,
        allTeams: defaultTeams(), teamsDown: {'equipe-1'},
        simQ: null, simFeasible: null);
    check((po['teams'] as List).length == 2 &&
        (po['teams'] as List).every((t) => (t as Map).containsKey('available')),
        'T39f real teams (2, not 5)');
    final down = (po['teams'] as List).firstWhere((t) => t['id'] == 'equipe-1');
    check(down['available'] == false, 'T39g outage reflected');
    final rows = po['incidents'] as List;
    final byI = {for (final r in rows) r['incidentId']: r};
    check(byI['I9']!['status'] == 'escalade-s5' &&
        byI['I8']!['status'] == 'a-verifier' &&
        byI['I1']!['status'] == 'planifiable',
        'T39h plan statuses: S5 escalation, unknown to verify, admissible plannable without plan');
    check(byI['I8']!['dureeEstimeeMin'] == null,
        'T39i no estimated duration without severity');
    final hist = revisionHistoryData([], [
      {'seq': 1, 'at': 't', 'event': 'plan.proposed', 'details': {'planId': 'PLAN-1'}},
      {'seq': 2, 'at': 't', 'event': 'photo.uploaded', 'details': {}},
      {'seq': 3, 'at': 't', 'event': 'inject.received', 'details': {'type': 'team_down'}},
    ], 10);
    check((hist['events'] as List).length == 2,
        'T39j revision history: only inject/plan/sim');
    check(validateReportPatch({'text': ''}) != null &&
        validateReportPatch({'category': 'mairie'}) != null &&
        validateReportPatch({'severityHint': 9}) != null &&
        validateReportPatch({'verificationNote': List.filled(501, 'x').join()}) != null,
        'T39k invalid patch rejected');
    check(validateReportPatch({'text': 'ok', 'severityHint': null, 'verificationNote': null}) == null &&
        validateReportPatch({}) == null,
        'T39l valid / empty patch accepted');
    final fd = ficheData(
        report: multi, groups: gs, incidents: incs,
        photoMeta: {'mime': 'image/png', 'size': 70},
        visualAnalysis: null, extraction: {'probleme': 'x'},
        auditEntries: [
          {'seq': 5, 'at': 't', 'event': 'report.created', 'details': {'id': 'E1'}},
          {'seq': 6, 'at': 't', 'event': 'group.done', 'details': {}},
        ]);
    check((fd['subunits'] as List).length == 2 &&
        (fd['linkedIncidents'] as List).isNotEmpty &&
        (fd['history'] as List).length == 1 &&
        (fd['report'] as Map)['fictive'] != false,
        'T39m record: parts + linked + id history, fictitious explicit');
  }

  // T40: municipal pages — plan, revision, statuses without inventing.
  {
    Incident ii2(String id, int? sev, [List<String>? rids]) => Incident(
        id: id, reportIds: rids ?? [id], severity: sev, exposure: 1,
        domain: 'voirie', x: 1, y: 1, firstSeen: 1, confidence: 1.0);
    final po = planOverviewData(
        reports: [], incidents: [ii2('I1', 2), ii2('I9', 5), ii2('I8', null)],
        plan: null, planValidation: null,
        allTeams: defaultTeams(), teamsDown: {},
        simQ: null, simFeasible: null);
    final rows = {for (final r in (po['incidents'] as List)) r['incidentId']: r};
    check(rows['I1']!['status'] == 'planifiable' &&
        rows['I9']!['status'] == 'escalade-s5' &&
        rows['I8']!['status'] == 'a-verifier',
        'T40a plan statuses without inventing');
    check((po['counts'] as Map)['planifiable'] == 1 &&
        (po['counts'] as Map)['planifie'] == 0,
        'T40a-bis admissibles counted even without plan');
    check((po['counts'] as Map)['planifiable'] == 1 &&
        po['plan'] == null && po['sim'] == null,
        'T40b without plan: counters only, no sim');
    check((po['teams'] as List).length == 2 &&
        (po['teams'] as List).every((t) => t['available'] == true),
        'T40c 2 real teams, all available');
    final hist = revisionHistoryData([], [
      {'seq': 1, 'at': 't', 'event': 'photo.uploaded', 'details': {}},
      {'seq': 2, 'at': 't', 'event': 'plan.proposed',
          'details': {'planId': 'PLAN-1', 'q': 60.0, 'tasks': 4, 'cost': 100.0}},
    ], 10);
    check((hist['plans'] as List).isEmpty &&
        (hist['events'] as List).length == 1,
        'T40d history: only inject/plan/simulate/validated kept');
    final ph = [
      {'planId': 'PLAN-1', 'version': 1, 'at': 't', 'method': 'classique',
          'validation': null, 'plan': {'q': 60.0, 'totalCost': 100.0, 'tasks': []}},
      {'planId': 'PLAN-2', 'version': 2, 'at': 't2', 'method': 'classique',
          'validation': 'valide', 'plan': {'q': 55.0, 'totalCost': 90.0, 'tasks': []}},
    ];
    final hist2 = revisionHistoryData(ph, [], 10);
    final plans = hist2['plans'] as List;
    check(plans.length == 2 && plans.first['planId'] == 'PLAN-2' &&
        plans.first['validation'] == 'valide',
        'T40e newest versions first, validation kept');
  }

  // T41: injection must group with the active method (regression
  // false N3-S5: grouping a split state as classic changes the
  // ORIGIN:FAMILY ids -> plain ones and makes a known S5 look
  // new).
  {
    Set<String> freshS5(List<Incident> oldIncs, List<Incident> newIncs) {
      final oldKeys = oldIncs
          .where((i) => i.severity != null && i.severity! >= 5)
          .map((i) => i.reportIds.join(','))
          .toSet();
      return newIncs
          .where((i) => i.severity != null && i.severity! >= 5)
          .map((i) => i.id)
          .where((id) => !oldKeys.contains(newIncs
              .firstWhere((i) => i.id == id)
              .reportIds
              .join(',')))
          .toSet();
    }

    final s1 = Report(
        id: 'S1', text: 'immeuble effondrement urgence', category: 'autre',
        x: 0.5, y: 4.5, t: 900, severityHint: 5);
    final m = Report(
        id: 'M1', text: 'nid de poule rue des lilas chaussee abimee',
        category: 'nid-de-poule', x: 1.0, y: 1.0, t: 500, severityHint: 2);
    final reps = [s1, m];
    final byId = {for (final r in reps) r.id: r};
    final gs = groupSplitReports(reps, distMaxM: 250.0, deltaTMaxH: 6.0);
    final incs = aggregateMixedGroups(gs, byId);
    check(freshS5(incs, incs).isEmpty,
        'T41a stable state: no fresh false S5');
    final dup = Report(
        id: 'M2', text: 'nid de poule rue des lilas chaussee trou',
        category: 'nid-de-poule', x: 1.0, y: 1.0, t: 530, severityHint: 2);
    final reps2 = [...reps, dup];
    final byId2 = {for (final r in reps2) r.id: r};
    final kept = aggregateMixedGroups(
        groupSplitReports(reps2, distMaxM: 250.0, deltaTMaxH: 6.0), byId2);
    check(freshS5(incs, kept).isEmpty,
        'T41b duplicate + active method (split): still no fresh S5');
    final classic = aggregate(
        groupReports(reps2,
            distMaxM: 250.0, deltaTMaxH: 6.0, simMin: 0.75),
        byId2);
    check(freshS5(incs, classic).isNotEmpty,
        'T41c classic grouping on split state: fresh false S5 (the bug fixed in /api/inject)');
  }

  // T42: plan stale if grouping is later (positional I1.. ids).
  {
    const p = Plan(
        tasks: [], unassigned: {}, escalations: [], totalCost: 0, q: 0,
        feasible: true, violations: [], justifications: {},
        planId: 'PLAN-9', version: 9);
    final hist = [
      {'planId': 'PLAN-9', 'at': '2026-11-04T10:00:00.000Z'}
    ];
    check(planIsStale(null, hist, []) == false,
        'T42a without plan: not stale');
    check(planIsStale(p, [], []) == true,
        'T42b plan without history entry: stale by caution');
    check(
        planIsStale(p, hist, [
          {'event': 'group.done', 'at': '2026-11-04T09:00:00.000Z'}
        ]) == false,
        'T42c earlier grouping: plan fresh');
    check(
        planIsStale(p, hist, [
          {'event': 'group.done', 'at': '2026-11-04T11:00:00.000Z'}
        ]) == true,
        'T42d later grouping: plan stale');
    final scoped = revisionHistoryData([], [
      {'seq': 1, 'at': '2026-11-04T08:00:00.000Z', 'event': 'inject.received',
          'details': {'type': 'reports'}},
      {'seq': 2, 'at': '2026-11-04T09:00:00.000Z', 'event': 'scenario.loaded',
          'details': {}},
      {'seq': 3, 'at': '2026-11-04T10:00:00.000Z', 'event': 'inject.received',
          'details': {'type': 'reports'}},
    ], 10);
    check((scoped['events'] as List).length == 1 &&
        (scoped['events'] as List).first['seq'] == 3,
        'T42e history scoped to the current generation (after scenario.loaded)');
  }

  // T43: "missing buttons" non-regression (Nov. 2026) — the municipal
  // interface exposes the Meta state and visual analysis, never simulated:
  // each button calls the corresponding real server route.
  {
    String readWeb(String name) {
      for (final base in ['web', 'app/web']) {
        final f = File('$base/$name');
        if (f.existsSync()) return f.readAsStringSync();
      }
      return '';
    }

    final dashHtml = readWeb('dashboard.html');
    final dashJs = readWeb('dashboard.js');
    final decoupHtml = readWeb('decoupage.html');
    final decoupJs = readWeb('decoupage.js');
    final ficheJs = readWeb('fiche-signalement.js');
    check(dashHtml.isNotEmpty && dashJs.isNotEmpty && decoupHtml.isNotEmpty &&
        decoupJs.isNotEmpty && ficheJs.isNotEmpty,
        'T43a municipal pages readable from the test root');
    check(dashHtml.contains('Verify Meta') && dashHtml.contains('metaVerifyBtn'),
        'T43b dashboard: Verify Meta button present');
    check(dashJs.contains('/api/meta') && dashJs.contains('/api/meta/verify'),
        'T43c dashboard: Meta state read and verified via the real routes');
    check(decoupHtml.contains('Verify Meta') &&
        decoupHtml.contains('metaVerifyBtn'),
        'T43d splitting: Verify Meta button present');
    check(decoupJs.contains('/api/meta/verify'),
        'T43e splitting: verification via the real route');
    check(ficheJs.contains('/api/meta/analyze-image'),
        'T43f record: visual analysis via the real route');
    check(dashJs.contains('/api/meta/analyze-image'),
        'T43g dashboard: visual analysis of the latest report');
    check(decoupJs.contains('/api/meta/analyze-image'),
        'T43h splitting: visual analysis of the origin report');
  }

  print('== $_pass PASS, $_fail FAIL ==');
  if (_fail > 0) throw StateError('$_fail test(s) failed.');
}
