// Municipal dashboard: pure, documented aggregates.
//
// All functions here are pure (inputs -> outputs) and unit-tested.
// They work on the bounded in-memory working state: no
// Mongo read, no full scan. Honesty rules:
// - never an invented percentage (change computed or absent);
// - exclusive, defined statuses (see incidentStatusBuckets);
// - periods computed on real timestamps (reports' receivedAt,
//   journal `at`); scenario data without a date
//   is excluded from bounded windows (documented, never estimated).
import 'grouping.dart';
import 'optimizer.dart';
import 'security.dart';
import 'types.dart';

/// Requested window. 'all' = all history. 'custom' requires from/to.
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
      throw FormatException('invalid custom period (from/to ISO required)');
    }
    return Period(k, from: from.toUtc(), to: to.toUtc());
  }
  if (!{'today', '7d', '30d', 'all'}.contains(k)) {
    throw FormatException('unknown period: $k');
  }
  return Period(k);
}

/// Bounds [start, end) of a window, and of the previous window
/// (same duration, just before) for the change. null = unbounded.
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
  if (iso == null) return start == null; // without a date: only in 'all'
  final t = DateTime.tryParse(iso)?.toUtc();
  if (t == null) return false;
  if (start != null && t.isBefore(start)) return false;
  if (end != null && !t.isBefore(end)) return false;
  return true;
}

/// Report KPI on the window + previous window (change
/// computed, never invented: null if the reference is empty).
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

/// EXCLUSIVE incident statuses (sum = total):
/// - escalade-s5: declared severity 5 (never dispatched);
/// - planifie: present in the current plan's tasks;
/// - non-affecte: a plan exists but the incident is not in it;
/// - a-analyser: no current plan (grouped, awaiting planning).
/// Without a plan, every non-S5 incident is "to analyse": this is not a
/// failure, it is the normal state before planning.
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

/// Display priority derived from the DECLARED severity only.
/// S5 = Critical (escalation, never in a plan); unknown = To verify.
String priorityOf(Incident i) {
  final s = i.severity;
  if (s == null) return 'a-verifier';
  if (s >= 5) return 'critique';
  if (s == 4) return 'haute';
  if (s == 3) return 'moyenne';
  return 'faible';
}

const Map<String, String> priorityLabels = {
  'critique': 'Critical (S5, escalation)',
  'haute': 'High',
  'moyenne': 'Medium',
  'faible': 'Low',
  'a-verifier': 'To verify',
};

/// GENERIC recommendation per domain (documented static table,
/// displayed as such — not an intervention prescription).
const Map<String, String> domainRecommendation = {
  'voirie': 'Roads intervention (field observation required)',
  'reseaux': 'Water/electricity networks intervention (diagnosis required)',
  'espaces-verts': 'Green spaces intervention (observation required)',
};

String shortLabel(Incident i, Map<String, Report> byId) {
  final cats = <String>{};
  for (final id in i.reportIds) {
    final r = byId[originIdOfSubunit(id)];
    if (r != null) cats.add(r.category);
  }
  final fam = cats.isEmpty ? 'incident' : cats.join(' + ');
  return '$fam · ${i.reportIds.length} report(s)';
}

