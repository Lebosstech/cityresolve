// Aggregation groups -> proposed incidents (exploratory).
//
// Severity and exposure: NEVER inferred from the category nor fabricated.
// - no declared value           -> null value, inconnue status;
// - a single distinct value    -> declaree status;
// - close values (gap <= 1)    -> max, estimee status;
// - incompatible values (>= 2) -> null value, contradictoire status,
//   declared values kept in severityValues/exposureValues.
// Domain: majority domain of the DECLARED categories; tie between
// two domains -> domainConflict flagged (first domain kept).
import 'policy.dart';
import 'types.dart';

class _Attr {
  final int? value;
  final String status;
  final List<int> values;
  const _Attr(this.value, this.status, this.values);
}

_Attr _aggregateAttr(List<int?> hints) {
  final values = hints.whereType<int>().toList()..sort();
  if (values.isEmpty) return const _Attr(null, statusInconnue, []);
  final distinct = values.toSet().toList();
  if (distinct.length == 1) {
    return _Attr(distinct.first, statusDeclaree, values);
  }
  if (values.last - values.first <= 1) {
    return _Attr(values.last, statusEstimee, values);
  }
  return _Attr(null, statusContradictoire, values);
}

/// Business domain of a DEV family (splitting). Aligned with
/// `categoryDomain`: lighting is attached to roads there, like
/// the `eclairage` category, to stay assignable to the existing
/// teams (equipe-1: voirie, espaces-verts; equipe-2: voirie,
/// reseaux). No severity is inferred from the family.
const Map<String, String> familyDomain = {
  'voirie-nid': 'voirie',
  'eclairage': 'voirie',
  'eau': 'reseaux',
  'electricite': 'reseaux',
  'assainissement': 'reseaux',
  'inconnu': 'voirie',
};

/// Aggregation for groups of SUB-reports (see
/// `groupSplitReports` / `splitGroupsByFamily`).
/// Do NOT call `aggregate()` on these groups: it would look up
/// `E1:eclairage` in the reports table and fail.
/// Here, each identifier is resolved to its origin report
/// (part before `:`), and the incident keeps the split
/// identifiers in `reportIds`: the origin is therefore traceable, and
/// the optimizer sees as many tasks as split groups.
/// Limitation: two parts of the same report share the same
/// declared severity/exposure (those of the origin); splitting
/// creates no severity or exposure of its own for a part.
List<Incident> aggregateSplitGroups(
    List<Group> groups, Map<String, Report> byId) {
  final out = <Incident>[];
  var ii = 0;
  for (final g in groups) {
    ii++;
    final origins = <Report>[];
    final fams = <String>{};
    for (final sid in g.reportIds) {
      final i = sid.indexOf(':');
      final originId = i < 0 ? sid : sid.substring(0, i);
      final fam = i < 0 ? 'inconnu' : sid.substring(i + 1);
      final rep = byId[originId];
      if (rep != null) origins.add(rep);
      fams.add(fam);
    }
    if (origins.isEmpty) continue;
    final sev = _aggregateAttr(origins.map((r) => r.severityHint).toList());
    final expo = _aggregateAttr(origins.map((r) => r.exposureHint).toList());
    var sx = 0.0, sy = 0.0;
    var first = origins.first.t;
    for (final r in origins) {
      sx += r.x;
      sy += r.y;
      if (r.t < first) first = r.t;
    }
    final dom = fams.length == 1
        ? (familyDomain[fams.single] ?? 'voirie')
        : 'voirie';
    out.add(Incident(
      id: 'I$ii',
      reportIds: g.reportIds,
      severity: sev.value,
      severityStatus: sev.status,
      severityValues: sev.values,
      exposure: expo.value,
      exposureStatus: expo.status,
      exposureValues: expo.values,
      domain: dom,
      domainConflict: fams.length > 1,
      x: sx / origins.length,
      y: sy / origins.length,
      firstSeen: first,
      confidence: g.confidence,
    ));
  }
  out.sort((a, b) {
    final dw = b.weight.compareTo(a.weight);
    if (dw != 0) return dw;
    final dd = a.deadline.compareTo(b.deadline);
    if (dd != 0) return dd;
    return a.id.compareTo(b.id);
  });
  return out;
}

