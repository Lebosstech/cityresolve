// Deterministic classic grouping (exploratory DEV).
//
// Rule: edge between two reports iff distance <= distMax AND
// time gap <= deltaTMax AND Jaccard similarity >= simMin.
// Groups = connected components (union-find), deterministic order.
// Group confidence = minimum similarity of its edges (0 if singleton).
import 'types.dart';

final RegExp _splitter = RegExp(r'[^a-zàâäéèêëîïôöùûüç0-9]+');

Set<String> tokens(String text) => text
    .toLowerCase()
    .split(_splitter)
    .where((w) => w.length > 2)
    .toSet();

/// Insufficient-content guardrail (pushed to main).
///
/// A text is insufficient if, after lowercasing, it contains
/// fewer than 2 alphanumeric characters (accented letters included).
/// So: empty text, punctuation/spaces only, or a single character.
/// A text of 2 characters or more PASSES the guardrail (assumed limitation:
/// it may still be meaningless, e.g. "ab") — the guardrail only targets
/// the absence of content, not content quality. It resolves neither
/// unknown place, nor unknown time, nor contradictions (see
/// PATCH_GUARDRAIL_NOTES.md).
final RegExp _alphanum = RegExp(r'[a-zàâäéèêëîïôöùûüç0-9]');

bool hasInsufficientContent(String text) {
  var count = 0;
  for (final _ in _alphanum.allMatches(text.toLowerCase())) {
    count++;
    if (count >= 2) return false;
  }
  return true;
}

const String guardrailReason =
    'insufficient-content-guardrail: report not mergeable, insufficient content, to verify';

/// Deterministic post-model (or post-classic) filter: splits any
/// group containing an insufficient-content report into singletons,
/// each marked uncertain with the explicit guardrail reason. Groups
/// without insufficient content are returned unchanged. The
/// `cancelledMerges` count = number of multi-report groups split:
/// it is the loggable trace of the cancellation, even if the model had
/// proposed the merge with low uncertainty.
({List<Group> groups, int cancelledMerges}) applyContentGuardrail(
    List<Report> reports, List<Group> groups) {
  final byId = {for (final r in reports) r.id: r};
  final out = <Group>[];
  var cancelled = 0;
  for (final g in groups) {
    final bad = g.reportIds.where(
        (id) => byId[id] != null && hasInsufficientContent(byId[id]!.text));
    if (bad.isEmpty) {
      out.add(g);
      continue;
    }
    if (g.reportIds.length > 1) cancelled++;
    for (final id in g.reportIds) {
      final isBad = bad.contains(id);
      out.add(Group(
        id: '',
        reportIds: [id],
        confidence: 0.0,
        singleton: true,
        method: g.method,
        uncertain: isBad ? true : g.uncertain,
        uncertaintyReasons: isBad
            ? [guardrailReason]
            : g.uncertaintyReasons,
        justification: isBad
            ? 'Guardrail: proposed merge cancelled (insufficient content)'
                '${g.justification == null ? '' : ' ; original proposal: ${g.justification}'}'
            : g.justification,
      ));
    }
  }
  out.sort((a, b) => a.reportIds.first.compareTo(b.reportIds.first));
  for (var i = 0; i < out.length; i++) {
    final g = out[i];
    out[i] = Group(
      id: 'G${i + 1}',
      reportIds: g.reportIds,
      confidence: g.confidence,
      singleton: g.singleton,
      method: g.method,
      uncertain: g.uncertain,
      uncertaintyReasons: g.uncertaintyReasons,
      justification: g.justification,
    );
  }
  return (groups: out, cancelledMerges: cancelled);
}

/// --- Units / statuses / time gate patch (pushed to main) ---
///
/// Representation choice, without breaking tests or persistence:
/// the `Group` type has no dedicated status field, so statuses
/// are carried by `uncertain = true` + an explicit reason in
/// `uncertaintyReasons` (`status-conflicting` or
/// `multi-problem-flag` prefix). No field is added to `Group`,
/// so `toJson` / `fromJson` and the server are unchanged. Statuses
/// NEVER split a group: they flag it. Only the time
/// gate (post-model, like the guardrail) splits, and each split
/// is counted in `splitGroups` and traced by a
/// `meta-time-gate` reason on each component from the split.

