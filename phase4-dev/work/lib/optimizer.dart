// Optimiseur COMMUN exact (moteur unique, indépendant du regroupement).
//
// Méthode : énumération complète des affectations (incident -> équipe/aucune)
// × ordres par équipe, simulation d'ordonnancement au plus tôt, sélection du
// meilleur plan. Exact pour n <= 9 incidents (garde anti-explosion).
// Départages : Q décroissant, coût croissant, durée croissante, id stable.
// Planification sur ESTIMATIONS accessibles ; la notation utilise la vérité.
import 'policy.dart';
import 'types.dart';

double manhattanKm(double x1, double y1, double x2, double y2) =>
    (x1 - x2).abs() + (y1 - y2).abs();

int estDurationMin(int? severity) => siteDurationsMin[severity] ?? 60;

/// Durée de tâche (site + trajet aller) et coût avec des paramètres donnés.
class SchedTask {
  final String incidentId;
  final double x, y;
  final int siteMin;
  final int deadline; // -1 si S5 (jamais planifié)
  final int firstSeen; // connaissance : démarrage impossible avant
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

/// Ordonnancement au plus tôt d'une équipe (départ dépôt chaque matin).
/// teamId utilisé pour les Task. Retourne tâches + coûts + complétés (fin <= échéance).
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
    // Premier créneau : connaissance (firstSeen) + horaires, lendemains inclus.
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
    if (!placed) break; // file abandonnée (reste non planifié)
  }
  return SchedResult(tasks, cost, firstStart < 0 ? 0 : lastEnd - firstStart,
      completed);
}

String fmtMin(int m) {
  final d = m ~/ 1440;
  final hh = ((m % 1440) ~/ 60).toString().padLeft(2, '0');
  final mm = (m % 60).toString().padLeft(2, '0');
  return 'J$d $hh:$mm';
}

/// Fin au plus tôt d'un incident seul (équipe compétente dédiée, estimations).
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
  if (items.isEmpty) return [[]]; // équipe sans tâche : un ordre vide
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

/// Optimise exactement. Lève si plus de 9 incidents S1..S4 (garde).
Plan optimizeExact({
  required List<Incident> incidents,
  required List<Team> teams,
}) {
  // S5 (gravité déclarée >= 5) : escalade humaine, jamais dispatché.
  final escalations = incidents
      .where((i) => i.severity != null && i.severity! >= 5)
      .map((i) => i.id)
      .toList();
  // Gravité inconnue/contradictoire : jamais de dispatch automatique.
  final blocked = <String, String>{};
  for (final i in incidents.where((i) => i.severity == null)) {
    blocked[i.id] = i.severityStatus == statusContradictoire
        ? 'gravités contradictoires déclarées ${i.severityValues} : vérification humaine requise avant dispatch'
        : 'gravité inconnue : vérification humaine requise avant dispatch';
  }
  final cands =
      incidents.where((i) => i.severity != null && i.severity! <= 4).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
  if (cands.length > 9) {
    throw StateError(
        'Optimiseur exact limité à 9 incidents (${cands.length} reçus).');
  }
  final weights = {for (final c in cands) c.id: c.weight};
  Plan? best;
  double bestQ = -1, bestCost = 1e18;
  var bestSpan = 1 << 30;
  var bestId = '';
  final k = teams.length;
  if (k < 1 || k > 3) {
    throw StateError('Optimiseur exact : 1 à 3 équipes ($k reçues).');
  }
  final n = cands.length;
  final base = k + 1;
  var total = 1;
  for (var i = 0; i < n; i++) {
    total *= base;
  }
  // Énumération des affectations en base k+1 (0=aucune, 1..k=équipes).
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
    // Compétences : rejet immédiat si équipe incompétente.
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
    // Produit cartésien des ordres par équipe.
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
        if (cost > budgetUnits) continue; // budget strict
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
  // Motifs de non-affectation + justifications.
  final assigned = best.tasks.map((t) => t.incidentId).toSet();
  final unassigned = <String, String>{};
  final just = <String, String>{};
  for (final t in best.tasks) {
    final inc = cands.firstWhere((c) => c.id == t.incidentId);
    just[t.incidentId] =
        '${t.teamId} ordre ${t.order}, ${fmtMin(t.startMin)}→${fmtMin(t.endMin)}, '
        'coût ${t.cost.toStringAsFixed(1)}, marge échéance ${inc.deadline - t.endMin} min.';
  }
  for (final inc in cands) {
    if (assigned.contains(inc.id)) continue;
    String reason;
    final competent =
        teams.any((tm) => tm.domains.contains(inc.domain));
    if (!competent) {
      reason = 'aucune équipe compétente (${inc.domain})';
    } else if (earliestEnd(inc, teams) > inc.deadline) {
      reason = 'échéance inaccessible même seule (${fmtMin(inc.deadline)})';
    } else {
      final cheapest = (estDurationMin(inc.severity) / 60.0) * siteRatePerHour;
      if (cheapest > budgetUnits) {
        reason = 'budget insuffisant même seule';
      } else {
        reason = 'non retenu par l\u2019optimiseur (Q maximal sans lui)';
      }
    }
    unassigned[inc.id] = reason;
    just[inc.id] = 'Non affecté : $reason.';
  }
  for (final e in escalations) {
    just[e] = 'S5 : escalade humaine immédiate, jamais dispatché.';
  }
  blocked.forEach((id, reason) {
    unassigned[id] = reason;
    just[id] = 'Non affecté : $reason.';
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
