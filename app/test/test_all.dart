// Tests CityResolve DEV : exécution réelle, valeurs attendues calculées à
// la main (voir commentaires). Zéro dépendance : `dart run test/test_all.dart`.
// Code de sortie non nul si un test échoue.
import 'dart:convert';
import 'dart:io';

import '../lib/audit.dart';
import '../lib/grouping.dart';
import '../lib/incidents.dart';
import '../lib/media.dart';
import '../lib/meta_connector.dart';
import '../lib/metrics.dart';
import '../lib/optimizer.dart';
import '../lib/oracle.dart';
import '../lib/scenarios.dart';
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

  // 1. Deux signalements du même incident -> même groupe.
  {
    final sc = toyFixed1();
    final g = groupReports(sc.reports,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final gR1 =
        g.firstWhere((x) => x.reportIds.contains('R1')).reportIds.toSet();
    check(gR1.contains('R2'), 'T1 même incident regroupé', gR1.toString());
  }

  // 2. Incidents proches mais différents -> groupes séparés.
  {
    final sc = toyFixed1();
    final g = groupReports(sc.reports,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(g.length == 3, 'T2a 3 groupes jouet-1', '${g.length}');
    // Même lieu/instant, vocabulaires disjoints (Jaccard 1/13 < 0,75).
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
    check(g2.length == 2, 'T2b vocabulaires disjoints séparés',
        '${g2.length}');
  }

  // 3. Exposition inconnue : conservée, décision E=4, poids cohérent.
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
    // Main : w = 0,65*(2/4) + 0,35*(4/4) = 0,325 + 0,35 = 0,675.
    check(i.exposure == null && i.exposureUnknown, 'T3a inconnue conservée');
    check(i.exposureForDecision == 4, 'T3b décision E=4');
    check(approx(i.weight, 0.675), 'T3c poids = 0,675', '${i.weight}');
  }

  // 4. Équipe non compétente -> motif explicite.
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
            (p.unassigned['IX'] ?? '').contains('aucune équipe compétente'),
        'T4 équipe incompétente',
        p.unassigned.toString());
  }

  // 5. Budget insuffisant : optimiseur respecte, simulateur sanctionne Q=0.
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
    check(po.totalCost <= 120.0, 'T5a optimiseur respecte budget',
        '${po.totalCost}');
    // Plan manuel forcé : tout sur equipe-2 (4x40 site = 160 > 120).
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
    check(sm.violations.any((v) => v.startsWith('budget dépassé')),
        'T5c motif budget', sm.violations.toString());
  }

  // 6. Échéance dépassée -> non affecté avec motif.
  {
    final r = Report(
        id: 'L',
        text: 'coupure electrique immeuble ascenseur bloque soir',
        category: 'coupure-electrique',
        x: 4.5,
        y: 4.5,
        t: 9540, // J6 15:00, S4 => échéance J6 19:00, fin de service 16:00
        severityHint: 4,
        exposureHint: 1);
    final incs = aggregate(
        [Group(id: 'G1', reportIds: ['L'], confidence: 0, singleton: true)],
        {'L': r});
    final p = optimizeExact(incidents: incs, teams: teams);
    check(
        p.tasks.isEmpty &&
            (p.unassigned['I1'] ?? '').contains('échéance'),
        'T6 échéance inaccessible',
        p.unassigned.toString());
  }

  // 7. S5 exclu du dispatch automatique, escaladé.
  {
    final sc = toyS5();
    final g = groupReports(sc.reports,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(g.length == 2, 'T7a 2 groupes', '${g.length}');
    final byId = {for (final r in sc.reports) r.id: r};
    final incs = aggregate(g, byId);
    final p = optimizeExact(incidents: incs, teams: teams);
    final s5 = incs.firstWhere((i) => i.severity != null && i.severity! >= 5);
    check(p.escalations.contains(s5.id), 'T7b S5 escaladé',
        p.escalations.toString());
    check(!p.tasks.any((t) => t.incidentId == s5.id),
        'T7c S5 jamais dispatché');
    check(approx(p.q, 100.0), 'T7d Q=100 sur S2 restant', '${p.q}');
  }

  // 8. Information nouvelle modifiant une décision (panne équipe-1).
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
    check(nec.code == 'N1' && nec.necessary, 'T8a N1 panne équipe',
        nec.code);
    final p1 = optimizeExact(incidents: incs, teams: t2only);
    // Main : A+B complétés, C (EV) impossible : Q = 100*(0,4125+0,6625)/1,2375.
    check(approx(p1.q, 86.8687, 0.01), 'T8b Q=86,87', '${p1.q}');
    final cInc = incs.firstWhere((i) => i.domain == 'espaces-verts');
    check((p1.unassigned[cInc.id] ?? '').contains('aucune équipe compétente'),
        'T8c C non affecté', p1.unassigned.toString());
  }

  // 9. Information nouvelle ne nécessitant aucune modification (doublon).
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
    check(nec.code == 'U' && !nec.necessary, 'T9 stabilité U', nec.code);
  }

  // 10. Reproductibilité à graine identique.
  {
    final a = generateDev(seed: 7);
    final b = generateDev(seed: 7);
    final ja = jsonEncode(a.reports.map((r) => r.toJson()).toList());
    final jb = jsonEncode(b.reports.map((r) => r.toJson()).toList());
    check(ja == jb, 'T10a scénario identique');
    Plan planOf(Scenario s) {
      final byId = {for (final r in s.reports) r.id: r};
      final gg = groupReports(s.reports,
          distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
      return optimizeExact(
          incidents: aggregate(gg, byId), teams: teams);
    }

    check(jsonEncode(planOf(a).toJson()) == jsonEncode(planOf(b).toJson()),
        'T10b plan identique');
  }

  // 11. Jouet-1 : F1=1 (TP=3), Q plan=100, coût=92, Q sim=100, B-cubed=1.
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
    // Main : T1 A(24)+C(16), T2 B(52) => 92 ; tout complété => Q=100.
    check(approx(p.q, 100.0), 'T11b Q plan=100', '${p.q}');
    check(approx(p.totalCost, 92.0), 'T11c coût=92', '${p.totalCost}');
    check(p.tasks.length == 3, 'T11d 3 tâches', '${p.tasks.length}');
    final sm =
        simulate(plan: p, proposed: incs, truth: sc.truth, teams: teams);
    check(sm.feasible && approx(sm.q ?? -1, 100.0), 'T11e Q sim=100',
        'q=${sm.q} v=${sm.violations}');
    check(
        sm.outcomes.every((o) => o.result == 1), 'T11f R=1 partout');
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

  // 12. Générés : regroupement parfait par construction (graines 7, 42).
  {
    for (final seed in [7, 42]) {
      final sc = generateDev(seed: seed);
      check(sc.reports.length == 20 && sc.truth.length == 8,
          'T12a 20/8 graine $seed');
      final g = groupReports(sc.reports,
          distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
      final prf = pairwiseF1(
          sc.truth.map((t) => t.reportIds).toList(),
          g.map((x) => x.reportIds).toList());
      check(prf.f1 == 1.0, 'T12b F1=1 graine $seed', prf.toJson().toString());
      final byId = {for (final r in sc.reports) r.id: r};
      final incs = aggregate(g, byId);
      final p = optimizeExact(incidents: incs, teams: teams);
      check(p.totalCost <= 120.0, 'T12c budget graine $seed',
          '${p.totalCost}');
      final sm =
          simulate(plan: p, proposed: incs, truth: sc.truth, teams: teams);
      check(sm.q != null, 'T12d Q défini graine $seed', '${sm.q}');
    }
  }

  // 13. Connecteur Meta : désactivé par défaut, jamais simulé.
  {
    final c = MetaConnector.fromEnvironment({});
    check(c.state == MetaState.unconfigured, 'T13a non configuré');
    var threw = false;
    try {
      groupWithMeta(c, []);
    } catch (_) {
      threw = true;
    }
    check(threw, 'T13b refus sans appel simulé');
  }

  // 14. Signalement manuel hors vérité : ni impureté ni violation fantôme.
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
        'T14a manuel fusionné non impur', sm.outcomes.single.reason);
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
            sm2.outcomes.single.reason.contains('hors vérité'),
        'T14b manuel seul non noté sans violation',
        '${sm2.violations} ${sm2.outcomes.single.reason}');
  }

  // 14c. Textes vides : aucune similarité fabriquée.
  check(jaccard('', '') == 0.0 && jaccard('', 'trou chaussee') == 0.0,
      'T14c Jaccard vide = 0');

  // 15. Journal : reprise après redémarrage (fichier JSONL).
  {
    final dir = Directory.systemTemp.createTempSync('cityresolve_audit');
    final path = '${dir.path}/journal.jsonl';
    AuditLog(path: path).append('test.un', {'n': 1});
    final resumed = AuditLog(path: path);
    check(resumed.entries.length == 1, 'T15a journal relu', '${resumed.entries.length}');
    resumed.append('test.deux', {'n': 2});
    check(resumed.entries.last['seq'] == 2, 'T15b séquence continue',
        '${resumed.entries.last['seq']}');
    dir.deleteSync(recursive: true);
  }

  // 16. Cas Q falaise DEV graine 7 (étape D) : estimé 118,4 -> réalisé 142,2.
  {
    final sc = generateDev(seed: 7);
    final g = groupReports(sc.reports,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final byId = {for (final r in sc.reports) r.id: r};
    final incs = aggregate(g, byId);
    final p = optimizeExact(incidents: incs, teams: teams);
    check(approx(p.totalCost, 118.4047, 0.01), 'T16a coût estimé 118,4',
        '${p.totalCost}');
    final sm =
        simulate(plan: p, proposed: incs, truth: sc.truth, teams: teams);
    check(approx(sm.totalCost, 142.2, 0.01), 'T16b coût réalisé 142,2',
        '${sm.totalCost}');
    check(!sm.feasible && sm.q == 0.0, 'T16c falaise Q=0 (politique)',
        'q=${sm.q} v=${sm.violations}');
  }

  // 17. Meta sans clé : refus explicites, aucun résultat simulé.
  {
    final c = MetaConnector.fromEnvironment({});
    check(c.state == MetaState.unconfigured, 'T17a non configuré sans clé');
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
    check(refused == 2, 'T17b extraction+rapprochement refusés', '$refused/2');
    final (vc, rec) = await c.verify();
    check(vc.state == MetaState.unconfigured && rec.status == 'refuse',
        'T17c verify sans clé = refus journalisé', rec.status);
  }

  // 18. Persistance locale : aller-retour, rotation .bak, récupération.
  {
    final dir = Directory.systemTemp.createTempSync('cityresolve_store');
    final store = JsonStore(dir.path);
    store.save({'format': 1, 'reportSeq': 101});
    var load = store.load();
    check(load.doc?['reportSeq'] == 101, 'T18a état relu', '${load.doc}');
    store.save({'format': 1, 'reportSeq': 102});
    File('${dir.path}/state.json').writeAsStringSync('{corrompu');
    load = store.load();
    check(load.recoveredFromBackup && load.doc?['reportSeq'] == 101,
        'T18b récupération .bak après corruption', '${load.doc}');
    dir.deleteSync(recursive: true);
  }

  // 19. Gravité inconnue/contradictoire : conservée, jamais dispatchée.
  {
    final r = Report(
        id: 'U1', text: 'fuite signalee', category: 'fuite-eau', x: 1, y: 1, t: 500);
    final incs = aggregate(
        [Group(id: 'G1', reportIds: ['U1'], confidence: 0, singleton: true)],
        {'U1': r});
    final i = incs.single;
    check(i.severity == null && i.severityStatus == statusInconnue,
        'T19a gravité inconnue conservée (pas de défaut catégorie)',
        'sev=${i.severity} status=${i.severityStatus}');
    check(i.deadline == -2, 'T19b pas d\'échéance fabriquée', '${i.deadline}');
    final p = optimizeExact(incidents: incs, teams: teams);
    check(p.tasks.isEmpty && (p.unassigned[i.id] ?? '').contains('gravité inconnue'),
        'T19c inconnu non dispatché', p.unassigned.toString());
    check(p.escalations.isEmpty, 'T19d inconnu non escaladé S5');
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
        'T19e contradiction explicite non effacée',
        '${cIncs.single.severityStatus} ${cIncs.single.severityValues}');
    final eReps = [
      Report(id: 'E1', text: 'a', category: 'autre', x: 1, y: 1, t: 500, severityHint: 2),
      Report(id: 'E2', text: 'b', category: 'autre', x: 1, y: 1, t: 510, severityHint: 3),
    ];
    final eIncs = aggregate([
      Group(id: 'G1', reportIds: ['E1', 'E2'], confidence: 0.5, singleton: false)
    ], {for (final x in eReps) x.id: x});
    check(eIncs.single.severity == 3 && eIncs.single.severityStatus == statusEstimee,
        'T19f valeurs proches = estimée (max)', '${eIncs.single.severityStatus}');
  }

  // 20. Regroupements incertains signalés (régressions E1/E2).
  {
    final e1 = [
      Report(id: 'A1', text: 'fuite eau rue basse trottoir inonde canalisation', category: 'fuite-eau', x: 2.0, y: 2.0, t: 500, severityHint: 3, exposureHint: 1),
      Report(id: 'A2', text: 'fuite eau rue basse trottoir inonde cassee', category: 'fuite-eau', x: 2.05, y: 2.0, t: 520, severityHint: 3, exposureHint: 1),
      Report(id: 'B1', text: 'fuite eau rue basse trottoir inonde importante', category: 'fuite-eau', x: 2.1, y: 2.0, t: 510, severityHint: 2, exposureHint: 1),
    ];
    final g1 = groupReports(e1, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(g1.length == 1 && g1.single.uncertain,
        'T20a fusion limite E1 signalée incertaine',
        '${g1.length} groupe, raisons=${g1.single.uncertaintyReasons}');
    final e2 = [
      Report(id: 'A1', text: 'trou chaussee dangereux voitures', category: 'nid-de-poule', x: 1.0, y: 1.0, t: 500, severityHint: 2, exposureHint: 1),
      Report(id: 'A2', text: 'excavation bitume perilleuse automobiles', category: 'nid-de-poule', x: 1.0, y: 1.0, t: 510, severityHint: 2, exposureHint: 1),
    ];
    final g2 = groupReports(e2, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final amb = ambiguousPairs(e2, g2,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(g2.length == 2 && amb.any((a) => a['a'] == 'A1' && a['b'] == 'A2'),
        'T20b séparation E2 signalée ambiguë', '$amb');
  }

  // 21. Connecteur Meta contre un stub HTTP LOCAL de test (plumbing,
  // pas un résultat Meta) : vérification, extraction, délai, mauvaise clé.
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
                    'justification': 'stub local de test',
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
                'description': 'stub local de test',
                'localisationMentionnee': null,
                'graviteExprimee': null,
                'expositionMentionnee': null,
                'incertitudes': ['gravité non exprimée'],
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
        'T21a verify stub -> modèles réels de la réponse', '${vc.models}');
    check(vrec.status == 'ok' && vrec.latencyMs >= 0, 'T21b appel journalisé');
    final rep = Report(
        id: 'R1', text: 'trou rue basse', category: 'autre', x: 1, y: 1, t: 500);
    final ext = await extractStructuredWithMeta(vc, rep);
    check(ext['graviteExprimee'] == null && (ext['incertitudes'] as List).isNotEmpty,
        'T21c extraction parsée, incertitude conservée', '$ext');
    final reps = [
      rep,
      Report(id: 'R2', text: 'trou rue basse bis', category: 'autre', x: 1, y: 1, t: 510),
    ];
    final mg = await proposeMatchingWithMeta(vc, reps);
    check(mg.length == 1 && mg.single.method == 'meta' && mg.single.reportIds.length == 2,
        'T21d rapprochement -> Group method=meta', '${mg.map((g) => g.toJson())}');
    var timeoutSeen = false;
    try {
      await extractStructuredWithMeta(
          vc,
          Report(id: 'LENT', text: 'LENT', category: 'autre', x: 1, y: 1, t: 1),
          timeout: const Duration(milliseconds: 200));
    } on MetaException {
      timeoutSeen = true;
    }
    check(timeoutSeen, 'T21e délai dépassé -> MetaException explicite');
    final bad = MetaConnector.fromEnvironment(
        {...env, 'LLAMA_API_KEY': 'wrong-key'});
    final (bc, _) = await bad.verify();
    check(bc.state == MetaState.accessError, 'T21f mauvaise clé -> erreur accès');
    final empty = MetaConnector.fromEnvironment(
        {...env, 'LLAMA_API_KEY': 'empty-key'});
    final (ec, _) = await empty.verify();
    check(ec.state == MetaState.accessError && ec.models.isEmpty,
        'T21g clé acceptée mais 0 modèle autorisé -> accès indisponible');
    await sub.cancel();
    await stub.close(force: true);
  }

  // 22. Régression fournisseur Meta Model API officiel.
  {
    final def = MetaConnector.fromEnvironment({});
    check(def.baseUrl == 'https://api.meta.ai/v1',
        'T22a base officielle api.meta.ai par défaut', def.baseUrl);
    check(def.baseUrl != 'https://api.llama.com/v1',
        'T22b ancien domaine llama.com non utilisé');
    final primary = MetaConnector.fromEnvironment({
      'MODEL_API_KEY': 'cle-primaire',
      'LLAMA_API_KEY': 'cle-legacy',
    });
    check(primary.keySource == 'MODEL_API_KEY',
        'T22c MODEL_API_KEY prioritaire sur alias', '${primary.keySource}');
    final alias = MetaConnector.fromEnvironment({'LLAMA_API_KEY': 'cle-legacy'});
    check(alias.keySource == 'LLAMA_API_KEY',
        'T22d alias historique explicite en repli', '${alias.keySource}');
    check(
        metaHttpErrorLabel(401).contains('authentification') &&
            metaHttpErrorLabel(402).contains('paiement') &&
            metaHttpErrorLabel(403).contains('autorisation') &&
            metaHttpErrorLabel(404).contains('introuvable') &&
            metaHttpErrorLabel(429).contains('limite') &&
            metaHttpErrorLabel(503).contains('temporaire'),
        'T22e erreurs HTTP distinguées');
  }

  // 23. Verrou mono-instance (patch local) : second serveur refusé.
  {
    final tmp = Directory.systemTemp.createTempSync('cityresolve-lock-');
    try {
      final first = tryAcquireServerLock(tmp.path);
      check(first.acquired, 'T23a premier serveur acquiert le verrou');
      final second = tryAcquireServerLock(tmp.path);
      check(!second.acquired && second.holderPid == pid,
          'T23b second serveur refusé, PID du premier signalé',
          'holderPid=${second.holderPid}');
      releaseServerLock(first.path);
      final third = tryAcquireServerLock(tmp.path);
      check(third.acquired, 'T23c verrou libéré puis réacquis');
      releaseServerLock(third.path);
    } finally {
      tmp.deleteSync(recursive: true);
    }
  }

  // 24. Garde-fou contenu insuffisant (poussé sur main).
  {
    Report rep(String id, String text) => Report(
        id: id, text: text, category: 'autre', x: 1.0, y: 1.0, t: 500);
    // T24a : deux textes vides ne fusionnent pas.
    final gVide = groupReports([rep('V1', ''), rep('V2', '')],
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(gVide.length == 2 && gVide.every((g) => g.singleton),
        'T24a deux textes vides ne fusionnent pas', gVide.toString());
    check(gVide.every((g) =>
        g.uncertain && g.uncertaintyReasons.contains(guardrailReason)),
        'T24a-bis singletons vides marqués garde-fou',
        gVide.map((g) => g.uncertaintyReasons).toString());
    // T24b : texte vide contre texte non vide ne fusionne pas.
    final gMix = groupReports(
        [rep('V1', ''), rep('N1', 'nid poule rue lilas chaussee degradee')],
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(gMix.length == 2 && gMix.every((g) => g.singleton),
        'T24b vide contre non vide ne fusionne pas', gMix.toString());
    // T24c : un seul caractère ne fusionne pas (même identique des deux côtés).
    final gChar = groupReports([rep('C1', 'a'), rep('C2', 'a')],
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(gChar.length == 2 && gChar.every((g) => g.singleton),
        'T24c un seul caractère ne fusionne pas', gChar.toString());
    // T24d : ponctuation/espaces seuls ne fusionnent pas.
    final gPonct = groupReports([rep('P1', '!!!'), rep('P2', '   ')],
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(gPonct.length == 2 && gPonct.every((g) => g.singleton),
        'T24d ponctuation seule ne fusionne pas', gPonct.toString());
    // T24e : texte normal non affecté (deux textes normaux identiques fusionnent).
    final gNorm = groupReports(
        [
          rep('N1', 'nid poule rue lilas chaussee degradee'),
          rep('N2', 'nid poule rue lilas chaussee degradee')
        ],
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(gNorm.length == 1 && !gNorm.single.singleton,
        'T24e texte normal non affecté', gNorm.toString());
    // T24f : le filtre post-modèle annule une fusion proposée par un
    // modèle (cas inc-vide de phase4-hard : deux vides fusionnés).
    final fakeMeta = [
      Group(
          id: 'G1',
          reportIds: ['V1', 'V2'],
          confidence: 0.0,
          singleton: false,
          method: 'meta',
          uncertain: true,
          uncertaintyReasons: ['incertitude modèle 1.00'],
          justification: 'aucune preuve positive'),
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
        'T24f une fusion annulée comptée', '${filtered.cancelledMerges}');
    check(filtered.groups.length == 3 &&
        filtered.groups.every((g) => g.singleton),
        'T24f fusion annulée -> 3 singletons', filtered.groups.toString());
    check(filtered.groups
            .where((g) => g.reportIds.first.startsWith('V'))
            .every((g) => g.uncertaintyReasons.contains(guardrailReason)),
        'T24f singletons annulés marqués garde-fou',
        filtered.groups.map((g) => g.uncertaintyReasons).toString());
    // T24g : le filtre ne touche pas un groupe normal.
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
              justification: 'même nid-de-poule')
        ]);
    check(kept.cancelledMerges == 0 && kept.groups.length == 1,
        'T24g groupe normal conservé', kept.groups.toString());
  }

  // 25. Patch unités / statuts / porte temps (poussé sur main).
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
        justification: 'proposition modele');
    // T25a : le listing serveur donne les unités, partout.
    final listing = metaListingWithUnits([
      repCat('B1', 'nid poule rue lilas chaussee degradee', 'nid-de-poule',
          1.0, 1.0, 500),
      repCat('B2', 'nid poule rue lilas chaussee degradee important',
          'nid-de-poule', 1.0, 1.0, 4820),
    ]);
    check(listing.contains('km') && listing.contains('min') &&
        listing.contains('4320 min = 3,0 jours') &&
        listing.contains('0,00 km'),
        'T25a listing avec unités explicites', listing);
    // T25b : la porte temps découpe distinct-temps (3 jours, local).
    final temps = [
      repCat('B1', 'nid poule rue lilas chaussee degradee', 'nid-de-poule',
          1.0, 1.0, 500),
      repCat('B2', 'nid poule rue lilas chaussee degradee important',
          'nid-de-poule', 1.0, 1.0, 4820),
    ];
    final gated = applyMetaTimeGate(temps, [fakeGroup(['B1', 'B2'])]);
    check(gated.splitGroups == 1 && gated.groups.length == 2 &&
        gated.groups.every((g) => g.singleton),
        'T25b porte temps découpe distinct-temps', gated.toString());
    check(gated.groups.every((g) =>
        g.uncertaintyReasons.any((r) => r.contains('porte-temps-meta'))),
        'T25b-bis découpes tracées porte-temps-meta',
        gated.groups.map((g) => g.uncertaintyReasons).toString());
    // T25c : l'exception étendue ne découpe PAS une coupure réseau
    // persistante (5000 min < 10080 min).
    final etendu = [
      repCat('P1', 'coupure electrique quartier ouest', 'coupure-electrique',
          1.0, 1.0, 500),
      repCat('P2', 'coupure electrique quartier ouest ascenseurs',
          'coupure-electrique', 1.0, 1.0, 5500),
    ];
    final kept = applyMetaTimeGate(etendu, [fakeGroup(['P1', 'P2'])]);
    check(kept.splitGroups == 0 && kept.groups.length == 1 &&
        !kept.groups.single.singleton,
        'T25c événement étendu non découpé', kept.toString());
    // T25d : catégorie mixte -> seuil local conservateur (découpe).
    final mixte = [
      repCat('M1', 'nid poule rue lilas', 'nid-de-poule', 1.0, 1.0, 500),
      repCat('M2', 'coupure electrique quartier ouest', 'coupure-electrique',
          1.0, 1.0, 1000),
    ];
    final mixGated = applyMetaTimeGate(mixte, [fakeGroup(['M1', 'M2'])]);
    check(mixGated.splitGroups == 1,
        'T25d catégorie mixte -> seuil local', mixGated.toString());
    // T25e : statut contradictoire (résolu contre en cours).
    final contra = [
      repCat('A1', 'fuite eau rue basse trottoir sec travaux termines fuite resolue',
          'fuite-eau', 2.0, 2.0, 500, sev: 2, exp: 1),
      repCat('A2', 'fuite eau rue basse trottoir inonde eau coule',
          'fuite-eau', 2.0, 2.0, 520, sev: 3, exp: 2),
    ];
    final flagged = applyGroupStatuses(contra, [fakeGroup(['A1', 'A2'])]);
    check(flagged.contradictoryGroups == 1,
        'T25e groupe contradictoire compté', flagged.toString());
    check(flagged.groups.length == 1 &&
        flagged.groups.single.reportIds.toSet().containsAll(['A1', 'A2']),
        'T25e-bis statut ne découpe pas le groupe',
        flagged.groups.toString());
    check(flagged.groups.single.uncertain &&
        flagged.groups.single.uncertaintyReasons
            .any((r) => r.contains('statut-contradictoire')),
        'T25e-ter groupe marqué statut-contradictoire',
        flagged.groups.single.uncertaintyReasons.toString());
    // T25f : drapeau multi-problème (E1) ; cas simple non signalé.
    final multi = [
      repCat('E1', 'nid poule rue lilas chaussee degradee reverbere eteint',
          'nid-de-poule', 1.0, 1.0, 500),
      repCat('E2', 'nid poule rue lilas chaussee degradee', 'nid-de-poule',
          1.0, 1.0, 510),
    ];
    final mFlag = applyGroupStatuses(multi, [fakeGroup(['E1', 'E2'])]);
    check(mFlag.multiProblemGroups == 1,
        'T25f groupe multi-problème compté', mFlag.toString());
    check(mFlag.groups.single.uncertaintyReasons
        .any((r) => r.contains('drapeau-multi-probleme') && r.contains('E1')),
        'T25f-bis drapeau cite E1',
        mFlag.groups.single.uncertaintyReasons.toString());
    final simple = applyGroupStatuses(
        multi, [fakeGroup(['E2'])]);
    check(simple.multiProblemGroups == 0 && simple.contradictoryGroups == 0,
        'T25f-ter cas simple non signalé', simple.toString());
    // T25g : les statuts seuls ne changent pas les reportIds.
    final keptIds = applyGroupStatuses(multi, [fakeGroup(['E1', 'E2'])]);
    check(keptIds.groups.single.reportIds.length == 2,
        'T25g statuts conservent les reportIds', keptIds.toString());
    // T25h : non-régression E4 (doublon distant signalé, non fusionné).
    final e4 = [
      repCat('R1', 'nid poule rue lilas', 'nid-de-poule', 1.0, 1.0, 500),
      repCat('R2', 'nid poule rue lilas', 'nid-de-poule', 7.5, 1.0, 510),
    ];
    final gE4 = groupReports(e4,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final amb = ambiguousPairs(e4, gE4,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    check(gE4.length == 2,
        'T25h E4 séparé, non fusionné', gE4.toString());
    check(amb.any((a) =>
        (a['reason'] as String).contains('doublon distant')),
        'T25h-bis E4 doublon distant signalé', amb.toString());
  }

  // 26. Découpage multi-problème (patch local, poussé sur main).
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
    // T26a : cas d'origine, E1 deux problèmes + E2 nid seul.
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
        'T26a origine découpée en 2 groupes', idsSplit.toString());
    check(idsSplit.any((g) =>
            g.toSet().containsAll(['E1:voirie-nid', 'E2:voirie-nid'])) &&
        idsSplit.any((g) => g.length == 1 && g.single == 'E1:eclairage'),
        'T26a-bis éclairage survit en incident propre',
        idsSplit.toString());
    final byIdOrig = {for (final r in origine) r.id: r};
    final incSplit = aggregateSplitGroups(gSplit, byIdOrig);
    check(incSplit.length == 2,
        'T26a-ter 2 incidents pour l’optimiseur', incSplit.toString());
    check(incSplit.any((i) => i.reportIds.single == 'E1:eclairage'),
        'T26a-quater incident éclairage traçable', incSplit.toString());
    // T26b : un seul signalement à deux problèmes -> 2 incidents.
    final seul = [
      repS('M1', 'fuite eau rue basse trottoir inonde reverbere eteint')
    ];
    final gSeul = groupSplitReports(seul, distMaxM: dDist, deltaTMaxH: dDt);
    check(gSeul.length == 2,
        'T26b signalement seul découpé en 2', gSeul.toString());
    // T26c : même problème deux fois -> pas de découpage.
    final faux = [
      repS('N1', 'nid poule rue lilas chaussee degradee trou grand')
    ];
    final gFaux = groupSplitReports(faux, distMaxM: dDist, deltaTMaxH: dDt);
    check(gFaux.length == 1 && gFaux.single.reportIds.single == 'N1:voirie-nid',
        'T26c faux multi-problème non découpé', gFaux.toString());
    // T26d : mention vague -> pas de découpage automatique.
    final vague = [
      repS('V1',
          'nid poule rue lilas chaussee degradee quelque chose aussi la nuit')
    ];
    final gVague =
        groupSplitReports(vague, distMaxM: dDist, deltaTMaxH: dDt);
    check(gVague.length == 1,
        'T26d vague non découpé automatiquement', gVague.toString());
    // T26e : trois problèmes -> 3 incidents.
    final trois = [
      repS('T1',
          'nid poule rue lilas chaussee degradee reverbere eteint fuite eau trottoir inonde')
    ];
    final gTrois =
        groupSplitReports(trois, distMaxM: dDist, deltaTMaxH: dDt);
    check(gTrois.length == 3,
        'T26e trois problèmes découpés en 3', gTrois.toString());
    // T26f : post-filtre sur le groupe classique [E1, E2].
    final gClass = groupReports(origine,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final post = splitGroupsByFamily(origine, gClass);
    check(post.splitGroups == 1 && post.groups.length == 2,
        'T26f post-filtre découpe le groupe classique',
        post.groups.toString());
    // T26g : réversibilité, chaque sous-signalement retrouve son origine.
    final units = expandToSubunits(origine);
    check(units.every((u) => byIdOrig.containsKey(u.originId)) &&
        units.map((u) => u.originId).toSet().containsAll(['E1', 'E2']),
        'T26g origines récupérables', units.map((u) => u.id).toString());
    // T26h : famille inconnue ne fusionne jamais.
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
        'T26h inconnus jamais fusionnés', gInc.toString());
  }

  // 27. Branchement serveur du découpage (lib) : agrégation mixte.
  // Le routage serveur lui-même (bin/server.dart) n'est pas importable
  // par ce harnais de tests lib : il est vérifié sur serveur réel via
  // le runbook (méthode 'split', split:true). Ici, on prouve le contrat
  // sur lequel le serveur s'appuie : aggregateMixedGroups, la
  // détection des identifiants découpés, et la persistance aller-retour.
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
    // T27a : un groupe découpé agrégé en mixte donne 2 incidents
    // (voirie + éclairage), pas 1, et le plein reste un incident propre.
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
        'T27a mixte découpé donne 3 incidents', mixed.toString());
    check(mixed.map((i) => i.id).toSet().length == 3,
        'T27a-bis identifiants incidents uniques', mixed.toString());
    check(mixed.any((i) => i.reportIds.single == 'E1:eclairage'),
        'T27a-ter éclairage survit en incident propre', mixed.toString());
    // T27b : l'origine est récupérable depuis chaque incident découpé.
    check(mixed
            .where((i) => i.reportIds.any((id) => id.contains(':')))
            .every((i) => i.reportIds
                .every((id) => byId.containsKey(originIdOfSubunit(id)))),
        'T27b origines récupérables depuis incidents découpés',
        mixed.toString());
    // T27c : chemin non découpé strictement identique à l'ancien.
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
        'T27c non découpé identique à aggregate()',
        '${incClassic.length} vs ${incMixedPlain.length}');
    // T27d : ancien état sans sous-signalements reste lisible, et un
    // état découpé survit à un aller-retour JSON (format 1, inchangé).
    final restoredPlain = gPlain
        .map((g) => Group.fromJson(g.toJson()))
        .toList();
    final restoredSplit = gSplit
        .map((g) => Group.fromJson(g.toJson()))
        .toList();
    check(restoredPlain.every((g) => !groupUsesSplitIds(g)) &&
        restoredSplit.any(groupUsesSplitIds),
        'T27d aller-retour JSON conserve les identifiants découpés',
        restoredSplit.toString());
    check(aggregateMixedGroups(restoredSplit, byId).length == 2,
        'T27d-bis état découpé restauré donne toujours 2 incidents',
        restoredSplit.toString());
    // T27e : détection des identifiants découpés (prédicat du serveur).
    check(groupUsesSplitIds(gSplit.first) &&
        !groupUsesSplitIds(plain.first) &&
        groupsUseSplitIds([...gSplit, ...plain]) &&
        !groupsUseSplitIds(plain),
        'T27e détection split/plain correcte', '');
    // T27f : l'appariement vérité d'un incident découpé exige la
    // projection vers l'origine : brut, l'intersection est vide.
    final splitInc = mixed.firstWhere(
        (i) => i.reportIds.single == 'E1:eclairage');
    check(splitInc.reportIds.toSet().intersection({'E1'}).isEmpty &&
        splitInc.reportIds
                .map(originIdOfSubunit)
                .toSet()
                .intersection({'E1'})
                .isNotEmpty,
        'T27f vérité liée via origine, pas via identifiant brut', '');
  }

  // T28 : médias — validation par octets magiques, jamais par extension.
  {
    check(validateImageBytes([0xFF, 0xD8, 0xFF, 0x00, 0x10]) == 'jpg',
        'T28a JPEG détecté');
    check(
        validateImageBytes(
                [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]) ==
            'png',
        'T28b PNG détecté');
    check(validateImageBytes([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]) == 'gif',
        'T28c GIF détecté');
    check(
        validateImageBytes([
          0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00,
          0x57, 0x45, 0x42, 0x50
        ]) ==
            'webp',
        'T28d WebP détecté');
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
    check(refused == 3, 'T28e PDF/vide/surdimensionné refusés');
    final id = newMediaId();
    check(isMediaId(id) && !isMediaId('../$id') && !isMediaId('photo.jpg'),
        'T28f mediaId strict (anti chemin)', id);
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
    check(traversal == 2, 'T28h traversal/extension bloqués');
  }

  // T29 : corps de requête chat — images uniquement en message user.
  {
    final txt = MetaConnector.buildChatRequest(
        model: 'm', system: 's', user: 'u');
    final msgs = txt['messages'] as List;
    check((msgs[1]['content'] as String) == 'u',
        'T29a texte seul reste une chaîne');
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
        'T29b image en data URL dans le message user');
    check(((withImg['messages'] as List)[0]['content'] as String) == 's',
        'T29c système sans image (jamais de 400)');
    final okAnalysis = {
      'observationsVisibles': ['déchets près du caniveau', 'eau présente'],
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
      'incertitudes': ['degré d\'obstruction non confirmé'],
    };
    check(validateVisualAnalysis(okAnalysis) == null,
        'T29d contrat visuel valide accepté');
    check(
        validateVisualAnalysis({
              'observationsVisibles': ['x'],
              'problemesPossibles': [],
              'incertitudes': [],
            }) !=
            null,
        'T29e incertitudes vides refusées');
    check(
        validateVisualAnalysis({
              'observationsVisibles': [],
              'problemesPossibles': [],
              'incertitudes': ['?'],
            }) !=
            null,
        'T29f observations vides refusées');
  }

  // T30 : démo §8 — « caniveau + lampadaires » : deux problèmes conservés.
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
        'T30a deux familles détectées', '$fams');
    check(hasMultiProblem(r), 'T30b multi-problème signalé');
    final gs = groupSplitReports([r], distMaxM: 250.0, deltaTMaxH: 6.0);
    check(gs.length == 2 && gs.every((g) => g.method == 'split'),
        'T30c découpage en 2 groupes split',
        gs.map((g) => g.reportIds).toString());
    final incs = aggregateMixedGroups(gs, {'DEMO8': r});
    check(incs.length == 2, 'T30d aucun problème perdu', '${incs.length}');
    final doms = incs.map((i) => i.domain).toSet();
    check(doms.contains('reseaux') && doms.contains('voirie'),
        'T30e domaines distincts (assainissement→reseaux)', '$doms');
    check(incs.every((i) => i.severity == null),
        'T30f gravité inconnue conservée sur les deux volets');
  }

  print('== $_pass PASS, $_fail FAIL ==');
  if (_fail > 0) throw StateError('$_fail test(s) en échec.');
}