/// DEV problem families (limited lexicon, vocabulary of the
/// misleading scenarios + extended cases). Does not claim to cover
/// general French: an abbreviated form unknown to the lexicon (e.g.
/// "ndp" for roads is covered, but an unseen abbreviation
/// would not be) escapes the flag — documented limitation.
const Map<String, Set<String>> _problemFamilies = {
  'voirie-nid': {
    'nid', 'poule', 'ndp', 'trou', 'chaussee', 'chaus',
    'degradee', 'degrade', 'abimee', 'abim'
  },
  'eclairage': {'reverbere', 'lampadaire', 'lampadaires', 'eclairage', 'eteint', 'defaillant'},
  'eau': {'fuite', 'eau', 'inonde', 'canalisation', 'ecoulement'},
  'electricite': {'coupure', 'courant', 'electrique', 'electricite', 'panne'},
  // DEMO family §8 (gutter + waste): documented addition, at the end of
  // the lexicon to avoid changing the existing expansion order.
  // Like the other families: limited DEV vocabulary, no
  // general understanding of French.
  'assainissement': {'caniveau', 'dechet', 'dechets', 'assainissement'},
};

const Set<String> _resolvedTokens = {
  'resolue', 'resolu', 'sec', 'seche', 'termines', 'termine',
  'repares', 'repare'
};
const Set<String> _ongoingTokens = {'inonde', 'inondee', 'coule', 'coulee'};

/// Families touched by a report's text.
Set<String> reportProblemFamilies(Report r) {
  final toks = tokens(r.text);
  return {
    for (final e in _problemFamilies.entries)
      if (toks.intersection(e.value).isNotEmpty) e.key
  };
}

/// Does a report list at least two distinct problems?
bool hasMultiProblem(Report r) => reportProblemFamilies(r).length >= 2;

/// State contradiction reason (resolved vs ongoing), or null.
String? stateContradictionReason(List<Report> members) {
  final toks = <String>{};
  for (final r in members) {
    toks.addAll(tokens(r.text));
  }
  if (toks.intersection(_resolvedTokens).isNotEmpty &&
      toks.intersection(_ongoingTokens).isNotEmpty) {
    return 'state contradiction: resolved and ongoing markers in the same group';
  }
  return null;
}

/// Contradiction reasons of a group: state + declared
/// severity/exposure gaps >= 2. Values are kept,
/// never averaged.
List<String> groupContradictionReasons(
    List<Report> reports, List<String> reportIds) {
  final byId = {for (final r in reports) r.id: r};
  final members = [
    for (final id in reportIds)
      if (byId[id] != null) byId[id]!
  ];
  final reasons = <String>[];
  final state = stateContradictionReason(members);
  if (state != null) reasons.add(state);
  for (final entry in {
    'severity': members.map((r) => r.severityHint).whereType<int>(),
    'exposure': members.map((r) => r.exposureHint).whereType<int>(),
  }.entries) {
    final vals = entry.value.toList();
    if (vals.isNotEmpty &&
        vals.reduce((a, b) => a > b ? a : b) -
                vals.reduce((a, b) => a < b ? a : b) >=
            2) {
      reasons.add(
          'contradiction of ${entry.key}: declared values $vals, gap >= 2, kept without averaging');
    }
  }
  return reasons;
}

