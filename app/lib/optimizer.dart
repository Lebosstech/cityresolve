// COMMON exact optimizer (single engine, independent of grouping).
//
// Method: full enumeration of assignments (incident -> team/none)
// × orders per team, earliest scheduling simulation, selection of the
// best plan. Exact for n <= 9 incidents (anti-explosion guard).
// Tie-breaks: decreasing Q, increasing cost, increasing duration, stable id.
// Planning on accessible ESTIMATES; scoring uses the truth.
import 'policy.dart';
import 'types.dart';

double manhattanKm(double x1, double y1, double x2, double y2) =>
    (x1 - x2).abs() + (y1 - y2).abs();

int estDurationMin(int? severity) => siteDurationsMin[severity] ?? 60;

/// Task duration (site + outbound travel) and cost with given parameters.
class SchedTask {
  final String incidentId;
  final double x, y;
  final int siteMin;
  final int deadline; // -1 if S5 (never planned)
  final int firstSeen; // knowledge: cannot start before
  const SchedTask({
    required this.incidentId,
    required this.x,
    required this.y,
    required this.siteMin,
    required this.deadline,
    this.firstSeen = 0,
  });
}

class SchedResult {
  final List<Task> tasks;
  final double totalCost;
  final int spanMin;
  final Set<String> completed;
  const SchedResult(this.tasks, this.totalCost, this.spanMin, this.completed);
}

/// Earliest scheduling of a team (depot departure every morning).
/// teamId used for the Tasks. Returns tasks + costs + completed (end <= deadline).
SchedResult simulateTeamSchedule(
    String teamId, List<SchedTask> ordered, double depotX, double depotY) {
  final tasks = <Task>[];
  var day = 0;
  var time = dayStartMin;
  var px = depotX, py = depotY;
  var cost = 0.0;
  var firstStart = -1, lastEnd = 0;
  final completed = <String>{};
  for (var k = 0; k < ordered.length; k++) {
    final t = ordered[k];
    // First slot: knowledge (firstSeen) + hours, following days included.
    var dDay = day, dTime = time, dPx = px, dPy = py;
    var placed = false;
    while (dDay < horizonDays) {
      final open = dDay * 1440 + dayStartMin;
      final close = dDay * 1440 + dayEndMin;
      final tv =
          (manhattanKm(dPx, dPy, t.x, t.y) * travelMinPerKm).ceil();
      var s = dTime + tv;
      if (s < open) s = open;
      if (s < t.firstSeen) s = t.firstSeen;
      final e = s + t.siteMin;
      if (s <= close && e <= close) {
        final travelKm = manhattanKm(dPx, dPy, t.x, t.y);
        final taskCost = (t.siteMin / 60.0) * siteRatePerHour +
            travelKm * travelRatePerKm;
        cost += taskCost;
        if (firstStart < 0) firstStart = s;
        lastEnd = e;
        tasks.add(Task(
            incidentId: t.incidentId,
            teamId: teamId,
            order: k + 1,
            startMin: s,
            endMin: e,
            travelKm: travelKm,
            cost: taskCost));
        if (t.deadline >= 0 && e <= t.deadline) completed.add(t.incidentId);
        day = dDay;
        time = e;
        px = t.x;
        py = t.y;
        placed = true;
        break;
      }
      dDay += 1;
      dTime = dDay * 1440 + dayStartMin;
      dPx = depotX;
      dPy = depotY;
    }
    if (!placed) break; // queue abandoned (rest unplanned)
  }
  return SchedResult(tasks, cost, firstStart < 0 ? 0 : lastEnd - firstStart,
      completed);
}

String fmtMin(int m) {
  final d = m ~/ 1440;
  final hh = ((m % 1440) ~/ 60).toString().padLeft(2, '0');
  final mm = (m % 60).toString().padLeft(2, '0');
  return 'D$d $hh:$mm';
}

