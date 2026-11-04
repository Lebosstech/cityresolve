// Tableau de bord municipal : agrégats purs et documentés.
//
// Toutes les fonctions ici sont pures (entrées -> sorties) et unit-testées.
// Elles travaillent sur l'état de travail en mémoire (borné) : aucune
// lecture Mongo, aucun scan complet. Règles d'honnêteté :
// - jamais de pourcentage inventé (évolution calculée ou absente) ;
// - statuts exclusifs et définis (voir incidentStatusBuckets) ;
// - périodes calculées sur les horodatages réels (receivedAt des
//   signalements, `at` du journal) ; les données de scénario sans date
//   sont exclues des fenêtres bornées (documenté, jamais estimé).
import 'grouping.dart';
import 'optimizer.dart';
import 'security.dart';
import 'types.dart';

/// Fenêtre demandée. 'all' = tout l'historique. 'custom' exige from/to.
class Period {
  final String kind; // today | 7d | 30d | all | custom
  final DateTime? from;
  final DateTime? to;
  const Period(this.kind, {this.from, this.to});
}

Period parsePeriod(String? kind, String? fromIso, String? toIso) {
  final k = (kind ?? 'all').trim();
  if (k == 'custom') {
    final from = DateTime.tryParse(fromIso ?? '');
    final to = DateTime.tryParse(toIso ?? '');
    if (from == null || to == null || !from.isBefore(to)) {
      throw FormatException('période personnalisée invalide (from/to ISO requis)');
    }
    return Period(k, from: from.toUtc(), to: to.toUtc());
  }
  if (!{'today', '7d', '30d', 'all'}.contains(k)) {
    throw FormatException('période inconnue : $k');
  }
  return Period(k);
}

/// Bornes [début, fin) d'une fenêtre, et de la fenêtre précédente
/// (même durée, juste avant) pour l'évolution. null = sans borne.
({DateTime? start, DateTime? end, DateTime? prevStart, DateTime? prevEnd})
periodBounds(Period p, DateTime nowUtc) {
  if (p.kind == 'all') return (start: null, end: null, prevStart: null, prevEnd: null);
  if (p.kind == 'custom') {
    final dur = p.to!.difference(p.from!);
    return (
      start: p.from,
      end: p.to,
      prevStart: p.from!.subtract(dur),
      prevEnd: p.from
    );
  }
  final days = p.kind == 'today' ? 1 : (p.kind == '7d' ? 7 : 30);
  final end = nowUtc;
  final start = end.subtract(Duration(days: days));
  return (
    start: start,
    end: end,
    prevStart: start.subtract(Duration(days: days)),
    prevEnd: start
  );
}

bool _inWindow(String? iso, DateTime? start, DateTime? end) {
  if (iso == null) return start == null; // sans date : que dans 'all'
  final t = DateTime.tryParse(iso)?.toUtc();
  if (t == null) return false;
  if (start != null && t.isBefore(start)) return false;
  if (end != null && !t.isBefore(end)) return false;
  return true;
}

/// KPI signalements sur la fenêtre + fenêtre précédente (évolution
/// calculée, jamais inventée : null si la référence est vide).
Map<String, dynamic> reportsKpi(
    List<Report> reports, DateTime? start, DateTime? end,
    DateTime? prevStart, DateTime? prevEnd) {
  final cur = reports.where((r) => _inWindow(r.receivedAt, start, end)).length;
  double? deltaPct;
  int? prev;
  if (start != null) {
    prev = reports.where((r) => _inWindow(r.receivedAt, prevStart, prevEnd)).length;
    if (prev > 0) deltaPct = 100.0 * (cur - prev) / prev;
  }
  return {'count': cur, 'previousCount': prev, 'deltaPct': deltaPct};
}

