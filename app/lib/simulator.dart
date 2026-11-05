// Simulator: applies the hidden TRUTH to score (never to plan).
//
// Rules: impure proposed group (merge of truths) => R=0; team
// not competent on the true domain => execution violation; TRUE durations, costs,
// positions and deadlines for scoring. Global violation => Q=0.
// Robustness: re-scoring with frozen plans, durations/costs ×1.2/×1.5 (6 variants).
import 'metrics.dart';
import 'optimizer.dart';
import 'policy.dart';
import 'types.dart';

class TaskOutcome {
  final String incidentId;
  final String? truthId;
  final bool pure;
  final int result;
  final String reason;
  final int startMin;
  final int endMin;
  final double cost;
  const TaskOutcome({
    required this.incidentId,
    required this.truthId,
    required this.pure,
    required this.result,
    required this.reason,
    required this.startMin,
    required this.endMin,
    required this.cost,
  });
  Map<String, dynamic> toJson() => {
        'incidentId': incidentId,
        'truthId': truthId,
        'pure': pure,
        'result': result,
        'reason': reason,
        'startMin': startMin,
        'endMin': endMin,
        'cost': cost,
      };
}

class SimResult {
  final List<TaskOutcome> outcomes;
  final List<String> missedTruth;
  final double? q;
  final bool feasible;
  final List<String> violations;
  final double totalCost;
  final List<String> structurallyInfeasible;
  const SimResult({
    required this.outcomes,
    required this.missedTruth,
    required this.q,
    required this.feasible,
    required this.violations,
    required this.totalCost,
    required this.structurallyInfeasible,
  });
  Map<String, dynamic> toJson() => {
        'outcomes': outcomes.map((o) => o.toJson()).toList(),
        'missedTruth': missedTruth,
        'q': q,
        'feasible': feasible,
        'violations': violations,
        'totalCost': totalCost,
        'structurallyInfeasible': structurallyInfeasible,
      };

  static TaskOutcome outcomeFromJson(Map<String, dynamic> j) => TaskOutcome(
        incidentId: j['incidentId'] as String,
        truthId: j['truthId'] as String?,
        pure: j['pure'] as bool? ?? false,
        result: (j['result'] as num).toInt(),
        reason: (j['reason'] ?? '') as String,
        startMin: (j['startMin'] as num).toInt(),
        endMin: (j['endMin'] as num).toInt(),
        cost: (j['cost'] as num).toDouble(),
      );

  static SimResult fromJson(Map<String, dynamic> j) => SimResult(
        outcomes: (j['outcomes'] as List)
            .map((e) => outcomeFromJson(e as Map<String, dynamic>))
            .toList(),
        missedTruth:
            (j['missedTruth'] as List? ?? []).map((e) => '$e').toList(),
        q: (j['q'] as num?)?.toDouble(),
        feasible: j['feasible'] as bool? ?? false,
        violations:
            (j['violations'] as List? ?? []).map((e) => '$e').toList(),
        totalCost: (j['totalCost'] as num).toDouble(),
        structurallyInfeasible: (j['structurallyInfeasible'] as List? ?? [])
            .map((e) => '$e')
            .toList(),
      );
}