/// Earliest end of a single incident (dedicated competent team, estimates).
int earliestEnd(Incident inc, List<Team> teams) {
  var best = 1 << 30;
  for (final team in teams) {
    if (!team.domains.contains(inc.domain)) continue;
    final dur = estDurationMin(inc.severity);
    var day = inc.firstSeen ~/ 1440;
    var earliest = inc.firstSeen;
    if (earliest < day * 1440 + dayStartMin) earliest = day * 1440 + dayStartMin;
    final travelMin =
        (manhattanKm(0, 0, inc.x, inc.y) * travelMinPerKm).ceil();
    var start = earliest + travelMin;
    var end = start + dur;
    if (end > day * 1440 + dayEndMin) {
      day += 1;
      start = day * 1440 + dayStartMin + travelMin;
      end = start + dur;
    }
    if (end < best) best = end;
  }
  return best;
}

List<List<T>> _permutations<T>(List<T> items) {
  if (items.isEmpty) return [[]]; // team without task: an empty order
  final out = <List<T>>[];
  void gen(List<T> arr, int k) {
    if (k == 1) {
      out.add(List<T>.from(arr));
      return;
    }
    for (var i = 0; i < k; i++) {
      gen(arr, k - 1);
      if (k % 2 == 1) {
        final tmp = arr[0];
        arr[0] = arr[k - 1];
        arr[k - 1] = tmp;
      } else {
        final tmp = arr[i];
        arr[i] = arr[k - 1];
        arr[k - 1] = tmp;
      }
    }
  }

  gen(List<T>.from(items), items.length);
  return out;
}

double _planQ(Set<String> completed, Map<String, double> weights) {
  var num = 0.0, den = 0.0;
  weights.forEach((id, w) {
    den += w;
    if (completed.contains(id)) num += w;
  });
  if (den == 0) return 0.0;
  return 100.0 * num / den;
}