/// Statuts d'incidents EXCLUSIFS (somme = total) :
/// - escalade-s5 : gravité déclarée 5 (jamais dispatché) ;
/// - planifie : présent dans les tâches du plan courant ;
/// - non-affecte : un plan existe mais l'incident n'y figure pas ;
/// - a-analyser : aucun plan courant (regroupé, en attente de planification).
/// Hors plan, tout incident non-S5 est « à analyser » : ce n'est pas un
/// échec, c'est l'état normal avant planification.
Map<String, dynamic> incidentStatusBuckets(
    List<Incident> incidents, Plan? plan) {
  final planned =
      plan == null ? <String>{} : plan.tasks.map((t) => t.incidentId).toSet();
  final counts = {
    'escalade-s5': 0,
    'planifie': 0,
    'non-affecte': 0,
    'a-analyser': 0,
  };
  for (final i in incidents) {
    if (i.severity != null && i.severity! >= 5) {
      counts['escalade-s5'] = counts['escalade-s5']! + 1;
    } else if (planned.contains(i.id)) {
      counts['planifie'] = counts['planifie']! + 1;
    } else if (plan != null) {
      counts['non-affecte'] = counts['non-affecte']! + 1;
    } else {
      counts['a-analyser'] = counts['a-analyser']! + 1;
    }
  }
  final total = incidents.length;
  double pct(int n) => total == 0 ? 0.0 : 100.0 * n / total;
  return {
    'total': total,
    'buckets': [
      for (final k in ['escalade-s5', 'planifie', 'non-affecte', 'a-analyser'])
        {'status': k, 'count': counts[k], 'pct': pct(counts[k]!)},
    ],
  };
}

/// Priorité d'affichage dérivée de la gravité DÉCLARÉE uniquement.
/// S5 = Critique (escalade, jamais dans un plan) ; inconnue = À vérifier.
String priorityOf(Incident i) {
  final s = i.severity;
  if (s == null) return 'a-verifier';
  if (s >= 5) return 'critique';
  if (s == 4) return 'haute';
  if (s == 3) return 'moyenne';
  return 'faible';
}

const Map<String, String> priorityLabels = {
  'critique': 'Critique (S5, escalade)',
  'haute': 'Haute',
  'moyenne': 'Moyenne',
  'faible': 'Faible',
  'a-verifier': 'À vérifier',
};

/// Recommandation GÉNÉRIQUE par domaine (table statique documentée,
/// affichée comme telle — pas une prescription d'intervention).
const Map<String, String> domainRecommendation = {
  'voirie': 'Intervention voirie (constat terrain requis)',
  'reseaux': 'Intervention réseaux eau/électricité (diagnostic requis)',
  'espaces-verts': 'Intervention espaces verts (constat requis)',
};

String shortLabel(Incident i, Map<String, Report> byId) {
  final cats = <String>{};
  for (final id in i.reportIds) {
    final r = byId[originIdOfSubunit(id)];
    if (r != null) cats.add(r.category);
  }
  final fam = cats.isEmpty ? 'incident' : cats.join(' + ');
  return '$fam · ${i.reportIds.length} signalement(s)';
}

/// Ligne du plan priorisé (données réelles du plan courant).
Map<String, dynamic> planRow(Task t, Incident i, Map<String, Report> byId,
    String? validation) {
  final durH = (t.endMin - t.startMin) / 60.0;
  return {
    'incidentId': i.id,
    'label': shortLabel(i, byId),
    'lieu': '(${i.x.toStringAsFixed(1)}, ${i.y.toStringAsFixed(1)}) km — grille fictive',
    'priority': priorityOf(i),
    'priorityLabel': priorityLabels[priorityOf(i)],
    'recommandation':
        '${domainRecommendation[i.domain] ?? 'Intervention à qualifier'} — générique, à valider sur le terrain',
    'resources':
        '${t.teamId} · ${durH.toStringAsFixed(1)} h · ${t.cost.toStringAsFixed(1)} u.',
    'teamId': t.teamId,
    'dureeMin': t.endMin - t.startMin,
    'cout': t.cost,
    'echeanceMin': i.deadline,
    'status': validation == 'valide'
        ? 'valide-humain'
        : validation == 'rejete'
            ? 'rejete-humain'
            : 'propose',
  };
}