/// Earliest end with the TRUE values (dedicated competent team).
int earliestEndTruth(TruthIncident t, List<Team> teams) {
  var best = 1 << 30;
  final dur = (siteDurationsMin[t.severity]! * t.durationMult).round();
  for (final team in teams) {
    if (!team.domains.contains(t.domain)) continue;
    var day = t.firstArrival ~/ 1440;
    var earliest = t.firstArrival;
    if (earliest < day * 1440 + dayStartMin) earliest = day * 1440 + dayStartMin;
    final travelMin =
        (manhattanKm(0, 0, t.x, t.y) * travelMinPerKm).ceil();
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

SimResult simulate({
  required Plan plan,
  required List<Incident> proposed,
  required List<TruthIncident> truth,
  required List<Team> teams,
}) {
  final propById = {for (final p in proposed) p.id: p};
  // Proposed -> truth matching (maximum overlap).
  final link = <String, TruthIncident?>{};
  final pure = <String, bool>{};
  for (final p in proposed) {
    final pset = p.reportIds.toSet();
    TruthIncident? best;
    var bestN = 0;
    for (final t in truth) {
      final n = pset.intersection(t.reportIds).length;
      if (n > bestN) {
        bestN = n;
        best = t;
      }
    }
    link[p.id] = bestN > 0 ? best : null;
    // Impure = merge of >= 2 distinct truths. Reports outside
    // truth (e.g. manual addition) do not make a group impure on their own.
    final hits = truth
        .where((t) => pset.intersection(t.reportIds).isNotEmpty)
        .length;
    pure[p.id] = hits <= 1;
  }
  // Replay per team with true values, plan order.
  final byTeam = <String, List<Task>>{};
  for (final t in plan.tasks) {
    byTeam.putIfAbsent(t.teamId, () => []).add(t);
  }
  final outcomes = <TaskOutcome>[];
  final violations = <String>[];
  var totalCost = 0.0;
  for (final team in teams) {
    final seq = (byTeam[team.id] ?? [])
      ..sort((a, b) => a.order.compareTo(b.order));
    final sched = simulateTeamSchedule(
        team.id,
        seq.map((t) {
          final p = propById[t.incidentId]!;
          final tr = link[t.incidentId];
          final dur = tr == null
              ? estDurationMin(p.severity)
              : (siteDurationsMin[tr.severity]! * tr.durationMult).round();
          return SchedTask(
              incidentId: t.incidentId,
              x: tr?.x ?? p.x,
              y: tr?.y ?? p.y,
              siteMin: dur,
              deadline: tr?.deadline ?? p.deadline,
              firstSeen: p.firstSeen);
        }).toList(),
        0,
        0);
    for (final st in sched.tasks) {
      final tr = link[st.incidentId];
      totalCost += st.cost;
      // Without a matching truth (incident outside truth, e.g. manual):
      // competence judged on the proposed domain, no truth violation.
      final competent = tr != null
          ? team.domains.contains(tr.domain)
          : team.domains.contains(propById[st.incidentId]!.domain);
      if (!competent) {
        violations.add(
            'execution:${team.id}-incompetent(${tr?.domain ?? propById[st.incidentId]!.domain}) for ${st.incidentId}');
      }
      final done = tr != null &&
          tr.deadline >= 0 &&
          st.endMin <= tr.deadline;
      var r = 0;
      var reason = '';
      if (tr == null) {
        reason = 'outside ground truth: not scored';
      } else if (!(pure[st.incidentId] ?? false)) {
        reason = 'erroneous merge (impure group)';
      } else if (!competent) {
        reason = 'team not competent on true domain';
      } else if (!done) {
        reason = 'true deadline exceeded (${fmtMin(tr.deadline)})';
      } else {
        r = 1;
        reason = 'completed within constraints';
      }
      outcomes.add(TaskOutcome(
          incidentId: st.incidentId,
          truthId: tr?.id,
          pure: pure[st.incidentId] ?? false,
          result: r,
          reason: reason,
          startMin: st.startMin,
          endMin: st.endMin,
          cost: st.cost));
    }
  }
  if (totalCost > budgetUnits) {
    violations.add(
        'budget exceeded: ${totalCost.toStringAsFixed(1)} > $budgetUnits');
  }
  // Truth Q S1..S4.
  final weights = <String, double>{};
  for (final t in truth) {
    if (t.severity <= 4) weights[t.id] = t.weight;
  }
  final completedTruth = <String>{};
  final missed = <String>[];
  for (final t in truth) {
    if (t.severity >= 5) continue;
    final done = outcomes.any((o) => o.truthId == t.id && o.result == 1);
    if (done) {
      completedTruth.add(t.id);
    } else {
      missed.add(t.id);
    }
  }
  var q = qScore(weights, completedTruth);
  var feasible = violations.isEmpty;
  if (!feasible) q = 0.0; // global violation => Q=0
  // Structural infeasibility (dedicated oracle, true values).
  final structural = <String>[];
  for (final t in truth) {
    if (t.severity <= 4 && earliestEndTruth(t, teams) > t.deadline) {
      structural.add(t.id);
    }
  }
  return SimResult(
      outcomes: outcomes,
      missedTruth: missed,
      q: q,
      feasible: feasible,
      violations: violations,
      totalCost: totalCost,
      structurallyInfeasible: structural);
}

class RobustVariant {
  final double durScale;
  final double costScale;
  final double? q;
  final bool feasible;
  final List<String> violations;
  const RobustVariant(
      this.durScale, this.costScale, this.q, this.feasible, this.violations);
  Map<String, dynamic> toJson() => {
        'durScale': durScale,
        'costScale': costScale,
        'q': q,
        'feasible': feasible,
        'violations': violations,
      };
  static RobustVariant fromJson(Map<String, dynamic> j) => RobustVariant(
        (j['durScale'] as num).toDouble(),
        (j['costScale'] as num).toDouble(),
        (j['q'] as num?)?.toDouble(),
        j['feasible'] as bool? ?? false,
        (j['violations'] as List? ?? []).map((e) => '$e').toList(),
      );
}

/// Robustness: re-scoring with frozen plans (no re-optimization).
List<RobustVariant> robustness({
  required Plan plan,
  required List<Incident> proposed,
  required List<TruthIncident> truth,
  required List<Team> teams,
}) {
  final out = <RobustVariant>[];
  const scales = [
    [1.2, 1.0],
    [1.5, 1.0],
    [1.0, 1.2],
    [1.0, 1.5],
    [1.2, 1.2],
    [1.5, 1.5],
  ];
  for (final s in scales) {
    final scaled = truth
        .map((t) => TruthIncident(
            id: t.id,
            reportIds: t.reportIds,
            severity: t.severity,
            exposure: t.exposure,
            domain: t.domain,
            x: t.x,
            y: t.y,
            firstArrival: t.firstArrival,
            durationMult: t.durationMult * s[0]))
        .toList();
    // Costs: re-evaluated via a truth with scaled durations, then
    // costScale is applied to the total (linear rates).
    final r = simulate(
        plan: plan, proposed: proposed, truth: scaled, teams: teams);
    final scaledCost = r.totalCost * s[1];
    final viol = r.violations
        .where((v) => !v.startsWith('budget exceeded'))
        .toList();
    if (scaledCost > budgetUnits) {
      viol.add('budget exceeded (variant ×${s[1]})');
    }
    final feasible = viol.isEmpty;
    out.add(RobustVariant(
        s[0], s[1], feasible ? r.q : 0.0, feasible, viol));
  }
  return out;
}
