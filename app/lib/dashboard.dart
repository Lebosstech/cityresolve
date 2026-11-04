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