/// Activité : projection d'une entrée de journal vers un événement
/// d'affichage. Tout événement inconnu est conservé avec son nom brut
/// (jamais supprimé silencieusement).
Map<String, dynamic> activityItem(Map<String, dynamic> e) {
  final event = (e['event'] ?? 'inconnu') as String;
  final d = (e['details'] as Map?)?.cast<String, dynamic>() ?? {};
  String type = 'systeme';
  var label = event;
  var detail = '';
  String? ref;
  switch (event) {
    case 'report.created':
      type = 'signalement';
      label = 'Signalement reçu';
      ref = d['id']?.toString();
      detail = ref ?? '';
      break;
    case 'photo.uploaded':
      type = 'signalement';
      label = 'Photo reçue';
      detail = (d['mime']?.toString() ?? '');
      break;
    case 'group.done':
      type = 'regroupement';
      label = 'Incidents regroupés';
      detail = 'méthode ${d['method'] ?? '?'}'
          '${d['groups'] != null ? ' · ${d['groups']} groupes' : ''}';
      break;
    case 'plan.proposed':
      type = 'plan';
      label = 'Plan généré';
      ref = d['planId']?.toString();
      detail = '${ref ?? ''} · ${d['tasks'] ?? '?'} tâches'
          ' · Q=${(d['q'] as num?)?.toStringAsFixed(1) ?? '?'}';
      break;
    case 'plan.validated':
      type = 'validation';
      label = d['decision'] == 'valide' ? 'Plan validé' : 'Plan rejeté';
      ref = d['planId']?.toString();
      detail = 'par ${d['by'] ?? 'humain'}${ref != null ? ' · $ref' : ''}';
      break;
    case 'simulate.done':
      type = 'simulation';
      label = 'Simulation exécutée';
      detail = 'Q=${(d['q'] as num?)?.toStringAsFixed(1) ?? '?'}'
          ' · faisable=${d['feasible'] ?? '?'}';
      break;
    case 'inject.received':
      type = d['type'] == 'team_down' ? 'equipe' : 'injection';
      label = d['type'] == 'team_down'
          ? 'Équipe indisponible'
          : 'Information nouvelle reçue';
      detail = 'nécessité ${d['necessity'] ?? '?'}'
          '${d['revised'] == true ? ' · plan révisé' : ''}';
      break;
    case 'scenario.loaded':
      type = 'systeme';
      label = 'Scénario chargé (DEV)';
      detail = d['id']?.toString() ?? '';
      break;
    case 'meta.verify':
    case 'meta.extract':
    case 'meta.analyze-image':
      type = 'ia';
      label = 'Analyse IA';
      detail = '$event${d['reportId'] != null ? ' · ${d['reportId']}' : ''}';
      break;
    case 'server.resumed':
      type = 'systeme';
      label = 'Serveur redémarré (état restauré)';
      detail = d['scenario']?.toString() ?? '';
      break;
  }
  return {
    'seq': e['seq'],
    'at': e['at'],
    'type': type,
    'label': label,
    'detail': detail,
    'ref': ref,
  };
}

/// Péremption d'un plan : vrai si un regroupement (group.done) est survenu
/// après la création du plan. Les identifiants d'incidents (I1..) sont
/// positionnels : un regroupement peut les renumérotationner, et les
/// tâches du plan ne désignent plus alors les bons incidents. Plutôt que
/// de présenter une jointure fausse, le backend signale le plan comme
/// périmé (à replanifier) et l'interface l'affiche explicitement.
bool planIsStale(
    Plan? plan, List<Map<String, dynamic>> planHistory,
    List<Map<String, dynamic>> journalEntries) {
  if (plan == null || plan.planId.isEmpty) return false;
  String? createdAt;
  for (final h in planHistory) {
    if (h['planId'] == plan.planId) {
      createdAt = h['at'] as String?;
      break;
    }
  }
  if (createdAt == null) return true;
  for (final e in journalEntries) {
    if (e['event'] == 'group.done') {
      final at = e['at'] as String?;
      if (at != null && at.compareTo(createdAt) > 0) return true;
    }
  }
  return false;
}

