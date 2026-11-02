// Agrégation groupes -> incidents proposés (exploratoire).
//
// Gravité et exposition : JAMAIS déduites de la catégorie ni fabriquées.
// - aucune valeur déclarée        -> valeur null, statut inconnue ;
// - une seule valeur distincte    -> statut declaree ;
// - valeurs proches (écart <= 1)  -> max, statut estimee ;
// - valeurs incompatibles (>= 2)  -> valeur null, statut contradictoire,
//   valeurs déclarées conservées dans severityValues/exposureValues.
// Domaine : domaine majoritaire des catégories DÉCLARÉES ; égalité entre
// deux domaines -> domainConflict signalé (domaine du premier conservé).
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
  // Priorité : poids de décision décroissant, puis échéance, puis id.
  out.sort((a, b) {
    final dw = b.weight.compareTo(a.weight);
    if (dw != 0) return dw;
    final dd = a.deadline.compareTo(b.deadline);
    if (dd != 0) return dd;
    return a.id.compareTo(b.id);
  });
  return out;
}
