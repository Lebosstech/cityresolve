// Oracle décisionnel (C6 §5) : nécessité d'une révision avec les seules
// informations disponibles (observables + estimations). La vérité cachée
// ne sert qu'à noter, jamais à juger. Déterministe.
// Appariement inter-phases par recouvrement de signalements (ids stables
// non requis) ; équipes retirées détectées.
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

/// Appariement ancien -> nouvel incident (recouvrement maximal, >0 requis).
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

/// Juge si l'ancien plan doit changer face aux incidents mis à jour.
Necessity judgeRevision({
  required Plan oldPlan,
  required List<Incident> oldIncidents,
  required List<Incident> updated,
  required List<Team> teams,
  Set<String> newS5 = const {},
}) {
  if (newS5.isNotEmpty) {
    return const Necessity('N3-S5', true,
        'S5 révélé : escalade humaine exigée, pas de réaffectation.');
  }
  final oldById = {for (final i in oldIncidents) i.id: i};
  final newById = {for (final i in updated) i.id: i};
  final teamIds = teams.map((t) => t.id).toSet();
  for (final t in oldPlan.tasks) {
    if (!teamIds.contains(t.teamId)) {
      return Necessity('N1', true,
          'Équipe ${t.teamId} indisponible : réaffectation requise.');
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
          'Regroupement modifié : ${t.incidentId} a disparu.');
    }
    mapping[t.incidentId] = m;
  }
  // Réévalue l'ancien plan (mappé) avec les estimations mises à jour,
  // ordres conservés.
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
          'Ancien plan infaisable ; alternative réalisable (Q=${fresh.q.toStringAsFixed(1)}).');
    }
    return const Necessity('N1b', false,
        'Ancien plan infaisable sans alternative : signaler, ne pas réaffecter.');
  }
  if (fresh != null && fresh.q - oldQ >= revisionThresholdQ - 1e-9) {
    return Necessity('N2', true,
        'Gain +${(fresh.q - oldQ).toStringAsFixed(1)} points Q (seuil $revisionThresholdQ).');
  }
  final g = fresh == null ? 0.0 : fresh.q - oldQ;
  return Necessity('U', false,
      'Ancien plan faisable, gain +${g.toStringAsFixed(1)} < $revisionThresholdQ : stabilité.');
}

class PlanDiff {
  final bool material;
  final String detail;
  const PlanDiff(this.material, this.detail);
}

/// Changement matériel entre deux plans (appariements par recouvrement,
/// règle 30 min cosmétique).
PlanDiff comparePlans(
  Plan oldPlan,
  Plan newPlan, {
  required Map<String, Set<String>> oldReports,
  required Map<String, Set<String>> newReports,
}) {
  // Apparie chaque tâche ancienne (recouvrement maximal).
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
      return const PlanDiff(true, 'Sélection d\u2019incidents modifiée.');
    }
    match[t.incidentId] = best!;
  }
  // Nouvelles tâches sans antériorité ?
  final matchedNew = match.values.toSet();
  for (final t in newPlan.tasks) {
    if (!matchedNew.contains(t.incidentId)) {
      return const PlanDiff(true, 'Sélection d\u2019incidents modifiée.');
    }
  }
  final n = {for (final t in newPlan.tasks) t.incidentId: t};
  for (final t in oldPlan.tasks) {
    final u = n[match[t.incidentId]!]!;
    if (t.teamId != u.teamId) {
      return PlanDiff(true, 'Réaffectation de ${t.incidentId}.');
    }
    if (t.order != u.order) {
      return PlanDiff(true, 'Ordre modifié pour ${t.incidentId}.');
    }
    if ((t.startMin - u.startMin).abs() >= cosmeticShiftMin ||
        (t.endMin - u.endMin).abs() >= cosmeticShiftMin) {
      return PlanDiff(true, 'Horaires modifiés ≥ $cosmeticShiftMin min.');
    }
  }
  return const PlanDiff(false, 'Inchangé ou écarts cosmétiques < 30 min.');
}
