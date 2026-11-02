// Regroupement classique déterministe (DEV exploratoire).
//
// Règle : arête entre deux signalements ssi distance <= distMax ET
// écart temporel <= deltaTMax ET similarité Jaccard >= simMin.
// Groupes = composantes connexes (union-find), ordre déterministe.
// Confiance d'un groupe = similarité minimale de ses arêtes (0 si singleton).
import 'types.dart';

final RegExp _splitter = RegExp(r'[^a-zàâäéèêëîïôöùûüç0-9]+');

Set<String> tokens(String text) => text
    .toLowerCase()
    .split(_splitter)
    .where((w) => w.length > 2)
    .toSet();

/// Garde-fou contenu insuffisant (poussé sur main).
///
/// Un texte est insuffisant si, après passage en minuscules, il contient
/// moins de 2 caractères alphanumériques (lettres accentuées comprises).
/// Donc : texte vide, ponctuation/espaces seuls, ou un seul caractère.
/// Un texte de 2 caractères ou plus PASSE le garde-fou (limite assumée :
/// il peut rester vide de sens, ex. "ab") — le garde-fou ne vise que
/// l'absence de contenu, pas la qualité du contenu. Il ne résout ni le
/// lieu inconnu, ni le temps inconnu, ni les contradictions (voir
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
    'garde-fou-contenu-insuffisant : signalement non fusionnable, contenu insuffisant, à vérifier';

/// Filtre déterministe post-modèle (ou post-classique) : découpe tout
/// groupe contenant un signalement à contenu insuffisant en singletons,
/// chacun marqué incertain avec la raison garde-fou explicite. Les groupes
/// sans contenu insuffisant sont retournés inchangés. Le comptage
/// `cancelledMerges` = nombre de groupes multi-signalements découpés :
/// c'est la trace journalisable de l'annulation, même si le modèle avait
/// proposé la fusion avec une incertitude faible.
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
            ? 'Garde-fou : fusion proposée annulée (contenu insuffisant)'
                '${g.justification == null ? '' : ' ; proposition d’origine : ${g.justification}'}'
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

/// --- Patch unités / statuts / porte temps (poussé sur main) ---
///
/// Choix de représentation, sans casser les tests ni la persistance :
/// le type `Group` n'a pas de champ statut dédié, donc les statuts
/// sont portés par `uncertain = true` + une raison explicite dans
/// `uncertaintyReasons` (préfixe `statut-contradictoire` ou
/// `drapeau-multi-probleme`). Aucun champ n'est ajouté à `Group`,
/// donc `toJson` / `fromJson` et le serveur sont inchangés. Les statuts
/// ne découpent JAMAIS un groupe : ils le signalent. Seule la porte
/// temps (post-modèle, comme le garde-fou) découpe, et chaque découpe
/// est comptée dans `splitGroups` et tracée par une raison
/// `porte-temps-meta` sur chaque composante issue du découpage.

/// Familles de problèmes DEV (lexique limité, vocabulaire des
/// scénarios trompeurs + cas étendus). Ne prétend pas couvrir le
/// français général : une forme abrégée inconnue du lexique (ex.
/// « ndp » pour la voirie est couverte, mais une abréviation inédite
/// ne le serait pas) échappe au drapeau — limite documentée.
const Map<String, Set<String>> _problemFamilies = {
  'voirie-nid': {
    'nid', 'poule', 'ndp', 'trou', 'chaussee', 'chaus',
    'degradee', 'degrade', 'abimee', 'abim'
  },
  'eclairage': {'reverbere', 'lampadaire', 'eclairage', 'eteint', 'defaillant'},
  'eau': {'fuite', 'eau', 'inonde', 'canalisation', 'ecoulement'},
  'electricite': {'coupure', 'courant', 'electrique', 'electricite', 'panne'},
};

const Set<String> _resolvedTokens = {
  'resolue', 'resolu', 'sec', 'seche', 'termines', 'termine',
  'repares', 'repare'
};
const Set<String> _ongoingTokens = {'inonde', 'inondee', 'coule', 'coulee'};

/// Familles touchées par le texte d'un signalement.
Set<String> reportProblemFamilies(Report r) {
  final toks = tokens(r.text);
  return {
    for (final e in _problemFamilies.entries)
      if (toks.intersection(e.value).isNotEmpty) e.key
  };
}

/// Un signalement liste-t-il au moins deux problèmes distincts ?
bool hasMultiProblem(Report r) => reportProblemFamilies(r).length >= 2;

/// Raison de contradiction d'état (résolu contre en cours), ou null.
String? stateContradictionReason(List<Report> members) {
  final toks = <String>{};
  for (final r in members) {
    toks.addAll(tokens(r.text));
  }
  if (toks.intersection(_resolvedTokens).isNotEmpty &&
      toks.intersection(_ongoingTokens).isNotEmpty) {
    return "contradiction d'état : marques résolu et en cours dans le même groupe";
  }
  return null;
}