/// Prioritized plan row (real data from the current plan).
Map<String, dynamic> planRow(Task t, Incident i, Map<String, Report> byId,
    String? validation) {
  final durH = (t.endMin - t.startMin) / 60.0;
  return {
    'incidentId': i.id,
    'label': shortLabel(i, byId),
    'lieu': '(${i.x.toStringAsFixed(1)}, ${i.y.toStringAsFixed(1)}) km — fictitious grid',
    'priority': priorityOf(i),
    'priorityLabel': priorityLabels[priorityOf(i)],
    'recommandation':
        '${domainRecommendation[i.domain] ?? 'Intervention to qualify'} — generic, to validate on site',
    'resources':
        '${t.teamId} · ${durH.toStringAsFixed(1)} h · ${t.cost.toStringAsFixed(1)} units.',
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

/// Activity: projection of a journal entry to a display event.
/// Any unknown event is kept with its raw name
/// (never silently dropped).
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
      label = 'Report received';
      ref = d['id']?.toString();
      detail = ref ?? '';
      break;
    case 'photo.uploaded':
      type = 'signalement';
      label = 'Photo received';
      detail = (d['mime']?.toString() ?? '');
      break;
    case 'group.done':
      type = 'regroupement';
      label = 'Incidents grouped';
      detail = 'method ${d['method'] ?? '?'}'
          '${d['groups'] != null ? ' · ${d['groups']} groups' : ''}';
      break;
    case 'plan.proposed':
      type = 'plan';
      label = 'Plan generated';
      ref = d['planId']?.toString();
      detail = '${ref ?? ''} · ${d['tasks'] ?? '?'} tasks'
          ' · Q=${(d['q'] as num?)?.toStringAsFixed(1) ?? '?'}';
      break;
    case 'plan.validated':
      type = 'validation';
      label = d['decision'] == 'valide' ? 'Plan validated' : 'Plan rejected';
      ref = d['planId']?.toString();
      detail = 'by ${d['by'] ?? 'human'}${ref != null ? ' · $ref' : ''}';
      break;
    case 'simulate.done':
      type = 'simulation';
      label = 'Simulation run';
      detail = 'Q=${(d['q'] as num?)?.toStringAsFixed(1) ?? '?'}'
          ' · feasible=${d['feasible'] ?? '?'}';
      break;
    case 'inject.received':
      type = d['type'] == 'team_down' ? 'equipe' : 'injection';
      label = d['type'] == 'team_down'
          ? 'Team unavailable'
          : 'New information received';
      detail = 'necessity ${d['necessity'] ?? '?'}'
          '${d['revised'] == true ? ' · plan revised' : ''}';
      break;
    case 'scenario.loaded':
      type = 'systeme';
      label = 'Scenario loaded (DEV)';
      detail = d['id']?.toString() ?? '';
      break;
    case 'meta.verify':
    case 'meta.extract':
    case 'meta.analyze-image':
      type = 'ia';
      label = 'AI analysis';
      detail = '$event${d['reportId'] != null ? ' · ${d['reportId']}' : ''}';
      break;
    case 'server.resumed':
      type = 'systeme';
      label = 'Server restarted (state restored)';
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

/// Plan staleness: true if a grouping (group.done) happened
/// after the plan was created. Incident identifiers (I1..) are
/// positional: a grouping can renumber them, and plan
/// tasks then no longer point to the right incidents. Rather than
/// presenting a false join, the backend flags the plan as
/// stale (to replan) and the interface shows it explicitly.
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

/// Municipal search (bounded state): identifier, text, category,
/// family (split lexicon), tracking status. Deterministic sort by id.
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

/// --- Dedicated municipal pages (splitting / planning / review / details) ---
///
/// All functions below are pure and bounded (in-memory working
/// state only). No invented percentage or score.

/// Splitting overview: method actually used, atomic-unit
/// counts, secondary problems kept, uncertainties and
/// justifications carried by the groups. No numeric confidence
/// computed: the confidences displayed are those already stored.
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
        'No numeric confidence computed here: only the confidences already stored on the groups are displayed.',
  };
}

/// Report detail for the splitting page: sub-reports
/// (ORIGIN:FAMILY units), detected families, linked incidents (via
/// origin), uncertainties of the groups involved.
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

/// Plannable incident: known severity 1..4 (S5 = escalation, never
/// dispatched; unknown/conflicting = verification required).
String incidentPlanningBucket(Incident i, Set<String> plannedIds,
    {bool hasPlan = true}) {
  if (i.severity != null && i.severity! >= 5) return 'escalade-s5';
  if (i.severity == null) return 'a-verifier';
  if (plannedIds.contains(i.id)) return 'planifie';
  if (!hasPlan) return 'planifiable';
  return 'non-affecte';
}

/// Incident row for the planning page (real data: team
/// and reason from the current plan, estimated duration/deadline, unknowns
/// kept).
Map<String, dynamic> planningIncidentRow(
    Incident i, Map<String, Report> byId, String bucket, String? motif) {
  return {
    'incidentId': i.id,
    'label': shortLabel(i, byId),
    'lieu': '(${i.x.toStringAsFixed(1)}, ${i.y.toStringAsFixed(1)}) km — fictitious grid',
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

/// Planning overview: real teams (default minus down),
/// classified incidents, current plan + validation + simulation if present,
/// budget and constraints. No optimization computation here (the
/// Optimize action calls POST /api/plan).
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
    'budget': {'total': 120.0, 'unit': 'fictitious units (neither euros, FCFA, nor dollars)'},
  };
}

/// Review history: plan versions (most recent first) +
/// relevant journal events (most recent first, cursor = seq).
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
  // Scope to the current state generation: a scenario load
  // restarts identifiers (reports, plans); injects from a
  // previous generation no longer concern the current plan.
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

/// Complete report details (real data only): declaration,
/// media (reference + metadata if uploaded), sub-reports,
/// linked incidents, kept severity/exposure, municipal verification,
/// AI analyses if present (labelled as such), history.
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

/// Validation of a limited municipal edit: text, category,
/// severity/exposure hints, verification note. Returns the
/// error message, or null if valid. Never regroups.
String? validateReportPatch(Map<String, dynamic> b) {
  if (b.containsKey('text')) {
    final err = publicTextError(b['text'] as String?);
    if (err != null) return err;
  }
  if (b.containsKey('category')) {
    final c = (b['category'] ?? '') as String;
    if (!isPublicCategory(c)) return 'unknown category: $c';
  }
  if (b.containsKey('severityHint')) {
    final s = b['severityHint'] as int?;
    if (s != null && (s < 1 || s > 5)) {
      return 'severityHint outside 1..5 (or null = unknown)';
    }
  }
  if (b.containsKey('exposureHint')) {
    final e = b['exposureHint'] as int?;
    if (e != null && (e < 0 || e > 4)) {
      return 'exposureHint outside 0..4 (or null = unknown)';
    }
  }
  if (b.containsKey('verificationNote')) {
    final n = b['verificationNote'];
    if (n != null && (n as String).length > 500) {
      return 'verification note too long (500 max)';
    }
  }
  return null;
}