/// Recherche municipale (état borné) : identifiant, texte, catégorie,
/// famille (lexique split), statut de suivi. Tri déterministe par id.
List<Map<String, dynamic>> searchAll(String query, List<Report> reports,
    List<Group> groups, List<Incident> incidents, Plan? plan) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [];
  final out = <Map<String, dynamic>>[];
  for (final r in reports) {
    final fams = reportProblemFamilies(r).join(' ');
    if (r.id.toLowerCase().contains(q) ||
        r.text.toLowerCase().contains(q) ||
        r.category.toLowerCase().contains(q) ||
        fams.contains(q)) {
      out.add({'kind': 'report', 'id': r.id, 'text': r.text, 'status': null});
    }
  }
  final planned =
      plan == null ? <String>{} : plan.tasks.map((t) => t.incidentId).toSet();
  for (final i in incidents) {
    final st = (i.severity != null && i.severity! >= 5)
        ? 'escalade-s5'
        : planned.contains(i.id)
            ? 'planifie'
            : 'a-analyser';
    if (i.id.toLowerCase().contains(q) ||
        i.domain.toLowerCase().contains(q) ||
        st.contains(q)) {
      out.add({'kind': 'incident', 'id': i.id, 'text': i.domain, 'status': st});
    }
  }
  out.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  return out;
}

/// --- Pages municipales dédiées (découpage / planification / révision / fiche) ---
///
/// Toutes les fonctions ci-dessous sont pures et bornées (état de travail
/// en mémoire uniquement). Aucun pourcentage ni score inventé.

/// Vue d'ensemble du découpage : méthode réellement utilisée, comptes
/// d'unités atomiques, problèmes secondaires conservés, incertitudes et
/// justifications portées par les groupes. Aucune confiance chiffrée
/// calculée : les confiances affichées sont celles déjà stockées.
Map<String, dynamic> splitOverviewData(
    List<Report> reports, List<Group> groups, List<Incident> incidents,
    String groupMethod,
    {Plan? plan}) {
  final plannedIds =
      plan == null ? <String>{} : plan.tasks.map((t) => t.incidentId).toSet();
  final byId = {for (final r in reports) r.id: r};
  final units = expandToSubunits(reports);
  final multiOrigins = reports.where(hasMultiProblem).map((r) => r.id).toList()
    ..sort();
  final reasons = <String>[];
  final justifs = <String>[];
  for (final g in groups) {
    reasons.addAll(g.uncertaintyReasons);
    if (g.justification != null && g.justification!.isNotEmpty) {
      justifs.add('${g.id} : ${g.justification}');
    }
  }
  final perIncident = <Map<String, dynamic>>[];
  for (final i in incidents) {
    final origins = <String>{};
    for (final rid in i.reportIds) {
      final o = originIdOfSubunit(rid);
      if (byId.containsKey(o)) origins.add(o);
    }
    perIncident.add({
      'incidentId': i.id,
      'units': i.reportIds.length,
      'origins': origins.toList()..sort(),
      'domain': i.domain,
      'severity': i.severity,
      'severityStatus': i.severityStatus,
      'x': i.x,
      'y': i.y,
      'status': incidentPlanningBucket(i, plannedIds, hasPlan: plan != null),
    });
  }
  perIncident.sort((a, b) =>
      (a['incidentId'] as String).compareTo(b['incidentId'] as String));
  return {
    'method': groupMethod,
    'groups': groups.length,
    'units': units.length,
    'incidents': incidents.length,
    'multiProblemReports': multiOrigins,
    'uncertainGroups':
        groups.where((g) => g.uncertain).map((g) => g.id).toList(),
    'uncertaintyReasons': reasons.toSet().toList()..sort(),
    'justifications': justifs,
    'perIncident': perIncident,
    'note':
        'Aucune confiance chiffrée calculée ici : seules les confiances déjà stockées sur les groupes sont affichées.',
  };
}