/// Applies statuses to groups, without changing their reportIds.
/// Also returns the number of conflicting groups and the number
/// of multi-problem groups (accounting traces, like
/// `cancelledMerges` for the guardrail).
({List<Group> groups, int contradictoryGroups, int multiProblemGroups})
    applyGroupStatuses(List<Report> reports, List<Group> groups) {
  final byId = {for (final r in reports) r.id: r};
  final out = <Group>[];
  var nContra = 0;
  var nMulti = 0;
  for (final g in groups) {
    final reasons = [...g.uncertaintyReasons];
    final contra = groupContradictionReasons(reports, g.reportIds);
    if (contra.isNotEmpty) {
      nContra++;
      for (final r in contra) {
        final labelled = 'status-conflicting: $r';
        if (!reasons.contains(labelled)) reasons.add(labelled);
      }
    }
    final multiIds = [
      for (final id in g.reportIds)
        if (byId[id] != null && hasMultiProblem(byId[id]!)) id
    ];
    if (multiIds.isNotEmpty) {
      nMulti++;
      reasons.add(
          'multi-problem-flag: report(s) ${multiIds.join(',')} listing >= 2 distinct problems; group not countable as a single clean incident');
    }
    out.add(Group(
      id: g.id,
      reportIds: g.reportIds,
      confidence: g.confidence,
      singleton: g.singleton,
      abstained: g.abstained,
      method: g.method,
      uncertain: g.uncertain || contra.isNotEmpty || multiIds.isNotEmpty,
      uncertaintyReasons: reasons,
      justification: g.justification,
    ));
  }
  return (
    groups: out,
    contradictoryGroups: nContra,
    multiProblemGroups: nMulti
  );
}

/// Post-model time gate (deterministic, counted).
///
/// Local threshold: 360 min (6 h), aligned with the classic gate
/// (deltaTMaxH = 6 h) for one-off incidents. Extended-event
/// exception: if ALL reports in the group have a
/// category in `extendedCategories` (network outage, network
/// failure — a network event can persist for several days),
/// threshold 10080 min (7 days). Mixed or one-off category -> local
/// threshold (conservative choice: we split). The gate must not
/// break extended events: that is why the exception is
/// explicit and tested (T25c), and why a mixed group falls back
/// to the local threshold rather than the extended one.
const int localTimeGateMin = 360;
const int extendedTimeGateMin = 10080;
const Set<String> extendedCategories = {
  'coupure-electrique',
  'panne-reseau'
};

({int gateMin, String kind}) timeGateFor(
    List<Report> reports, List<String> reportIds) {
  final byId = {for (final r in reports) r.id: r};
  final cats = {
    for (final id in reportIds)
      if (byId[id] != null) byId[id]!.category
  };
  if (cats.isNotEmpty &&
      cats.every((c) => extendedCategories.contains(c))) {
    return (gateMin: extendedTimeGateMin, kind: 'extended');
  }
  return (gateMin: localTimeGateMin, kind: 'local');
}

/// Post-model split of groups violating the time gate.
/// Returns the split groups + the number of groups split.
/// Each component from a split carries a
/// `meta-time-gate` reason; unsplit groups are unchanged.
({List<Group> groups, int splitGroups}) applyMetaTimeGate(
    List<Report> reports, List<Group> groups) {
  final byId = {for (final r in reports) r.id: r};
  final out = <Group>[];
  var split = 0;
  for (final g in groups) {
    final ids = g.reportIds;
    if (ids.length <= 1) {
      out.add(g);
      continue;
    }
    final gate = timeGateFor(reports, ids);
    final parent = {for (final id in ids) id: id};
    String find(String x) {
      var r = x;
      while (parent[r] != r) {
        r = parent[r]!;
      }
      while (parent[x] != r) {
        final nxt = parent[x]!;
        parent[x] = r;
        x = nxt;
      }
      return r;
    }

    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final a = byId[ids[i]];
        final b = byId[ids[j]];
        if (a != null && b != null && (a.t - b.t).abs() <= gate.gateMin) {
          parent[find(ids[i])] = find(ids[j]);
        }
      }
    }
    final comps = <String, List<String>>{};
    for (final id in ids) {
      comps.putIfAbsent(find(id), () => []).add(id);
    }
    if (comps.length == 1) {
      out.add(g);
      continue;
    }
    split++;
    for (final comp in comps.values) {
      comp.sort();
      final reasons = [...g.uncertaintyReasons];
      reasons.add(
          'meta-time-gate: proposed merge split, delay > ${gate.gateMin} min (threshold ${gate.kind})');
      out.add(Group(
        id: '',
        reportIds: comp,
        confidence: comp.length == 1 ? 0.0 : g.confidence,
        singleton: comp.length == 1,
        abstained: g.abstained,
        method: g.method,
        uncertain: true,
        uncertaintyReasons: reasons,
        justification: g.justification,
      ));
    }
  }
  out.sort((a, b) => a.reportIds.first.compareTo(b.reportIds.first));
  for (var i = 0; i < out.length; i++) {
    final g = out[i];
    out[i] = Group(
      id: 'G${i + 1}',
      reportIds: g.reportIds,
      confidence: g.confidence,
      singleton: g.singleton,
      abstained: g.abstained,
      method: g.method,
      uncertain: g.uncertain,
      uncertaintyReasons: g.uncertaintyReasons,
      justification: g.justification,
    );
  }
  return (groups: out, splitGroups: split);
}

