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

/// Domaine métier d'une famille DEV (découpage). Aligné sur
/// `categoryDomain` : l'éclairage y est rattaché à la voirie, comme
/// la catégorie `eclairage`, pour rester assignable aux équipes
/// existantes (equipe-1 : voirie, espaces-verts ; equipe-2 : voirie,
/// reseaux). Aucune gravité n'est déduite de la famille.
const Map<String, String> familyDomain = {
  'voirie-nid': 'voirie',
  'eclairage': 'voirie',
  'eau': 'reseaux',
  'electricite': 'reseaux',
  'inconnu': 'voirie',
};

/// Agrégation pour groupes de SOUS-signalements (voir
/// `groupSplitReports` / `splitGroupsByFamily`).
/// NE PAS appeler `aggregate()` sur ces groupes : il chercherait
/// `E1:eclairage` dans la table des signalements et échouerait.
/// Ici, chaque identifiant est résolu vers son signalement d'origine
/// (partie avant `:`), et l'incident conserve les identifiants
/// découpés dans `reportIds` : l'origine est donc traçable, et
/// l'optimiseur voit autant de tâches que de groupes découpés.
/// Limite : deux volets d'un même signalement partagent les mêmes
/// gravité/exposition déclarées (celles de l'origine) ; le découpage
/// ne crée ni gravité ni exposition propres à un volet.
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

/// --- Branchement serveur du découpage multi-problème ---
///
/// Le serveur ne doit JAMAIS appeler `aggregate()` sur un groupe dont
/// un identifiant contient `:` (sous-signalement `ORIGINE:FAMILLE`) :
/// `aggregate()` chercherait `E1:eclairage` dans la table des
/// signalements et échouerait (accès `byId[id]!` sur une clé absente).
/// `aggregateMixedGroups()` route chaque groupe vers la bonne
/// agrégation : groupes découpés -> `aggregateSplitGroups()`, groupes
/// pleins -> `aggregate()`, puis renumérote les incidents I1.. dans
/// l'ordre final (poids décroissant, échéance, identifiant provisoire),
/// car les deux agrégations numéroteraient sinon chacune depuis I1
/// et les tâches de plan (référencées par identifiant d'incident)
/// deviendraient ambiguës. Sur des groupes sans `:` le résultat est
/// identique à `aggregate()` (prouvé par le test T27d).
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