/// Détail d'un signalement pour la page découpage : sous-signalements
/// (unités ORIGINE:FAMILLE), familles détectées, incidents liés (via
/// origine), incertitudes des groupes concernés.
Map<String, dynamic>? splitReportDetail(List<Report> reports,
    List<Group> groups, List<Incident> incidents, String reportId) {
  Report? rep;
  for (final r in reports) {
    if (r.id == reportId) rep = r;
  }
  if (rep == null) return null;
  final units = expandToSubunits([rep]);
  final linkedGroups = groups
      .where((g) => g.reportIds.any((id) => originIdOfSubunit(id) == reportId))
      .toList();
  final linkedIncidents = incidents
      .where((i) => i.reportIds.any((id) => originIdOfSubunit(id) == reportId))
      .toList();
  final reasons = <String>{};
  for (final g in linkedGroups) {
    reasons.addAll(g.uncertaintyReasons);
  }
  return {
    'reportId': rep.id,
    'text': rep.text,
    'category': rep.category,
    'photo': rep.photo,
    'source': rep.source,
    'receivedAt': rep.receivedAt,
    'hasPhoto': rep.photo != null && rep.photo!.isNotEmpty,
    'families': reportProblemFamilies(rep).toList(),
    'multiProblem': hasMultiProblem(rep),
    'subunits': [
      for (final u in units)
        {'id': u.id, 'family': u.family, 'originId': u.originId}
    ],
    'linkedGroups': [for (final g in linkedGroups) g.toJson()],
    'linkedIncidents': [
      for (final i in linkedIncidents)
        {'id': i.id, 'domain': i.domain, 'severity': i.severity}
    ],
    'uncertaintyReasons': reasons.toList()..sort(),
  };
}

/// Incident planifiable : gravité connue 1..4 (S5 = escalade, jamais
/// dispatché ; inconnue/contradictoire = vérification requise).
String incidentPlanningBucket(Incident i, Set<String> plannedIds,
    {bool hasPlan = true}) {
  if (i.severity != null && i.severity! >= 5) return 'escalade-s5';
  if (i.severity == null) return 'a-verifier';
  if (plannedIds.contains(i.id)) return 'planifie';
  if (!hasPlan) return 'planifiable';
  return 'non-affecte';
}

/// Ligne d'incident pour la page planification (données réelles : équipe
/// et motif issus du plan courant, durée/échéance estimées, inconnues
/// conservées).
Map<String, dynamic> planningIncidentRow(
    Incident i, Map<String, Report> byId, String bucket, String? motif) {
  return {
    'incidentId': i.id,
    'label': shortLabel(i, byId),
    'lieu': '(${i.x.toStringAsFixed(1)}, ${i.y.toStringAsFixed(1)}) km — grille fictive',
    'severity': i.severity,
    'severityStatus': i.severityStatus,
    'severityValues': i.severityValues,
    'priority': priorityOf(i),
    'priorityLabel': priorityLabels[priorityOf(i)],
    'dureeEstimeeMin': i.severity == null ? null : estDurationMin(i.severity),
    'echeanceMin': i.deadline,
    'domain': i.domain,
    'reportCount': i.reportIds.length,
    'status': bucket,
    'motif': motif,
  };
}