/// --- Multi-problem splitting patch (local, pushed to main) ---
///
/// One report can describe several distinct problems. The
/// existing multi-problem flag signals this case, it does not resolve
/// it: a group [E1, E2] remains a single incident for the optimizer,
/// and the secondary problem (lighting) disappears from the plan.
///
/// Splitting resolves this case at grouping level, without
/// inventing a problem: each report is expanded into
/// sub-reports, one per explicit DEV family
/// (`reportProblemFamilies`, documented limited lexicon, no
/// claim to general French). A sub-report is identified as
/// `ORIGIN:FAMILY` (e.g. `E1:eclairage`): the origin is
/// recoverable on read by cutting at the first `:` (see
/// `originIdOfSubunit`), so splitting is reversible.
///
/// Rules:
/// - two sub-reports are grouped only if they share the
///   SAME family (`inconnu` family excluded: never merged) and
///   pass the distance and time gates of classic grouping.
///   No Jaccard threshold is applied after splitting: the explicit
///   family is the semantic match. Assumed limitation: this
///   rule is more permissive than the classic one; it only holds
///   because the family is explicit.
/// - insufficient content (guardrail) never merges.
/// - a report with a single family is not split; a
///   vague mention without an explicit family creates no
///   sub-report, hence no automatic splitting.
/// - classic `aggregate()` MUST NOT be called on groups
///   of sub-reports: it would look up `E1:eclairage` in the
///   reports table and fail. Use
///   `aggregateSplitGroups()` (lib/incidents.dart), which aggregates by
///   sub-report and keeps the split identifiers in
///   the incident. Persistence of sub-reports by the real server
///   (MongoDB / JSON) remains to be verified on a real server.
/// - split groups carry `method: 'split'` and a
///   `multi-problem-splitting` reason when they come from a
///   multi-problem report; they are marked uncertain, because
///   splitting relies on a DEV lexicon, not on field verification.
class Subunit {
  final String id; // ORIGINE:FAMILLE, ex. E1:eclairage
  final String originId;
  final String family;
  final Report report;
  const Subunit(
      {required this.id,
      required this.originId,
      required this.family,
      required this.report});
}

/// Origin of a sub-report identifier (reversibility).
String originIdOfSubunit(String subunitId) {
  final i = subunitId.indexOf(':');
  return i < 0 ? subunitId : subunitId.substring(0, i);
}

/// Deterministic expansion: one sub-report per DEV family.
/// Family order = lexicon order (voirie-nid, eclairage, eau,
/// electricite). No family -> a single `inconnu` sub-report,
/// which will never merge.
List<Subunit> expandToSubunits(List<Report> reports) {
  final out = <Subunit>[];
  for (final r in reports) {
    final fams = reportProblemFamilies(r);
    if (fams.isEmpty) {
      out.add(Subunit(
          id: '${r.id}:inconnu', originId: r.id, family: 'inconnu', report: r));
    } else {
      for (final f in fams) {
        out.add(Subunit(
            id: '${r.id}:$f', originId: r.id, family: f, report: r));
      }
    }
  }
  return out;
}

class _UnionFindSplit {
  final List<int> _p;
  _UnionFindSplit(int n) : _p = List.generate(n, (i) => i);
  int find(int x) {
    while (_p[x] != x) {
      _p[x] = _p[_p[x]];
      x = _p[x];
    }
    return x;
  }

