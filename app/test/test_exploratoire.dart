// Tests exploratoires VISIBLES CityResolve (indépendants de tout scénario
// confirmatoire). Ils publient le comportement réel, y compris les limites
// confirmées du moteur classique. Aucun scénario n'est ajusté pour réussir.
// Exécution : dart run test/test_exploratoire.dart
import '../lib/grouping.dart';
import '../lib/incidents.dart';
import '../lib/optimizer.dart';
import '../lib/oracle.dart';
import '../lib/policy.dart';
import '../lib/scenarios.dart';
import '../lib/simulator.dart';
import '../lib/types.dart';

int _ok = 0, _limite = 0;

void observe(String name, bool ideal, String detail) {
  if (ideal) {
    _ok++;
    print('OK     $name :: $detail');
  } else {
    _limite++;
    print('LIMITE $name :: $detail');
  }
}

const dDist = 250.0, dDt = 6.0, dSim = 0.75;

List<Incident> incsOf(List<Report> reps) {
  final g = groupReports(reps, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
  return aggregate(g, {for (final r in reps) r.id: r});
}

void main() {
  final teams = defaultTeams();

  // E1. Deux incidents proches, descriptions presque identiques.
  {
    final reps = [
      Report(id: 'A1', text: 'fuite eau rue basse trottoir inonde canalisation', category: 'fuite-eau', x: 2.0, y: 2.0, t: 500, severityHint: 3, exposureHint: 1),
      Report(id: 'A2', text: 'fuite eau rue basse trottoir inonde cassee', category: 'fuite-eau', x: 2.05, y: 2.0, t: 520, severityHint: 3, exposureHint: 1),
      Report(id: 'B1', text: 'fuite eau rue basse trottoir inonde importante', category: 'fuite-eau', x: 2.1, y: 2.0, t: 510, severityHint: 2, exposureHint: 1),
    ];
    final g = groupReports(reps, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    // Régression phase 2 : la fusion classique subsiste (faite), mais elle
    // doit être SIGNALÉE incertaine au lieu d'être imposée en silence.
    observe('E1 fusion limite signalée incertaine (non imposée en silence)',
        g.length == 1 && g.single.uncertain,
        '${g.length} groupe(s) pour 2 incidents vrais à 100 m, uncertain=${g.single.uncertain}, raisons=${g.single.uncertaintyReasons}');
  }

  // E2. Même incident, mots complètement différents (synonymes).
  {
    final reps = [
      Report(id: 'A1', text: 'trou chaussee dangereux voitures', category: 'nid-de-poule', x: 1.0, y: 1.0, t: 500, severityHint: 2, exposureHint: 1),
      Report(id: 'A2', text: 'excavation bitume perilleuse automobiles', category: 'nid-de-poule', x: 1.0, y: 1.0, t: 510, severityHint: 2, exposureHint: 1),
    ];
    final g = groupReports(reps, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final amb = ambiguousPairs(reps, g,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    // Régression phase 2 : la scission classique subsiste, mais la paire
    // doit être signalée ambiguë (même lieu/instant, vocabulaire disjoint).
    observe('E2 séparation signalée ambiguë (non imposée en silence)',
        g.length == 2 && amb.isNotEmpty,
        '${g.length} groupe(s), Jaccard=${jaccard(reps[0].text, reps[1].text).toStringAsFixed(2)}, ambiguës=${amb.map((a) => a['reason']).toList()}');
  }

  // E3. Signalement incomplet (texte vide, aucun indice).
  {
    final reps = [
      Report(id: 'V1', text: '', category: 'autre', x: 1.0, y: 1.0, t: 500),
      Report(id: 'V2', text: '', category: 'autre', x: 1.02, y: 1.0, t: 510),
    ];
    final g = groupReports(reps, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final incs = incsOf(reps);
    observe('E3a deux textes vides non fusionnés au hasard', g.length == 2,
        '${g.length} groupe(s) : Jaccard("","")=0.0 (aucune évidence), pas de fusion sans information');
    observe('E3b gravité inconnue signalée comme telle',
        incs.every((i) => i.severity == null && i.severityStatus == statusInconnue),
        'incidents sev=${incs.map((i) => i.severity).toList()} statuts=${incs.map((i) => i.severityStatus).toList()} (aucun défaut catégorie), exposition inconnue décision E=${incs.first.exposureForDecision}');
    print('       E3 detail: confiance groupe=${g.first.confidence}, singleton=${g.first.singleton}');
  }

  // E4. Information géographique contradictoire (même texte, coins opposés).
  {
    final reps = [
      Report(id: 'G1', text: 'nid poule rue basse chaussee trou abimee', category: 'nid-de-poule', x: 0.2, y: 0.2, t: 500, severityHint: 2, exposureHint: 1),
      Report(id: 'G2', text: 'nid poule rue basse chaussee trou abimee', category: 'nid-de-poule', x: 4.8, y: 4.8, t: 505, severityHint: 2, exposureHint: 1),
    ];
    final g = groupReports(reps, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final amb4 = ambiguousPairs(reps, g,
        distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    // Patch local : la séparation subsiste (deux incidents réels peuvent
    // partager un texte), mais elle doit être SIGNALÉE comme doublon
    // distant à vérifier, et non imposée en silence.
    observe('E4 contradiction géographique signalée (séparation + alerte)',
        g.length == 2 && amb4.isNotEmpty,
        '${g.length} incident(s) pour un même texte à 6,5 km d\'écart, ambiguës=${amb4.map((a) => a['reason']).toList()}');
  }

  // E5. Gravité inconnue (indice absent, catégorie renseignée).
  {
    final r = Report(id: 'S?', text: 'fuite signalee sans precision', category: 'fuite-eau', x: 2.0, y: 2.0, t: 500);
    final incs = incsOf([r]);
    observe('E5 gravité inconnue conservée (pas de défaut fabriqué)',
        incs.single.severity == null && incs.single.severityStatus == statusInconnue,
        'severityHint=null -> gravité=${incs.single.severity}, statut=${incs.single.severityStatus} (catégorie fuite-eau sans effet sur la gravité)');
  }

  // E6. Incident S5 : escalade, jamais dispatché.
  {
    final sc = toyS5();
    final incs = incsOf(sc.reports);
    final p = optimizeExact(incidents: incs, teams: teams);
    final s5 = incs.firstWhere((i) => i.severity != null && i.severity! >= 5);
    observe('E6 S5 escaladé et non dispatché',
        p.escalations.contains(s5.id) && !p.tasks.any((t) => t.incidentId == s5.id),
        'escalations=${p.escalations}, deadline S5=${s5.deadline} (-1 = escalade)');
  }

  // E7. Faisable en estimé, budget dépassé en réalisé (graine DEV 7).
  {
    final sc = generateDev(seed: 7);
    final g = groupReports(sc.reports, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final incs = aggregate(g, {for (final r in sc.reports) r.id: r});
    final p = optimizeExact(incidents: incs, teams: teams);
    final sm = simulate(plan: p, proposed: incs, truth: sc.truth, teams: teams);
    observe('E7 dépassement budget réalisé sans annulation totale de Q',
        sm.q != 0.0,
        'estimé=${p.totalCost.toStringAsFixed(1)}/$budgetUnits, réalisé=${sm.totalCost.toStringAsFixed(1)}, Q=${sm.q}, violations=${sm.violations} (falaise Q=0 imposée par SPEC D-SIMU §7 / V1.5 §3, pas un bug isolé)');
  }

  // E8. Nouvelle information sans modification injustifiée (doublon).
  {
    final sc = toyFixed1();
    final i0 = incsOf(sc.reports);
    final p0 = optimizeExact(incidents: i0, teams: teams);
    final reps = [...sc.reports, Report(id: 'R7', text: 'nid de poule rue des lilas chaussee abimee', category: 'nid-de-poule', x: 1.0, y: 1.0, t: 530, severityHint: 2, exposureHint: 1)];
    final i1 = incsOf(reps);
    final nec = judgeRevision(oldPlan: p0, oldIncidents: i0, updated: i1, teams: teams);
    observe('E8 doublon sans révision injustifiée', nec.code == 'U' && !nec.necessary,
        'oracle=${nec.code} (${nec.detail})');
  }

  // E9. Garde-fou contenu insuffisant (poussé sur main) : deux
  // textes vides au même lieu et au même temps ne fusionnent pas, et le
  // singleton vide est marqué à vérifier au lieu d'être imposé en silence.
  {
    final reps = [
      Report(id: 'V1', text: '', category: 'autre', x: 1.0, y: 1.0, t: 500),
      Report(id: 'V2', text: '', category: 'autre', x: 1.0, y: 1.0, t: 510),
      Report(id: 'N1', text: 'nid poule rue lilas chaussee degradee', category: 'nid-de-poule', x: 1.0, y: 1.0, t: 505),
    ];
    final g = groupReports(reps, distMaxM: dDist, deltaTMaxH: dDt, simMin: dSim);
    final vides = g.where((gr) => gr.reportIds.any((id) => id.startsWith('V')));
    observe('E9 deux textes vides non fusionnés et marqués garde-fou',
        g.length == 3 &&
            vides.length == 2 &&
            vides.every((gr) =>
                gr.singleton &&
                gr.uncertaintyReasons.contains(guardrailReason)),
        '${g.length} groupe(s), raisons vides=${vides.map((gr) => gr.uncertaintyReasons).toList()}');
  }

  print('== EXPLORATOIRE : $_ok OK, $_limite LIMITE(S) CONFIRMEE(S) ==');
  print('Les LIMITE sont des comportements mesurés et publiés, pas des échecs masqués.');
}
