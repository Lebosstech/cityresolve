# Patch découpage multi-problème — notes (local, poussé sur main)

Base : copie complète de `patch-units-status-app/app/` (version poussée
sur main incluant E4 + garde-fou + unités/statuts/porte temps), vérifiée
avant modification : 99 PASS, 0 FAIL, exploratoire 9 OK / 1 limite (E7).
Aucune régression de cette base n'est introduite par ce patch : les
fichiers modifiés sont seulement `lib/grouping.dart`,
`lib/incidents.dart` et `test/test_all.dart`.

## Problème résolu

Avant ce patch, un signalement à deux problèmes (E1 : nid-de-poule +
réverbère éteint) fusionné avec E2 (nid-de-poule seul) donnait un seul
groupe, donc un seul incident pour l'optimiseur, et l'éclairage
disparaissait du plan. Le drapeau multi-problème existant signalait
le cas sans le résoudre. Après ce patch, E1 est découpé en
`E1:voirie-nid` et `E1:eclairage`, regroupés séparément : l'optimiseur
voit deux tâches, et l'éclairage survit en incident propre et traçable.

## Ce qui a été ajouté

- `lib/grouping.dart` :
  - `Subunit` (identifiant `ORIGINE:FAMILLE`, origine, famille,
    signalement d'origine) et `originIdOfSubunit()` : le découpage est
    réversible en lecture en coupant au premier `:`.
  - `expandToSubunits()` : un sous-signalement par famille DEV
    explicite (`reportProblemFamilies`, lexique limité : voirie-nid,
    eclairage, eau, electricite). Aucune famille -> un seul
    sous-signalement `inconnu`, qui ne fusionne jamais.
  - `groupSplitReports()` : regroupement global par sous-signalements.
    Deux sous-signalements ne sont groupés que s'ils partagent la
    MÊME famille (hors `inconnu`) et passent les portes distance
    (250 m par défaut dans les tests) et temps (360 min). Aucun seuil
    Jaccard après découpage : la famille explicite est l'appariement
    sémantique. Le garde-fou contenu insuffisant s'applique aussi.
    Groupes marqués `method: 'split'`, incertains quand ils proviennent
    d'un signalement multi-problème, avec raison
    `découpage-multi-problème`.
  - `splitGroupsByFamily()` : post-filtre. Il découpe chaque groupe de
    signalements en sous-groupes par famille, SANS fusionner entre
    groupes d'origine. Un groupe sans signalement multi-problème est
    retourné inchangé. Retourne aussi le nombre de groupes découpés.
- `lib/incidents.dart` :
  - `familyDomain` : voirie-nid -> voirie, eclairage -> voirie (aligné
    sur `categoryDomain`, où la catégorie `eclairage` est déjà en
    voirie, pour rester assignable aux équipes existantes),
    eau -> reseaux, electricite -> reseaux, inconnu -> voirie. Aucune
    gravité n'est déduite de la famille.
  - `aggregateSplitGroups()` : agrégation pour groupes de
    sous-signalements. Chaque identifiant est résolu vers son
    signalement d'origine, et l'incident conserve les identifiants
    découpés dans `reportIds`. NE PAS appeler `aggregate()` sur ces
    groupes : il chercherait `E1:eclairage` dans la table des
    signalements et échouerait.
- `test/test_all.dart` : section 26, 11 vérifications T26a–h.

## Résultats réels

SDK Dart de `~/workspace/cityresolve/dart-sdk` :
- `dart test/test_all.dart` : **110 PASS, 0 FAIL** (99 de base + 11 T26).
- `dart test/test_exploratoire.dart` : **9 OK, 1 LIMITE (E7 seule)**,
  inchangé.
- `dart analyze` sur les 3 fichiers modifiés : **No issues found!**

## Périmètre exact et limites

- Lexique DEV limité : seules les familles explicites du lexique sont
  découpées. Une abréviation ou une formulation hors lexique échappe
  au découpage ; ce n'est pas une compréhension générale du français.
- Cas vagues : une mention vague sans famille explicite ne crée aucun
  sous-signalement, donc aucun découpage automatique. C'est le
  comportement sûr choisi, pas une détection de vague : la revue
  humaine reste nécessaire pour ces cas.
- Même problème deux fois : deux formulations de la même famille ne
  créent qu'un seul sous-signalement, donc aucun découpage à l'aveugle.
- Gravité/exposition : deux volets d'un même signalement partagent les
  valeurs déclarées de l'origine. Le découpage ne crée ni gravité ni
  exposition propres à un volet.
- Plans existants : un signalement découpé augmente le nombre
  d'incidents (1 -> 2 ou 3), donc le coût et le plan changent. Aucun
  Q n'a été calculé dans les tests DEV, faute d'équipes, de budget et
  d'échéances définis dans les scénarios de test : calculer un Q
  aurait exigé d'inventer ces entrées.
- Persistance : les groupes découpés portent des identifiants
  `ORIGINE:FAMILLE` dans `reportIds`. La persistance de ces
  identifiants par le serveur réel (MongoDB / JSON, lecture par
  `fromJson`, agrégation par le serveur) reste à vérifier sur serveur
  réel. Le serveur actuel appelle `aggregate()` sur les groupes
  classiques/Meta : brancher `aggregateSplitGroups()` dans le serveur
  est un travail d'intégration séparé, non fait ici.
- Le découpage ne remplace pas une vérification humaine pour les cas
  ambigus : les groupes découpés issus d'un signalement
  multi-problème sont marqués incertains.