  void union(int a, int b) {
    _p[find(a)] = find(b);
  }
}

/// Grouping by sub-reports (global, not a post-filter).
List<Group> groupSplitReports(
  List<Report> reports, {
  required double distMaxM,
  required double deltaTMaxH,
}) {
  final units = expandToSubunits(reports);
  final distMaxKm = distMaxM / 1000.0;
  final deltaTMaxMin = (deltaTMaxH * 60).round();
  final uf = _UnionFindSplit(units.length);
  for (var i = 0; i < units.length; i++) {
    for (var j = i + 1; j < units.length; j++) {
      final a = units[i], b = units[j];
      if (a.family != b.family || a.family == 'inconnu') continue;
      if (hasInsufficientContent(a.report.text) ||
          hasInsufficientContent(b.report.text)) {
        continue;
      }
      if (distKm(a.report, b.report) <= distMaxKm &&
          dtMin(a.report, b.report) <= deltaTMaxMin) {
        uf.union(i, j);
      }
    }
  }
  final comps = <int, List<int>>{};
  for (var i = 0; i < units.length; i++) {
    comps.putIfAbsent(uf.find(i), () => []).add(i);
  }
  final ordered = comps.values.toList()
    ..sort((a, b) => units[a.first].id.compareTo(units[b.first].id));
  final groups = <Group>[];
  var gi = 0;
  for (final comp in ordered) {
    comp.sort((a, b) => units[a].id.compareTo(units[b].id));
    gi++;
    final ids = [for (final i in comp) units[i].id];
    final origins = {for (final i in comp) units[i].originId};
    final multi = origins.any((id) => hasMultiProblem(
        reports.firstWhere((r) => r.id == id)));
    final reasons = <String>[];
    if (multi) {
      reasons.add(
          'multi-problem-splitting: group from a report listing >= 2 distinct problems; verify the splitting (DEV lexicon)');
    }
    groups.add(Group(
      id: 'G$gi',
      reportIds: ids,
      confidence: 0.0,
      singleton: ids.length == 1,
      method: 'split',
      uncertain: multi,
      uncertaintyReasons: reasons,
      justification: multi
          ? 'Multi-problem splitting by DEV family; origin(s): ${origins.join(',')}'
          : null,
    ));
  }
  return groups;
}

/// Post-filter: splits each group of reports into
/// sub-groups by family, WITHOUT merging across origin groups.
/// A group without a multi-problem report is returned unchanged
/// (report identifiers, not sub-report identifiers).
/// Returns the split groups + the number of groups split.
({List<Group> groups, int splitGroups}) splitGroupsByFamily(
    List<Report> reports, List<Group> groups) {
  final byId = {for (final r in reports) r.id: r};
  final out = <Group>[];
  var split = 0;
  for (final g in groups) {
    final members = [for (final id in g.reportIds) if (byId[id] != null) byId[id]!];
    if (!members.any(hasMultiProblem)) {
      out.add(g);
      continue;
    }
    split++;
    final units = expandToSubunits(members);
    final byFamily = <String, List<String>>{};
    for (final u in units) {
      byFamily.putIfAbsent(u.family, () => []).add(u.id);
    }
    for (final entry in byFamily.entries) {
      entry.value.sort();
      out.add(Group(
        id: '',
        reportIds: entry.value,
        confidence: 0.0,
        singleton: entry.value.length == 1,
        method: 'split',
        uncertain: true,
        uncertaintyReasons: [
          'multi-problem-splitting: group ${g.id} split by DEV family (${entry.key}); origin(s): ${members.map((r) => r.id).join(',')}'
        ],
        justification: g.justification,
      ));
    }
  }
  out.sort((a, b) => a.reportIds.first.compareTo(b.reportIds.first));
  for (var i = 0; i < out.length; i++) {
    final g = out[i];
    out[i] = Group(
      id: 'G${i + 1}',
      reportIds: g.reportIds,
      confidence: g.confidence,
      singleton: g.singleton,
      abstained: g.abstained,
      method: g.method,
      uncertain: g.uncertain,
      uncertaintyReasons: g.uncertaintyReasons,
      justification: g.justification,
    );
  }
  return (groups: out, splitGroups: split);
}

