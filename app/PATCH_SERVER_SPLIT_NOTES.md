# Patch branchement serveur du découpage multi-problème — notes

Patch local, testé, poussé sur main (le parent pousse après sa propre
vérification). Base : copie complète de `patch-multi-split-app/app/`
(E4, garde-fou, unités/statuts/porte temps, multi-split), préservée
sans régression : les seuls fichiers qui diffèrent de la base sont
`lib/incidents.dart`, `bin/server.dart`, `test/test_all.dart` et
`web/index.html` (option de menu seulement).

## Problème résolu

Le patch multi-split fournissait `Subunit ORIGINE:FAMILLE`,
`expandToSubunits`, `groupSplitReports`, `splitGroupsByFamily` et
`aggregateSplitGroups`, mais le serveur ne les utilisait pas : il
appelait `aggregate()` classique sur les groupes, qui cherche
`E1:eclairage` dans la table des signalements (`byId[id]!`) et
échouerait. De plus, `_restore()` écrasait les groupes persistés par
le classique avant de les relire, donc un état découpé aurait été
perdu au redémarrage, et le simulateur n'aurait jamais lié un
incident découpé à sa vérité (`[E1:eclairage]` n'intersecte pas
`[E1]`).

## Fichiers et fonctions modifiés

### `lib/incidents.dart` — routage d'agrégation (nouveau)

- `groupUsesSplitIds(Group)` / `groupsUseSplitIds(List<Group>)` :
  vrai dès qu'un identifiant contient `:`.