/// Raisons de contradiction d'un groupe : état + écarts de
/// gravité/exposition déclarées >= 2. Les valeurs sont conservées,
/// jamais moyennées.
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
    'gravité': members.map((r) => r.severityHint).whereType<int>(),
    'exposition': members.map((r) => r.exposureHint).whereType<int>(),
  }.entries) {
    final vals = entry.value.toList();
    if (vals.isNotEmpty &&
        vals.reduce((a, b) => a > b ? a : b) -
                vals.reduce((a, b) => a < b ? a : b) >=
            2) {
      reasons.add(
          'contradiction de ${entry.key} : valeurs déclarées $vals, écart >= 2, conservées sans moyenne');
    }
  }
  return reasons;
}

/// Applique les statuts aux groupes, sans changer leurs reportIds.
/// Retourne aussi le nombre de groupes contradictoires et le nombre
/// de groupes multi-problème (traces comptables, comme
/// `cancelledMerges` pour le garde-fou).
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
        final labelled = 'statut-contradictoire : $r';
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
          'drapeau-multi-probleme : signalement(s) ${multiIds.join(',')} listant >= 2 problèmes distincts ; groupe non comptable comme un seul incident propre');
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

/// Porte temps post-modèle (déterministe, comptée).
///
/// Seuil local : 360 min (6 h), aligné sur la porte classique
/// (deltaTMaxH = 6 h) pour les incidents ponctuels. Exception
/// événements étendus : si TOUS les signalements du groupe ont une
/// catégorie dans `extendedCategories` (coupure de réseau, panne
/// réseau — un événement réseau peut persister plusieurs jours),
/// seuil 10080 min (7 jours). Catégorie mixte ou ponctuelle -> seuil
/// local (choix conservateur : on découpe). La porte ne doit pas
/// casser les événements étendus : c'est pourquoi l'exception est
/// explicite et testée (T25c), et pourquoi un groupe mixte retombe
/// sur le seuil local plutôt que sur le seuil étendu.
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
    return (gateMin: extendedTimeGateMin, kind: 'étendu');
  }
  return (gateMin: localTimeGateMin, kind: 'local');
}

/// Découpe post-modèle les groupes violant la porte temps.
/// Retourne les groupes découpés + le nombre de groupes découpés.
/// Chaque composante issue d'un découpage porte une raison
/// `porte-temps-meta` ; les groupes non découpés sont inchangés.
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
          'porte-temps-meta : fusion proposée découpée, délai > ${gate.gateMin} min (seuil ${gate.kind})');
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

/// --- Patch découpage multi-problème (local, poussé sur main) ---
///
/// Un signalement peut décrire plusieurs problèmes distincts. Le
/// drapeau multi-problème existant signale ce cas, il ne le résout
/// pas : un groupe [E1, E2] reste un seul incident pour l'optimiseur,
/// et le problème secondaire (éclairage) disparaît du plan.
///
/// Le découpage résout ce cas au niveau du regroupement, sans
/// inventer de problème : chaque signalement est expansé en
/// sous-signalements, un par famille DEV explicite
/// (`reportProblemFamilies`, lexique limité documenté, pas de
/// prétention au français général). Un sous-signalement s'identifie
/// `ORIGINE:FAMILLE` (ex. `E1:eclairage`) : l'origine est
/// récupérable en lecture en coupant au premier `:` (voir
/// `originIdOfSubunit`), donc le découpage est réversible.
///
/// Règles :
/// - deux sous-signalements ne sont groupés que s'ils partagent la
///   MÊME famille (famille `inconnu` exclue : jamais de fusion) et
///   passent les portes distance et temps du regroupement classique.
///   Aucun seuil Jaccard n'est appliqué après découpage : la famille
///   explicite est l'appariement sémantique. Limite assumée : cette
///   règle est plus permissive que le classique ; elle ne vaut que
///   parce que la famille est explicite.
/// - un contenu insuffisant (garde-fou) ne fusionne jamais.
/// - un signalement à une seule famille n'est pas découpé ; une
///   mention vague sans famille explicite ne crée aucun
///   sous-signalement, donc aucun découpage automatique.
/// - `aggregate()` classique NE DOIT PAS être appelé sur des groupes
///   de sous-signalements : il chercherait `E1:eclairage` dans la
///   table des signalements et échouerait. Utiliser
///   `aggregateSplitGroups()` (lib/incidents.dart), qui agrège par
///   sous-signalement et conserve les identifiants découpés dans
///   l'incident. La persistance des sous-signalements par le serveur
///   réel (MongoDB / JSON) reste à vérifier sur serveur réel.
/// - les groupes découpés portent `method: 'split'` et une raison
///   `découpage-multi-problème` quand ils proviennent d'un
///   signalement multi-problème ; ils sont marqués incertains, car
///   le découpage repose sur un lexique DEV, pas sur une vérification
///   terrain.
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