/// --- Server wiring of multi-problem splitting ---
///
/// The server must NEVER call `aggregate()` on a group whose
/// identifier contains `:` (sub-report `ORIGIN:FAMILY`):
/// `aggregate()` would look up `E1:eclairage` in the
/// reports table and fail (`byId[id]!` access on a missing key).
/// `aggregateMixedGroups()` routes each group to the right
/// aggregation: split groups -> `aggregateSplitGroups()`, full
/// groups -> `aggregate()`, then renumbers incidents I1.. in
/// final order (decreasing weight, deadline, provisional identifier),
/// because the two aggregations would otherwise each number from I1
/// and plan tasks (referenced by incident identifier)
/// would become ambiguous. On groups without `:` the result is
/// identical to `aggregate()` (proven by test T27d).
bool groupUsesSplitIds(Group g) =>
    g.reportIds.any((id) => id.contains(':'));

bool groupsUseSplitIds(List<Group> groups) =>
    groups.any(groupUsesSplitIds);

List<Incident> aggregateMixedGroups(
    List<Group> groups, Map<String, Report> byId) {
  final split = groups.where(groupUsesSplitIds).toList();
  final plain = groups.where((g) => !groupUsesSplitIds(g)).toList();
  final merged = <Incident>[
    ...aggregateSplitGroups(split, byId),
    ...aggregate(plain, byId),
  ];
  merged.sort((a, b) {
    final dw = b.weight.compareTo(a.weight);
    if (dw != 0) return dw;
    final dd = a.deadline.compareTo(b.deadline);
    if (dd != 0) return dd;
    return a.id.compareTo(b.id);
  });
  return [
    for (var i = 0; i < merged.length; i++)
      Incident(
        id: 'I${i + 1}',
        reportIds: merged[i].reportIds,
        severity: merged[i].severity,
        exposure: merged[i].exposure,
        domain: merged[i].domain,
        x: merged[i].x,
        y: merged[i].y,
        firstSeen: merged[i].firstSeen,
        confidence: merged[i].confidence,
        severityStatus: merged[i].severityStatus,
        severityValues: merged[i].severityValues,
        exposureStatus: merged[i].exposureStatus,
        exposureValues: merged[i].exposureValues,
        domainConflict: merged[i].domainConflict,
      ),
  ];
}

List<Incident> aggregate(
    List<Group> groups, Map<String, Report> byId) {
  final out = <Incident>[];
  var ii = 0;
  for (final g in groups) {
    ii++;
    final reps = g.reportIds.map((id) => byId[id]!).toList();
    final sev = _aggregateAttr(reps.map((r) => r.severityHint).toList());
    final expo = _aggregateAttr(reps.map((r) => r.exposureHint).toList());
    final domCount = <String, int>{};
    var sx = 0.0, sy = 0.0;
    var first = reps.first.t;
    for (final r in reps) {
      final dom = categoryDomainOf(r.category);
      domCount[dom] = (domCount[dom] ?? 0) + 1;
      sx += r.x;
      sy += r.y;
      if (r.t < first) first = r.t;
    }
    var dom = 'voirie';
    var best = -1;
    var conflict = false;
    domCount.forEach((k, v) {
      if (v > best) {
        best = v;
        dom = k;
        conflict = false;
      } else if (v == best) {
        conflict = true;
      }
    });
    out.add(Incident(
      id: 'I$ii',
      reportIds: g.reportIds,
      severity: sev.value,
      severityStatus: sev.status,
      severityValues: sev.values,
      exposure: expo.value,
      exposureStatus: expo.status,
      exposureValues: expo.values,
      domain: dom,
      domainConflict: conflict,
      x: sx / reps.length,
      y: sy / reps.length,
      firstSeen: first,
      confidence: g.confidence,
    ));
  }
  // Priority: decreasing decision weight, then deadline, then id.
  out.sort((a, b) {
    final dw = b.weight.compareTo(a.weight);
    if (dw != 0) return dw;
    final dd = a.deadline.compareTo(b.deadline);
    if (dd != 0) return dd;
    return a.id.compareTo(b.id);
  });
  return out;
}