/// Vue d'ensemble planification : équipes réelles (défaut moins down),
/// incidents classés, plan courant + validation + simulation si présente,
/// budget et contraintes. Aucun calcul d'optimisation ici (l'action
/// Optimiser appelle POST /api/plan).
Map<String, dynamic> planOverviewData({
  required List<Report> reports,
  required List<Incident> incidents,
  required Plan? plan,
  required String? planValidation,
  required List<Team> allTeams,
  required Set<String> teamsDown,
  required double? simQ,
  required bool? simFeasible,
}) {
  final byId = {for (final r in reports) r.id: r};
  final plannedIds =
      plan == null ? <String>{} : plan.tasks.map((t) => t.incidentId).toSet();
  final tasksByTeam = <String, List<Task>>{};
  if (plan != null) {
    for (final t in plan.tasks) {
      tasksByTeam.putIfAbsent(t.teamId, () => []).add(t);
    }
  }
  final teams = [
    for (final tm in allTeams)
      {
        'id': tm.id,
        'domains': tm.domains.toList()..sort(),
        'available': !teamsDown.contains(tm.id),
        'taskCount': (tasksByTeam[tm.id] ?? []).length,
        'estimatedMin': (tasksByTeam[tm.id] ?? [])
            .fold<int>(0, (a, t) => a + (t.endMin - t.startMin)),
      }
  ];
  final rows = <Map<String, dynamic>>[];
  final counts = {
    'planifiable': 0,
    'planifie': 0,
    'non-affecte': 0,
    'a-verifier': 0,
    'escalade-s5': 0
  };
  for (final i in incidents) {
    final admissible =
        i.severity != null && i.severity! >= 1 && i.severity! <= 4;
    if (admissible) {
      counts['planifiable'] = counts['planifiable']! + 1;
    }
    final bucket =
        incidentPlanningBucket(i, plannedIds, hasPlan: plan != null);
    if (bucket == 'escalade-s5') {
      counts['escalade-s5'] = counts['escalade-s5']! + 1;
    } else if (bucket == 'a-verifier') {
      counts['a-verifier'] = counts['a-verifier']! + 1;
    } else if (bucket == 'planifie') {
      counts['planifie'] = counts['planifie']! + 1;
    } else if (bucket == 'non-affecte') {
      counts['non-affecte'] = counts['non-affecte']! + 1;
    }
    rows.add(planningIncidentRow(i, byId, bucket,
        plan == null ? null : plan.unassigned[i.id]));
  }
  rows.sort((a, b) =>
      (a['incidentId'] as String).compareTo(b['incidentId'] as String));
  return {
    'teams': teams,
    'incidents': rows,
    'counts': counts,
    'plan': plan == null
        ? null
        : {
            ...plan.toJson(),
            'validation': planValidation,
          },
    'unassigned': plan == null
        ? []
        : [
            for (final e in plan.unassigned.entries)
              {'incidentId': e.key, 'motif': e.value}
          ],
    'escalations': plan?.escalations ?? [],
    'sim': simQ == null
        ? null
        : {'q': simQ, 'feasible': simFeasible},
    'budget': {'total': 120.0, 'unit': 'unités fictives (ni euros, ni FCFA, ni dollars)'},
  };
}