double jaccard(String a, String b) {
  final ta = tokens(a);
  final tb = tokens(b);
  // Two texts without tokens: no evidence of similarity (not 1.0).
  if (ta.isEmpty && tb.isEmpty) return 0.0;
  if (ta.isEmpty || tb.isEmpty) return 0.0;
  final inter = ta.intersection(tb).length;
  final union = ta.union(tb).length;
  return inter / union;
}

double distKm(Report a, Report b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return dx * dx + dy * dy > 0 ? _sqrt(dx * dx + dy * dy) : 0.0;
}

// Newton square root (avoids dart:math for a pure module).
double _sqrt(double v) {
  if (v <= 0) return 0.0;
  var g = v / 2.0;
  for (var i = 0; i < 30; i++) {
    g = (g + v / g) / 2.0;
  }
  return g;
}

int dtMin(Report a, Report b) => (a.t - b.t).abs();

class _UnionFind {
  final List<int> parent;
  _UnionFind(int n) : parent = List<int>.generate(n, (i) => i);
  int find(int i) {
    var r = i;
    while (parent[r] != r) {
      r = parent[r];
    }
    while (parent[i] != r) {
      final nxt = parent[i];
      parent[i] = r;
      i = nxt;
    }
    return r;
  }

  void union(int a, int b) {
    parent[find(a)] = find(b);
  }
}

/// Groups the reports. Parameters in prototype SI units:
/// distMaxM (metres), deltaTMaxH (hours), simMin (Jaccard 0..1).
List<Group> groupReports(
  List<Report> reports, {
  required double distMaxM,
  required double deltaTMaxH,
  required double simMin,
}) {
  final n = reports.length;
  final uf = _UnionFind(n);
  final edgeSim = <String, double>{};
  final distMaxKm = distMaxM / 1000.0;
  final deltaTMaxMin = (deltaTMaxH * 60).round();
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final a = reports[i];
      final b = reports[j];
      // Guardrail: insufficient content NEVER merges, whatever
      // the distance, time or similarity (two empty texts
      // have a Jaccard of 0.0, but the rule is explicit and depends
      // on no threshold).
      if (hasInsufficientContent(a.text) || hasInsufficientContent(b.text)) {
        continue;
      }
      if (distKm(a, b) <= distMaxKm && dtMin(a, b) <= deltaTMaxMin) {
        final s = jaccard(a.text, b.text);
        if (s >= simMin) {
          uf.union(i, j);
          edgeSim['$i|$j'] = s;
        }
      }
    }
  }
  final comps = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    comps.putIfAbsent(uf.find(i), () => []).add(i);
  }
  // Deterministic order: sort by smallest report id.
  final ordered = comps.values.toList()
    ..sort((a, b) => reports[a.first].id.compareTo(reports[b.first].id));
  final groups = <Group>[];
  var gi = 0;
  for (final comp in ordered) {
    comp.sort((a, b) => reports[a].id.compareTo(reports[b].id));
    double conf = 0.0;
    if (comp.length > 1) {
      conf = 1.0;
      for (var x = 0; x < comp.length; x++) {
        for (var y = x + 1; y < comp.length; y++) {
          final key = comp[x] < comp[y]
              ? '${comp[x]}|${comp[y]}'
              : '${comp[y]}|${comp[x]}';
          final s = edgeSim[key];
          if (s != null && s < conf) conf = s;
        }
      }
    }
    // Grouping uncertainty: flagged, never hidden.
    final reasons = <String>[];
    if (comp.length == 1 &&
        hasInsufficientContent(reports[comp.first].text)) {
      reasons.add(guardrailReason);
    }
    if (comp.length > 1) {
      if (conf <= simMin + 0.10) {
        reasons.add(
            'minimum similarity ${conf.toStringAsFixed(2)} close to threshold $simMin');
      }
      // Transitive chaining: internal pair without a direct edge.
      for (var x = 0; x < comp.length && reasons.length < 4; x++) {
        for (var y = x + 1; y < comp.length; y++) {
          final key = comp[x] < comp[y]
              ? '${comp[x]}|${comp[y]}'
              : '${comp[y]}|${comp[x]}';
          if (!edgeSim.containsKey(key)) {
            reasons.add(
                'transitive chaining: ${reports[comp[x]].id}-${reports[comp[y]].id} with no direct edge');
            break;
          }
        }
      }
      final sevHints =
          comp.map((i) => reports[i].severityHint).whereType<int>().toList();
      if (sevHints.isNotEmpty &&
          sevHints.reduce((a, b) => a > b ? a : b) -
                  sevHints.reduce((a, b) => a < b ? a : b) >=
              2) {
        reasons.add('conflicting declared severities in the group');
      }
      // Units/statuses patch: the classic one also carries statuses
      // (reasons only, grouping unchanged).
      final members = comp.map((i) => reports[i]).toList();
      final state = stateContradictionReason(members);
      if (state != null) reasons.add('status-conflicting: $state');
      final multiIds = members
          .where((r) => hasMultiProblem(r))
          .map((r) => r.id)
          .toList();
      if (multiIds.isNotEmpty) {
        reasons.add(
            'multi-problem-flag: report(s) ${multiIds.join(',')} listing >= 2 distinct problems; group not countable as a single clean incident');
      }
    }
    gi++;
    groups.add(Group(
      id: 'G$gi',
      reportIds: comp.map((i) => reports[i].id).toList(),
      confidence: comp.length > 1 ? conf : 0.0,
      singleton: comp.length == 1,
      uncertain: reasons.isNotEmpty,
      uncertaintyReasons: reasons,
    ));
  }
  return groups;
}