- `aggregateMixedGroups(groups, byId)` : groupes découpés ->
  `aggregateSplitGroups()`, groupes pleins -> `aggregate()`, puis
  renumérotation I1.. dans l'ordre final (poids décroissant,
  échéance, identifiant provisoire). La renumérotation est
  indispensable : les deux agrégations numéroteraient sinon chacune
  depuis I1, et les tâches de plan (référencées par identifiant
  d'incident) deviendraient ambiguës. Sur des groupes sans `:`, le
  résultat est identique à `aggregate()` (prouvé par T27c).

### `bin/server.dart` — branchement

- `groupsUseSplitIds`, `aggregateForGroups` : un groupe découpé
  présent -> `aggregateMixedGroups()`, sinon `aggregate()` (chemin
  inchangé). C'est le seul point d'entrée d'agrégation des groupes
  serveur ; `aggregate()` ne subsiste que dans `regroup()` classique
  (groupes de `groupReports`, jamais de `:` par construction) et
  comme repli interne d'`aggregateForGroups`.
- `originIdsOfRefs`, `originMappedGroups`, `originMappedIncident` :
  projection `ORIGINE:FAMILLE -> ORIGINE` (identité sur un
  identifiant plein), sans doublon, ordre préservé.
- `regroupSplit(s)` : `groupSplitReports()` + `aggregateForGroups()`,
  `groupMethod = 'split'`, plan invalidé sauf `keepPlan`.
- `POST /api/group` :
  - `{"method": "split"}` : regroupement découpé global, journal
    `group.done` avec méthode, groupes et incidents.
  - `{"method": "classique"|"meta", "split": true}` : regroupement
    habituel, puis post-filtre `splitGroupsByFamily()`, puis
    `aggregateMixedGroups()` ; le nombre de groupes découpés est
    journalisé (`splitGroups`), les groupes découpés sont persistés
    tels quels (y compris dans `metaGroups` pour Meta).
  - Sans `split: true`, les chemins classique et Meta sont
    strictement inchangés. Le découpage est donc EXPLICITE, jamais
    silencieux. Message d'erreur mis à jour :
    `method = classique|meta|split`.
- `_restore()` : les groupes persistés sont capturés AVANT
  `regroup()` (qui les écrasait par le classique). Si
  `groupMethod == 'split'` et qu'un groupe persisté contient `:`,
  les groupes persistés sont restaurés et agrégés par
  `aggregateForGroups()` ; sinon, l'ancien chemin s'applique, avec
  `aggregateForGroups()` aussi pour la branche Meta (identique pour
  des groupes pleins).
- `metricsFor()` et `GET /api/compare-methods` (`side()` et
  désaccords) : agrégation mixte, et F1/désaccords calculés sur les
  origines. Limite assumée, écrite dans le code : une origine
  présente dans deux groupes découpés ne compte que pour le dernier
  dans les cartes de prédiction ; le F1 d'un état découpé est donc
  une approximation au niveau origine. La preuve première du
  découpage reste le nombre d'incidents (2, pas 1).
- `POST /api/compare` : configs classiques uniquement
  (`groupReports` ne produit jamais de `:`) ; routé par
  `aggregateForGroups()` pour uniformité, résultat identique.
- `POST /api/simulate` : les incidents proposés sont projetés vers
  leurs origines AVANT l'appariement à la vérité
  (`originMappedIncident`), champs de planification conservés.
  Sans cela, un incident découpé serait compté « hors vérité » et
  sa vérité manquée. Réponse enrichie de `splitOriginMapped`
  (booléen). Le simulateur lui-même (`lib/simulator.dart`) et la
  formule Q ne sont pas touchés.
- `POST /api/scenario/load`, `POST /api/reports`, `POST /api/inject`,
  `_check()` : inchangés (chemin classique). Charger un scénario
  réinitialise l'état découpé (groupes vidés, méthode classique) :
  c'est le comportement existant, pas une régression.
- `POST /api/plan` : inchangé ; il planifie les incidents tels
  qu'agrégés, donc 2 tâches pour un cas découpé, 1 pour l'ancien
  chemin. Le contrôle de péremption de `/api/simulate` (tâches dont
  l'identifiant d'incident n'existe plus) s'applique tel quel.

### `test/test_all.dart` — section 27 (nouvelle, 9 vérifications)

- T27a/a-bis/a-ter : agrégation mixte d'un cas découpé + un plein
  -> 3 incidents, identifiants uniques, éclairage propre
  (`E1:eclairage`).
- T27b : origine récupérable depuis chaque incident découpé.
- T27c : groupes pleins -> `aggregateMixedGroups()` identique à
  `aggregate()`.
- T27d/d-bis : aller-retour JSON d'un groupe plein et d'un groupe
  découpé (identifiants `:` conservés) ; état découpé restauré ->
  toujours 2 incidents.
- T27e : prédicat de détection split/plain.
- T27f : un incident découpé n'intersecte sa vérité que via son
  origine (principe de la projection utilisée par `/api/simulate`).
- Le routage serveur lui-même (`bin/server.dart`) n'est pas
  importable par ce harnais de tests lib : il est vérifié sur
  serveur réel via la procédure Windows ci-dessous, pas ici.

### `web/index.html` — interface

- Seul changement : une option `DÉCOUPÉ (multi-problème)` ajoutée
  au menu de méthode (`gMethod`). Le code `web/app.js` poste déjà
  la méthode du menu, donc aucune logique JS n'a changé. Les
  identifiants découpés s'affichent tels quels (`E1:eclairage`) ;
  l'origine est la partie avant `:`. Le `split: true` sur
  classique/meta reste API uniquement (pas de case dans l'interface).

## Chemin exact des données

Signalement (texte, catégorie, x/y en km, t en minutes)
-> familles DEV (`reportProblemFamilies`, lexique limité)
-> sous-signalements `ORIGINE:FAMILLE` (`expandToSubunits`,
  réversible par `originIdOfSubunit`)
-> groupes par famille (`groupSplitReports`, ou post-filtre
  `splitGroupsByFamily` sur un regroupement classique/Meta)
-> incidents (`aggregateMixedGroups`, via `aggregateForGroups`
  côté serveur ; jamais `aggregate()` classique sur des `:`)
-> plan (`POST /api/plan`, tâches par identifiant d'incident)
-> simulation (`POST /api/simulate`, appariement vérité sur les
  origines)
-> persistance : `stateDoc` (format 1, inchangé) + collections
  miroirs MongoDB reconstruites depuis ce document.

## Persistance : pas de migration, un point de rupture documenté

Le format 1 ne change pas : `Group.toJson/fromJson` conservent
déjà les identifiants `:` verbatim, `groupMethod` est déjà persisté
dans `stateDoc`, et `MongoStore.saveSnapshot()` reconstruit les
collections miroirs (dont `incidents`, avec leurs `reportIds`
découpés) depuis ce document, sans schéma propre aux identifiants.
Aucune migration n'est donc nécessaire pour les états format 1.

Point de rupture, assumé et non silencieux : un état découpé n'est
restauré comme découpé que si `groupMethod == 'split'` est persisté.
Si un état contenant des `:` est restauré sans cette méthode
(état édité à la main, ou session antérieure au branchement), le
redémarrage retombe sur le regroupement classique : les groupes
découpés sont perdus, mais l'état reste lisible et aucun plantage
n'a lieu. De même, les identifiants d'incidents sont positionnels
(I1.. par ordre poids/échéance) : un plan persisté reste valide
tant que le regroupement ne change pas, et le contrôle de
péremption de `/api/simulate` garde les plans périmés (limite
préexistante, identique pour le classique).

## Résultats réels (SDK Dart de `~/workspace/cityresolve/dart-sdk`)

- Base multi-split avant modification : 110 PASS, 0 FAIL ;
  exploratoire 9 OK / 1 limite (E7).
- Après ce patch : `dart test/test_all.dart` = **119 PASS, 0 FAIL**
  (110 + 9 vérifications T27) ; `dart test/test_exploratoire.dart` =
  **9 OK, 1 LIMITE (E7 seule)**, inchangé.
- `dart analyze` ciblé sur les fichiers modifiés
  (`lib/incidents.dart`, `bin/server.dart`, `test/test_all.dart`,
  `web/index.html`) : **No issues found**.
- `dart analyze lib test` complet : 7 problèmes, tous préexistants
  et identiques sur la base (paquet `mongo_dart` non résolu dans
  cette VM : `lib/mongo_store.dart`, `test/mongo_check.dart`) ;
  aucun ne concerne les fichiers modifiés ici.
- `dart bin/server.dart --check` : impossible dans cette VM, avant
  comme après ce patch (même erreur préexistante `Db` non défini,
  paquet `mongo_dart` absent) ; ce n'est pas une régression de ce
  patch. La preuve serveur réelle reste donc à faire sur Windows.

## Limites

- Le lexique de familles DEV reste limité (voirie-nid, éclairage,
  eau, électricité, inconnu) : une forme inconnue échappe au
  découpage, comme au drapeau avant lui.
- Deux volets d'un même signalement partagent les gravité/exposition
  déclarées de l'origine (limite déjà notée dans
  `aggregateSplitGroups`) : le découpage ne crée pas d'attributs
  propres à un volet.
- Le F1 et les désaccords d'un état découpé sont calculés au niveau
  origine (approximation documentée) ; ils ne prouvent pas le
  découpage au niveau sous-signalement.
- Les plans d'un état découpé n'ont pas été rejoués sur serveur
  réel ici (MongoDB indisponible dans cette VM) : persistance
  réelle, miroirs MongoDB et plan à 2 tâches restent à vérifier
  sur Windows.
- Aucun appel Meta n'a été fait pour ce patch ; aucune clé lue,
  copiée ou journalisée ; rien n'a été poussé ni envoyé.

## Procédure de vérification Windows (à ajouter au runbook)

Sans clé, sans mot de passe : la méthode `split` ne requiert pas
Meta (regroupement découpé classique par familles), donc cette
vérification ne nécessite pas `MODEL_API_KEY`.

1. `git pull origin main` (après push de ce patch), puis
   `dart test/test_all.dart` (attendu : 119 PASS) et
   `dart test/test_exploratoire.dart` (attendu : 9 OK / 1 limite E7).
2. Démarrer le serveur (`dart bin/server.dart --port 8080`,
   MongoDB local en principal, vérifier `/api/db`).
3. Créer le cas d'origine par l'API (ou charger un scénario
   contenant un signalement multi-problème) :
   `POST /api/reports` avec un texte contenant un nid-de-poule ET
   un réverbère éteint (ex. « nid poule rue lilas chaussee
   degradee reverbere eteint »), puis un second signalement
   nid-de-poule seul au même lieu.
4. `POST /api/group {"method": "split"}` : attendu, 2 incidents
   (voirie regroupant les deux volets voirie, éclairage seul),
   identifiants découpés visibles (`ORIGINE:voirie-nid`,
   `ORIGINE:eclairage`), méthode `split`.
5. `POST /api/plan` : attendu, 2 tâches (une par incident découpé),
   pas 1.
6. Redémarrer le serveur, puis `GET /api/state` et
   `GET /api/incidents` : attendu, méthode `split` conservée et
   mêmes 2 incidents (persistance des `:` vérifiée) ; vérifier
   aussi `/api/db` (compteurs incidents cohérents).
7. Contrôle de non-régression : `POST /api/group
   {"method": "classique"}` (sans `split`) sur les mêmes
   signalements : attendu, 1 incident (ancien chemin conservé) ;
   puis `POST /api/group {"method": "classique", "split": true}` :
   attendu, de nouveau 2 incidents.
8. Envoyer les sorties exactes (groupes, incidents, plan, état
   après redémarrage, compteurs `/api/db`), sans aucune clé.
   Si une étape échoue, envoyer le message d'erreur exact et
   l'étape concernée, sans relancer en boucle.