/// Historique de révision : versions de plans (plus récent d'abord) +
/// événements de journal pertinents (plus récents d'abord, curseur = seq).
Map<String, dynamic> revisionHistoryData(
    List<Map<String, dynamic>> planHistory,
    List<Map<String, dynamic>> auditEntries,
    int limit) {
  const relevant = {
    'inject.received',
    'plan.proposed',
    'plan.validated',
    'simulate.done',
  };
  // Scoper a la generation d'etat courante : un chargement de scenario
  // recommence les identifiants (reports, plans) ; les injects d'une
  // generation anterieure ne concernent plus le plan courant.
  String? generationStart;
  for (final e in auditEntries) {
    if (e['event'] == 'scenario.loaded') {
      generationStart = e['at'] as String?;
    }
  }
  final plans = planHistory.reversed
      .map((h) => {
            'planId': h['planId'],
            'version': h['version'],
            'at': h['at'],
            'method': h['method'],
            'validation': h['validation'],
            'q': (h['plan'] as Map?)?['q'],
            'totalCost': (h['plan'] as Map?)?['totalCost'],
            'tasks': ((h['plan'] as Map?)?['tasks'] as List?)?.length,
            'detail': h['plan'],
          })
      .toList();
  final events = auditEntries.reversed
      .where((e) => relevant.contains(e['event']))
      .where((e) =>
          generationStart == null ||
          (e['at'] as String? ?? '').compareTo(generationStart) > 0)
      .take(limit.clamp(1, 100))
      .map(activityItem)
      .toList();
  return {'plans': plans, 'events': events};
}

/// Fiche signalement complète (données réelles uniquement) : déclaration,
/// média (référence + métadonnées si téléversé), sous-signalements,
/// incidents liés, gravité/exposition conservées, vérification municipale,
/// analyses IA si présentes (étiquetées comme telles), historique.
Map<String, dynamic> ficheData({
  required Report report,
  required List<Group> groups,
  required List<Incident> incidents,
  Map<String, dynamic>? photoMeta,
  Map<String, dynamic>? visualAnalysis,
  Map<String, dynamic>? extraction,
  required List<Map<String, dynamic>> auditEntries,
}) {
  final units = expandToSubunits([report]);
  final linkedGroups = groups
      .where((g) => g.reportIds.any((id) => originIdOfSubunit(id) == report.id))
      .toList();
  final linkedIncidents = incidents
      .where((i) => i.reportIds.any((id) => originIdOfSubunit(id) == report.id))
      .toList();
  final history = auditEntries
      .where((e) {
        final d = e['details'];
        if (d is! Map) return false;
        if (d['id'] == report.id || d['reportId'] == report.id) return true;
        if (d['mediaId'] != null && d['mediaId'] == report.photo) return true;
        return false;
      })
      .map(activityItem)
      .toList();
  return {
    'report': {
      ...report.toJson(),
      'families': reportProblemFamilies(report).toList(),
      'multiProblem': hasMultiProblem(report),
    },
    'photoMeta': photoMeta,
    'subunits': [
      for (final u in units) {'id': u.id, 'family': u.family}
    ],
    'linkedGroups': [for (final g in linkedGroups) g.toJson()],
    'linkedIncidents': [for (final i in linkedIncidents) i.toJson()],
    'visualAnalysis': visualAnalysis,
    'extraction': extraction,
    'history': history,
    'fictive': true,
  };
}

/// Validation d'une modification municipale limitée : texte, catégorie,
/// indices de gravité/exposition, note de vérification. Retourne le
/// message d'erreur, ou null si valide. Ne regroupe jamais.
String? validateReportPatch(Map<String, dynamic> b) {
  if (b.containsKey('text')) {
    final err = publicTextError(b['text'] as String?);
    if (err != null) return err;
  }
  if (b.containsKey('category')) {
    final c = (b['category'] ?? '') as String;
    if (!isPublicCategory(c)) return 'catégorie inconnue : $c';
  }
  if (b.containsKey('severityHint')) {
    final s = b['severityHint'] as int?;
    if (s != null && (s < 1 || s > 5)) {
      return 'severityHint hors 1..5 (ou null = inconnue)';
    }
  }
  if (b.containsKey('exposureHint')) {
    final e = b['exposureHint'] as int?;
    if (e != null && (e < 0 || e > 4)) {
      return 'exposureHint hors 0..4 (ou null = inconnue)';
    }
  }
  if (b.containsKey('verificationNote')) {
    final n = b['verificationNote'];
    if (n != null && (n as String).length > 500) {
      return 'note de vérification trop longue (500 max)';
    }
  }
  return null;
}


