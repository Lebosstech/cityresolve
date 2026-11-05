// Decision oracle (C6 §5): necessity of a review with only the
// available information (observables + estimates). Hidden truth
// is only used to score, never to judge. Deterministic.
// Cross-phase matching by report overlap (stable ids
// not required); removed teams detected.
import 'optimizer.dart';
import 'policy.dart';
import 'types.dart';

class Necessity {
  final String code; // N1, N1b, N2, N3-S5, N3-S4, U
  final bool necessary;
  final String detail;
  const Necessity(this.code, this.necessary, this.detail);
  Map<String, dynamic> toJson() =>
      {'code': code, 'necessary': necessary, 'detail': detail};
}

/// Old -> new incident matching (maximum overlap, >0 required).
String? matchIncident(Set<String> oldReports, List<Incident> updated) {
  String? best;
  var bestN = 0;
  for (final u in updated) {
    final n = oldReports.intersection(u.reportIds.toSet()).length;
    if (n > bestN) {
      bestN = n;
      best = u.id;
    }
  }
  return best;
}

/// Judges whether the old plan must change given the updated incidents.
Necessity judgeRevision({
  required Plan oldPlan,
  required List<Incident> oldIncidents,
  required List<Incident> updated,
  required List<Team> teams,
  Set<String> newS5 = const {},
}) {
  if (newS5.isNotEmpty) {
    return const Necessity('N3-S5', true,
        'S5 revealed: human escalation required, no reassignment.');
  }
  final oldById = {for (final i in oldIncidents) i.id: i};
  final newById = {for (final i in updated) i.id: i};
  final teamIds = teams.map((t) => t.id).toSet();
  for (final t in oldPlan.tasks) {
    if (!teamIds.contains(t.teamId)) {
      return Necessity('N1', true,
          'Team ${t.teamId} unavailable: reassignment required.');
    }
  }
  final mapping = <String, String>{}; // ancien id -> nouvel id
  for (final t in oldPlan.tasks) {
    final old = oldById[t.incidentId];
    final m = old == null
        ? null
        : matchIncident(old.reportIds.toSet(), updated);
    if (m == null) {
      return Necessity('N1', true,
          'Grouping changed: ${t.incidentId} disappeared.');
    }
    mapping[t.incidentId] = m;
  }
  // Re-evaluates the old plan (mapped) with the updated estimates,
  // orders kept.
  final perTeam = <String, List<SchedTask>>{};
  final oldOrder = {for (final t in oldPlan.tasks) t.incidentId: t.order};
  for (final t in oldPlan.tasks) {
    final inc = newById[mapping[t.incidentId]!]!;
    perTeam.putIfAbsent(t.teamId, () => []).add(SchedTask(
        incidentId: t.incidentId,
        x: inc.x,
        y: inc.y,
        siteMin: estDurationMin(inc.severity),
        deadline: inc.deadline,
        firstSeen: inc.firstSeen));
  }
  for (final e in perTeam.entries) {
    e.value.sort((a, b) =>
        oldOrder[a.incidentId]!.compareTo(oldOrder[b.incidentId]!));
  }
  final weights = {
    for (final i in updated)
      if (i.severity != null && i.severity! <= 4) i.id: i.weight
  };
  final completedOld = <String>{};
  var oldCost = 0.0;
  var infeasible = false;
  for (final team in teams) {
    final r =
        simulateTeamSchedule(team.id, perTeam[team.id] ?? [], 0, 0);
    oldCost += r.totalCost;
    for (final st in r.tasks) {
      final inc = newById[mapping[st.incidentId]!]!;
      if (!team.domains.contains(inc.domain)) infeasible = true;
      if (inc.deadline >= 0 && st.endMin > inc.deadline) infeasible = true;
      if (r.completed.contains(st.incidentId)) {
        completedOld.add(mapping[st.incidentId]!);
      }
    }
  }
  if (oldCost > budgetUnits) infeasible = true;
  var num = 0.0, den = 0.0;
  weights.forEach((id, w) {
    den += w;
    if (completedOld.contains(id)) num += w;
  });
  final oldQ = den == 0 ? 0.0 : 100.0 * num / den;
  Plan? fresh;
  try {
    fresh = optimizeExact(incidents: updated, teams: teams);
  } catch (_) {
    fresh = null;
  }
  if (infeasible) {
    if (fresh != null && fresh.tasks.isNotEmpty) {
      return Necessity('N1', true,
          'Old plan infeasible; feasible alternative (Q=${fresh.q.toStringAsFixed(1)}).');
    }
    return const Necessity('N1b', false,
        'Old plan infeasible with no alternative: flag it, do not reassign.');
  }
  if (fresh != null && fresh.q - oldQ >= revisionThresholdQ - 1e-9) {
    return Necessity('N2', true,
        'Gain +${(fresh.q - oldQ).toStringAsFixed(1)} Q points (threshold $revisionThresholdQ).');
  }
  final g = fresh == null ? 0.0 : fresh.q - oldQ;
  return Necessity('U', false,
      'Old plan feasible, gain +${g.toStringAsFixed(1)} < $revisionThresholdQ: stability.');
}

class PlanDiff {
  final bool material;
  final String detail;
  const PlanDiff(this.material, this.detail);
}

/// Material change between two plans (overlap matching,
/// 30 min cosmetic rule).
PlanDiff comparePlans(
  Plan oldPlan,
  Plan newPlan, {
  required Map<String, Set<String>> oldReports,
  required Map<String, Set<String>> newReports,
}) {
  // Match each old task (maximum overlap).
  final match = <String, String>{};
  for (final t in oldPlan.tasks) {
    final ors = oldReports[t.incidentId] ?? {};
    String? best;
    var bestN = 0;
    newReports.forEach((nid, nrs) {
      final n = ors.intersection(nrs).length;
      if (n > bestN) {
        bestN = n;
        best = nid;
      }
    });
    if (best == null) {
      return const PlanDiff(true, 'Incident selection changed.');
    }
    match[t.incidentId] = best!;
  }
  // New tasks without a predecessor?
  final matchedNew = match.values.toSet();
  for (final t in newPlan.tasks) {
    if (!matchedNew.contains(t.incidentId)) {
      return const PlanDiff(true, 'Incident selection changed.');
    }
  }
  final n = {for (final t in newPlan.tasks) t.incidentId: t};
  for (final t in oldPlan.tasks) {
    // A matched incident with no task in the new plan (e.g. no
    // competent team left after team_down) is a material change,
    // never a crash: the old code dereferenced n[...] without a check.
    final u = n[match[t.incidentId]!];
    if (u == null) {
      return PlanDiff(true,
          'Incident ${t.incidentId} not carried over to the new plan.');
    }
    if (t.teamId != u.teamId) {
      return PlanDiff(true, 'Reassignment of ${t.incidentId}.');
    }
    if (t.order != u.order) {
      return PlanDiff(true, 'Order changed for ${t.incidentId}.');
    }
    if ((t.startMin - u.startMin).abs() >= cosmeticShiftMin ||
        (t.endMin - u.endMin).abs() >= cosmeticShiftMin) {
      return PlanDiff(true, 'Times changed ≥ $cosmeticShiftMin min.');
    }
  }
  return const PlanDiff(false, 'Unchanged or cosmetic differences < 30 min.');
}