/// Origine d'un identifiant de sous-signalement (réversibilité).
String originIdOfSubunit(String subunitId) {
  final i = subunitId.indexOf(':');
  return i < 0 ? subunitId : subunitId.substring(0, i);
}

/// Expansion déterministe : un sous-signalement par famille DEV.
/// Ordre des familles = ordre du lexique (voirie-nid, eclairage, eau,
/// electricite). Aucune famille -> un seul sous-signalement `inconnu`,
/// qui ne fusionnera jamais.
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

/// Regroupement par sous-signalements (global, pas post-filtre).
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
          'découpage-multi-problème : groupe issu d’un signalement listant >= 2 problèmes distincts ; vérifier le découpage (lexique DEV)');
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
          ? 'Découpage multi-problème par famille DEV ; origine(s) : ${origins.join(',')}'
          : null,
    ));
  }
  return groups;
}

/// Post-filtre : découpe chaque groupe de signalements en
/// sous-groupes par famille, SANS fusionner entre groupes d'origine.
/// Un groupe sans signalement multi-problème est retourné inchangé
/// (identifiants de signalements, pas de sous-signalements).
/// Retourne les groupes découpés + le nombre de groupes découpés.
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
          'découpage-multi-problème : groupe ${g.id} découpé par famille DEV (${entry.key}) ; origine(s) : ${members.map((r) => r.id).join(',')}'
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
  // Deux textes sans jeton : aucune évidence de similarité (pas 1,0).
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

// Racine carrée de Newton (évite dart:math pour un module pur).
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

/// Regroupe les signalements. Paramètres en unités SI du prototype :
/// distMaxM (mètres), deltaTMaxH (heures), simMin (Jaccard 0..1).
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
      // Garde-fou : un contenu insuffisant ne fusionne JAMAIS, quelle que
      // soit la distance, le temps ou la similarité (deux textes vides
      // ont un Jaccard de 0,0, mais la règle est explicite et ne dépend
      // d'aucun seuil).
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
  // Ordre déterministe : tri par plus petit id de signalement.
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
    // Incertitude du regroupement : signalée, jamais masquée.
    final reasons = <String>[];
    if (comp.length == 1 &&
        hasInsufficientContent(reports[comp.first].text)) {
      reasons.add(guardrailReason);
    }
    if (comp.length > 1) {
      if (conf <= simMin + 0.10) {
        reasons.add(
            'similarité minimale ${conf.toStringAsFixed(2)} proche du seuil $simMin');
      }
      // Chaînage transitif : paire interne sans arête directe.
      for (var x = 0; x < comp.length && reasons.length < 4; x++) {
        for (var y = x + 1; y < comp.length; y++) {
          final key = comp[x] < comp[y]
              ? '${comp[x]}|${comp[y]}'
              : '${comp[y]}|${comp[x]}';
          if (!edgeSim.containsKey(key)) {
            reasons.add(
                'chaînage transitif : ${reports[comp[x]].id}-${reports[comp[y]].id} sans arête directe');
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
        reasons.add('gravités déclarées contradictoires dans le groupe');
      }
      // Patch unités/statuts : le classique porte aussi les statuts
      // (raisons seulement, regroupement inchangé).
      final members = comp.map((i) => reports[i]).toList();
      final state = stateContradictionReason(members);
      if (state != null) reasons.add('statut-contradictoire : $state');
      final multiIds = members
          .where((r) => hasMultiProblem(r))
          .map((r) => r.id)
          .toList();
      if (multiIds.isNotEmpty) {
        reasons.add(
            'drapeau-multi-probleme : signalement(s) ${multiIds.join(',')} listant >= 2 problèmes distincts ; groupe non comptable comme un seul incident propre');
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

/// Paires NON regroupées mais ambiguës (presque-fusions / séparations
/// douteuses). Permet de signaler une séparation incertaine au lieu de
/// l'imposer en silence (cas E2 : même lieu/instant, vocabulaire disjoint).
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
            'proximité spatio-temporelle mais vocabulaire insuffisant (Jaccard ${s.toStringAsFixed(2)} < $simMin) : séparation incertaine';
      } else if (s >= simMin && dKm > distMaxKm && dKm <= distMaxKm * 2) {
        reason =
            'texte similaire mais distance ${(dKm * 1000).round()} m au-delà du seuil ${distMaxM.round()} m : séparation incertaine';
      } else if (s >= simMin && dt <= deltaTMaxMin && dKm > distMaxKm * 2) {
        // E4 (poussé sur main) : même texte, très loin. Ne pas
        // fusionner de force (deux incidents réels peuvent partager un
        // texte), mais ne pas séparer en silence : signaler le doublon
        // distant à vérifier par un humain.
        reason =
            'texte similaire (Jaccard ${s.toStringAsFixed(2)}) mais distance ${(dKm * 1000).round()} m, bien au-delà du seuil ${distMaxM.round()} m : séparation incertaine, doublon distant à vérifier, non fusionné';
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