/// Optimizes exactly. Throws if more than 9 S1..S4 incidents (guard).
Plan optimizeExact({
  required List<Incident> incidents,
  required List<Team> teams,
}) {
  // S5 (declared severity >= 5): human escalation, never dispatched.
  final escalations = incidents
      .where((i) => i.severity != null && i.severity! >= 5)
      .map((i) => i.id)
      .toList();
  // Unknown/conflicting severity: never any automatic dispatch.
  final blocked = <String, String>{};
  for (final i in incidents.where((i) => i.severity == null)) {
    blocked[i.id] = i.severityStatus == statusContradictoire
        ? 'conflicting declared severities ${i.severityValues}: human verification required before dispatch'
        : 'unknown severity: human verification required before dispatch';
  }
  final cands =
      incidents.where((i) => i.severity != null && i.severity! <= 4).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
  if (cands.length > 9) {
    throw StateError(
        'Exact optimizer limited to 9 incidents (${cands.length} received).');
  }
  final weights = {for (final c in cands) c.id: c.weight};
  Plan? best;
  double bestQ = -1, bestCost = 1e18;
  var bestSpan = 1 << 30;
  var bestId = '';
  final k = teams.length;
  if (k < 1 || k > 3) {
    throw StateError('Exact optimizer: 1 to 3 teams ($k received).');
  }
  final n = cands.length;
  final base = k + 1;
  var total = 1;
  for (var i = 0; i < n; i++) {
    total *= base;
  }
  // Enumeration of assignments in base k+1 (0=none, 1..k=teams).
  for (var code = 0; code < total; code++) {
    final assign = <int>[];
    var c = code;
    for (var i = 0; i < n; i++) {
      assign.add(c % base);
      c ~/= base;
    }
    final perTeam = <int, List<Incident>>{
      for (var t = 0; t < k; t++) t: []
    };
    for (var i = 0; i < n; i++) {
      if (assign[i] > 0) perTeam[assign[i] - 1]!.add(cands[i]);
    }
    // Skills: immediate rejection if the team is not competent.
    var ok = true;
    for (var t = 0; t < k; t++) {
      for (final inc in perTeam[t]!) {
        if (!teams[t].domains.contains(inc.domain)) {
          ok = false;
          break;
        }
      }
    }
    if (!ok) continue;
    // Cartesian product of the orders per team.
    var combos = <List<List<Incident>>>[[]];
    for (var t = 0; t < k; t++) {
      final next = <List<List<Incident>>>[];
      for (final prefix in combos) {
        for (final order in _permutations(perTeam[t]!)) {
          next.add([...prefix, order]);
        }
      }
      combos = next;
    }
    for (final combo in combos) {
      final completed = <String>{};
        var cost = 0.0;
        var span = 0;
        final all = <Task>[];
        for (var t = 0; t < k; t++) {
          final r = simulateTeamSchedule(
              teams[t].id,
              combo[t]
                  .map((inc) => SchedTask(
                      incidentId: inc.id,
                      x: inc.x,
                      y: inc.y,
                      siteMin: estDurationMin(inc.severity),
                      deadline: inc.deadline,
                      firstSeen: inc.firstSeen))
                  .toList(),
              0,
              0);
          completed.addAll(r.completed);
          cost += r.totalCost;
          if (r.spanMin > span) span = r.spanMin;
          all.addAll(r.tasks);
        }
        if (cost > budgetUnits) continue; // strict budget
        final q = _planQ(completed, weights);
        all.sort((a, b) => a.incidentId.compareTo(b.incidentId));
        final cid = all.map((t) => '${t.teamId}:${t.incidentId}').join(',');
        final better = q > bestQ + 1e-9 ||
            ((q - bestQ).abs() <= 1e-9 &&
                (cost < bestCost - 1e-9 ||
                    ((cost - bestCost).abs() <= 1e-9 &&
                        (span < bestSpan ||
                            (span == bestSpan &&
                                (best == null || cid.compareTo(bestId) < 0))))));
        if (better) {
          bestQ = q;
          bestCost = cost;
          bestSpan = span;
          bestId = cid;
          best = Plan(
              tasks: all,
              unassigned: {},
              escalations: escalations,
              totalCost: cost,
              q: q,
              feasible: true,
              violations: [],
              justifications: {});
        }
      }
  }
  best ??= Plan(
      tasks: [],
      unassigned: {},
      escalations: escalations,
      totalCost: 0,
      q: 0,
      feasible: true,
      violations: [],
      justifications: {});
  // Non-assignment reasons + justifications.
  final assigned = best.tasks.map((t) => t.incidentId).toSet();
  final unassigned = <String, String>{};
  final just = <String, String>{};
  for (final t in best.tasks) {
    final inc = cands.firstWhere((c) => c.id == t.incidentId);
    just[t.incidentId] =
        '${t.teamId} order ${t.order}, ${fmtMin(t.startMin)}→${fmtMin(t.endMin)}, '
        'cost ${t.cost.toStringAsFixed(1)}, deadline margin ${inc.deadline - t.endMin} min.';
  }
  for (final inc in cands) {
    if (assigned.contains(inc.id)) continue;
    String reason;
    final competent =
        teams.any((tm) => tm.domains.contains(inc.domain));
    if (!competent) {
      reason = 'no competent team (${inc.domain})';
    } else if (earliestEnd(inc, teams) > inc.deadline) {
      reason = 'deadline unreachable even alone (${fmtMin(inc.deadline)})';
    } else {
      final cheapest = (estDurationMin(inc.severity) / 60.0) * siteRatePerHour;
      if (cheapest > budgetUnits) {
        reason = 'insufficient budget even alone';
      } else {
        reason = 'not selected by the optimizer (maximum Q without it)';
      }
    }
    unassigned[inc.id] = reason;
    just[inc.id] = 'Not assigned: $reason.';
  }
  for (final e in escalations) {
    just[e] = 'S5: immediate human escalation, never dispatched.';
  }
  blocked.forEach((id, reason) {
    unassigned[id] = reason;
    just[id] = 'Not assigned: $reason.';
  });
  return Plan(
      tasks: best.tasks,
      unassigned: unassigned,
      escalations: escalations,
      totalCost: best.totalCost,
      q: best.q,
      feasible: true,
      violations: [],
      justifications: just);
}