/// Pairs NOT grouped but ambiguous (near-merges / doubtful
/// splits). Flags an uncertain separation instead of
/// imposing it silently (case E2: same place/time, disjoint vocabulary).
List<Map<String, dynamic>> ambiguousPairs(
  List<Report> reports,
  List<Group> groups, {
  required double distMaxM,
  required double deltaTMaxH,
  required double simMin,
}) {
  final groupOf = <String, String>{};
  for (final g in groups) {
    for (final id in g.reportIds) {
      groupOf[id] = g.id;
    }
  }
  final out = <Map<String, dynamic>>[];
  final distMaxKm = distMaxM / 1000.0;
  final deltaTMaxMin = (deltaTMaxH * 60).round();
  for (var i = 0; i < reports.length; i++) {
    for (var j = i + 1; j < reports.length; j++) {
      final a = reports[i], b = reports[j];
      if (groupOf[a.id] == groupOf[b.id]) continue;
      final dKm = distKm(a, b);
      final dt = dtMin(a, b);
      final s = jaccard(a.text, b.text);
      String? reason;
      if (dKm <= distMaxKm && dt <= deltaTMaxMin && s < simMin) {
        reason =
            'spatio-temporal proximity but insufficient vocabulary (Jaccard ${s.toStringAsFixed(2)} < $simMin): uncertain separation';
      } else if (s >= simMin && dKm > distMaxKm && dKm <= distMaxKm * 2) {
        reason =
            'similar text but distance ${(dKm * 1000).round()} m beyond the ${distMaxM.round()} m threshold: uncertain separation';
      } else if (s >= simMin && dt <= deltaTMaxMin && dKm > distMaxKm * 2) {
        // E4 (pushed to main): same text, very far away. Do not
        // force a merge (two real incidents can share a
        // text), but do not split silently: flag the distant
        // duplicate for a human to verify.
        reason =
            'similar text (Jaccard ${s.toStringAsFixed(2)}) but distance ${(dKm * 1000).round()} m, well beyond the ${distMaxM.round()} m threshold: uncertain separation, distant duplicate to verify, not merged';
      }
      if (reason != null) {
        out.add({
          'a': a.id,
          'b': b.id,
          'sim': s,
          'distM': (dKm * 1000).round(),
          'dtMin': dt,
          'reason': reason,
        });
      }
    }
  }
  return out;
}
