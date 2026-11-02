// Q Phase 4 DEV, via les bibliotheques Dart reelles uniquement.
// Usage : dart q.dart <scenarios.json> <meta_groups.json> <sortie.json>
// - CLASSIQUE : groupes recalcules par groupReports (Dart original).
// - META : groupes lus dans meta_groups.json, meme agregation,
//   meme optimiseur exact, meme simulateur.
// - Q officiel = Q simule du simulateur, avec la regle documentee
//   violation globale => Q=0. AUCUNE formule n'est modifiee ici.
//   Le Q planifie de l'optimiseur est rapporte separement, a titre
//   descriptif, jamais comme substitut du Q simule.
// - E1 : verite non specifiee => Q = null, motif explicite.
import 'dart:convert';
import 'dart:io';
import 'lib/grouping.dart';
import 'lib/incidents.dart';
import 'lib/optimizer.dart';
import 'lib/simulator.dart';
import 'lib/types.dart';

TruthIncident truthFromJson(Map<String, dynamic> j) => TruthIncident(
      id: j['id'] as String,
      reportIds: (j['reportIds'] as List).map((e) => '$e').toSet(),
      severity: (j['severity'] as num).toInt(),
      exposure: (j['exposure'] as num).toInt(),
      domain: j['domain'] as String,
      x: (j['x'] as num).toDouble(),
      y: (j['y'] as num).toDouble(),
      firstArrival: (j['firstArrival'] as num).toInt(),
      durationMult: (j['durationMult'] as num).toDouble(),
    );

void main(List<String> args) {
  final scenariosDoc =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final metaDoc =
      jsonDecode(File(args[1]).readAsStringSync()) as Map<String, dynamic>;
  final teams = defaultTeams();
  final out = <String, dynamic>{};
  for (final sc in (scenariosDoc['scenarios'] as List)) {
    final id = sc['id'] as String;
    final reports = (sc['reports'] as List)
        .map((e) => Report.fromJson(e as Map<String, dynamic>))
        .toList();
    final byId = {for (final r in reports) r.id: r};
    final truthJson = sc['truth'] as List?;
    final truth = truthJson == null
        ? null
        : truthJson
            .map((e) => truthFromJson(e as Map<String, dynamic>))
            .toList();
    final methods = <String, dynamic>{};
    final classicGroups = groupReports(reports,
        distMaxM: 250, deltaTMaxH: 6, simMin: 0.75);
    final metaRaw = metaDoc[id];
    final metaGroups = metaRaw == null
        ? null
        : (metaRaw as List).map((e) {
            final g = e as Map<String, dynamic>;
            final ids = (g['reportIds'] as List).map((x) => '$x').toList();
            return Group(
              id: g['id'] as String,
              reportIds: ids,
              confidence: (g['confidence'] as num).toDouble(),
              singleton: ids.length == 1,
              method: 'meta',
              uncertain: (g['uncertain'] as bool?) ?? false,
              uncertaintyReasons: (g['uncertaintyReasons'] as List? ?? [])
                  .map((x) => '$x')
                  .toList(),
              justification: g['justification'] as String?,
            );
          }).toList();
    for (final entry in [
      ('classique', classicGroups),
      ('meta', metaGroups),
    ]) {
      final method = entry.$1;
      final groups = entry.$2;
      if (groups == null) {
        methods[method] = {'error': 'groupes META absents (appel en echec)'};
        continue;
      }
      if (truth == null) {
        methods[method] = {
          'error': 'verite non specifiee pour ce scenario : Q non calculable',
          'groups': groups.map((g) => g.reportIds).toList(),
        };
        continue;
      }
      // Validation de couverture : chaque signalement exactement une fois.
      final seen = <String>{};
      var coverOk = true;
      for (final g in groups) {
        for (final rid in g.reportIds) {
          if (!seen.add(rid) || !byId.containsKey(rid)) coverOk = false;
        }
      }
      if (!coverOk || seen.length != reports.length) {
        methods[method] = {
          'error': 'couverture invalide des groupes META',
          'groups': groups.map((g) => g.reportIds).toList(),
        };
        continue;
      }
      try {
        final incs = aggregate(groups, byId);
        final plan = optimizeExact(incidents: incs, teams: teams);
        final sim = simulate(
            plan: plan, proposed: incs, truth: truth, teams: teams);
        methods[method] = {
          'groups': groups.map((g) => g.reportIds).toList(),
          'incidents': incs.map((i) => i.toJson()).toList(),
          'plan_q': plan.q,
          'plan_cost': plan.totalCost,
          'plan_tasks': plan.tasks.map((t) => t.toJson()).toList(),
          'plan_unassigned': plan.unassigned,
          'plan_escalations': plan.escalations,
          'sim_q': sim.q,
          'sim_cost': sim.totalCost,
          'sim_feasible': sim.feasible,
          'sim_violations': sim.violations,
          'sim_missed_truth': sim.missedTruth,
          'sim_outcomes': sim.outcomes.map((o) => o.toJson()).toList(),
        };
      } catch (e) {
        methods[method] = {
          'error': '$e',
          'groups': groups.map((g) => g.reportIds).toList(),
        };
      }
    }
    out[id] = methods;
  }
  File(args[2]).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(out));
  print('Q ecrit dans ${args[2]}');
}
