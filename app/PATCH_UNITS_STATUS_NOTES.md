# Patch unités / statuts / porte temps — notes (poussé sur main)

Dossier : `patch-units-status-app/app/` = copie complète de l'application
du miroir du dépôt (`repo-mirror/app`, lecture seule, intact — hash
`grouping.dart` du miroir vérifié inchangé après travaux :
`7e360ed506c4a037af836756b9d8e103fba2bb60bbf356f43271895d8afb6d74`),
superposée avec la version fusionnée E4 + garde-fou
(`patch-e4-guardrail-merged/app/`, déjà poussée sur main selon la
mission — ici reprise comme base, sans la modifier), puis modifiée
comme ci-dessous. **Rien n'a été poussé sur GitHub, rien n'a été envoyé
à ChatGPT, aucune clé n'a été lue ni copiée.** Les seuls motifs
`Bearer` dans ce dossier sont les jetons factices préexistants du code
de test d'origine (ex. `wrong-key`), pas des secrets.
Aucune formule Q, aucun seuil existant, aucun protocole n'a été touché.
Le classique garde ses seuils (250 m, 6 h, Jaccard 0,75) ; la porte
temps Meta réutilise 360 min pour le local, sans modifier la porte
classique.

## 1. Base préservée, sans régression

Vérifié avant modification, dans ce dossier même :

- `dart test/test_all.dart` : **85 PASS, 0 FAIL** (base fusionnée).
- `dart test/test_exploratoire.dart` : **9 OK, 1 LIMITE (E7 seule)**.
- `app/lib/grouping.dart` superposé : hash identique à la version
  fusionnée (`07377ca88d948e43658f2b6cadd3b7e3528bac26f0f7f2959f1f5504e841c5ef`).
- `app/lib/server_lock.dart` et `app/bin/server.dart` : identiques
  byte pour byte à la version fusionnée après travaux (vérifié par
  `diff`) — le verrou mono-instance E4 n'est pas touché.

## 2. Périmètre exact : trois fichiers modifiés seulement

- `app/lib/grouping.dart` : mécanismes déterministes (section 3).
- `app/lib/meta_connector.dart` : listing avec unités + prompt unités +
  chaîne de filtres post-modèle (section 4).
- `app/test/test_all.dart` : section 25, tests T25a–h (section 5).
- Non modifiés : `app/bin/server.dart`, `app/lib/server_lock.dart`,
  `app/test/test_exploratoire.dart`, tous les autres fichiers de
  l'application. Le serveur n'a pas eu besoin de modification : il
  utilise `groupReports` pour le classique et
  `proposeMatchingWithMeta` pour Meta, donc les deux chemins sont
  couverts.

## 3. Mécanismes déterministes (`lib/grouping.dart`)

### 3.1 Choix de représentation : pas de nouveau champ dans `Group`

Le type `Group` n'a pas de champ statut dédié, et en ajouter un
casserait `toJson` / `fromJson` et la persistance serveur. Les statuts
sont donc portés par `uncertain = true` + une raison explicite dans
`uncertaintyReasons` (préfixe `statut-contradictoire` ou
`drapeau-multi-probleme`). C'est un statut exploitable par lecture des
raisons, pas un champ typé : si le serveur veut un jour un champ
dédié, il faudra une migration de persistance, hors de ce patch.

### 3.2 Statut groupe contradictoire

`groupContradictionReasons(reports, reportIds)` : un groupe fusionné
est marqué si ses signalements portent des états opposés (lexique DEV
: résolu/sec/terminé contre inondé/coule) OU si l'écart des gravités
ou expositions déclarées est >= 2. Les valeurs sont conservées, jamais
moyennées. `applyGroupStatuses` applique ce statut (et le drapeau
ci-dessous) sans changer les `reportIds`, et retourne les compteurs
`contradictoryGroups` / `multiProblemGroups` (traces comptables, comme
`cancelledMerges` pour le garde-fou). Le classique porte aussi ces
raisons dans `groupReports` (regroupement inchangé, raisons ajoutées).

### 3.3 Drapeau multi-problème

`hasMultiProblem(report)` : le texte touche >= 2 familles de problèmes
DEV (voirie-nid, éclairage, eau, électricité — lexique limité
documenté dans le code). Un groupe contenant un tel signalement porte
la raison `drapeau-multi-probleme` citant le signalement, et ne peut
pas être compté comme un seul incident propre sans ce drapeau. Le
drapeau ne découpe pas : découper un signalement en deux incidents
exigerait une règle de découpage qui n'existe pas encore.

### 3.4 Porte temps Meta (post-modèle, comptée)

`applyMetaTimeGate(reports, groups)` : découpe les groupes proposés
dont une paire dépasse le seuil. Seuil local : 360 min (6 h), aligné
sur la porte classique, pour les incidents ponctuels. Seuil étendu :
10080 min (7 jours) si TOUS les signalements du groupe ont une
catégorie dans {coupure-electrique, panne-reseau}. Catégorie mixte
-> seuil local (choix conservateur). Chaque découpe est comptée dans
`splitGroups` et tracée par une raison `porte-temps-meta` sur chaque
composante issue du découpage.

**Limite explicite sur les événements étendus :** la porte ne doit
pas casser les événements étendus, et l'exception ci-dessus est la
protection prévue — mais elle repose sur la catégorie déclarée et sur
un seuil de 7 jours choisi par convention, non mesuré sur des pannes
réelles. Une coupure mal catégorisée, ou plus longue que 7 jours,
serait découpée à tort. La porte est un filet de sécurité, pas une
preuve d'identité d'incident.

## 4. Côté serveur Meta (`lib/meta_connector.dart`)

- `metaListingWithUnits(reports)` : en-tête d'unités + lignes
  `x=2,0 km, y=2,0 km, t=500 min` + paires calculées
  (`distance 0,00 km, délai 4320 min = 3,0 jours`). C'est le listing
  utilisé par `proposeMatchingWithMeta`, à la place de l'ancien
  listing sans unités (`x=2.0 y=2.0 t=500`).
- Prompt système du rapprochement : règle d'unités explicite (ne
  jamais écrire qu'une unité est absente ; 4320 min = 3 jours, pas un
  délai court ; un délai de plusieurs jours ne prouve pas l'identité
  pour un incident ponctuel).
- Chaîne post-modèle, dans cet ordre, dans `proposeMatchingWithMeta` :
  1. `applyContentGuardrail` (garde-fou, inchangé),
  2. `applyMetaTimeGate` (porte temps),
  3. `applyGroupStatuses` (statuts, sans découpe).
  Les compteurs sont vérifiables groupe par groupe via les raisons
  (`garde-fou-contenu-insuffisant`, `porte-temps-meta`,
  `statut-contradictoire`, `drapeau-multi-probleme`).
- Non couvert par ce patch : `extractStructuredWithMeta` (l'extraction
  ne porte ni coordonnées ni temps, donc pas de listing à corriger
  là) ; aucune image, SAM 3.1 non branché.

## 5. Tests exécutés, résultats réels

Commandes (SDK Dart de `~/workspace/cityresolve/dart-sdk`) :

```text
cd ~/workspace/cityresolve/patch-units-status-app/app
~/workspace/cityresolve/dart-sdk/bin/dart test/test_all.dart
~/workspace/cityresolve/dart-sdk/bin/dart test/test_exploratoire.dart
~/workspace/cityresolve/dart-sdk/bin/dart analyze lib/grouping.dart lib/meta_connector.dart test/test_all.dart
```

- `test_all.dart` : **99 PASS, 0 FAIL**
  (85 de base fusionnée + 14 nouveaux T25) :
  - T25a : listing avec unités explicites (`km`, `min`,
    `4320 min = 3,0 jours`, `0,00 km`).
  - T25b / T25b-bis : porte temps découpe distinct-temps (1 découpe,
    2 singletons, raisons `porte-temps-meta`).
  - T25c : événement étendu non découpé (coupure réseau, 5000 min).
  - T25d : catégorie mixte -> seuil local (découpe).
  - T25e / T25e-bis / T25e-ter : groupe contradictoire compté,
    reportIds inchangés, raison `statut-contradictoire`.
  - T25f / T25f-bis / T25f-ter : groupe multi-problème compté,
    drapeau citant E1, cas simple non signalé.
  - T25g : statuts conservent les reportIds.
  - T25h / T25h-bis : non-régression E4 (séparé à 6,5 km, doublon
    distant signalé, non fusionné).
- `test_exploratoire.dart` : **9 OK, 1 LIMITE (E7 seule)**, inchangé
  par rapport à la base fusionnée (E4 OK, E9 OK).
- `dart analyze` sur les trois fichiers modifiés : **No issues found!**
  (les 7 problèmes mongo_dart connus du dépôt, sur d'autres fichiers,
  ne concernent pas ce patch et n'ont pas été re-mesurés ici.)

## 6. Ce que ce patch NE résout pas

- Les statuts ne remplacent pas une vérification humaine : une fusion
  marquée contradictoire exige un humain pour trancher résolu contre
  en cours ; un groupe marqué multi-problème exige une revue (ou un
  futur découpage) pour ne pas perdre le second problème dans le plan.
  Un statut n'est pas une décision.
- Le lexique des statuts est DEV et limité : état ou problème formulé
  hors lexique, abréviation inédite, catégorie mal déclarée échappent
  au signalement. Le patch réduit les fusions silencieuses, il ne les
  élimine pas.
- La porte temps ne prouve rien sur l'identité : elle empêche une
  fusion au-delà d'un seuil, elle ne valide pas une fusion en deçà.
- Aucun appel Meta réel n'a été exécuté depuis ce code Dart ici : la
  preuve serveur bout en bout (serveur Windows, `MODEL_API_KEY` dans
  son environnement, endpoints `/api/meta`) reste à faire par le
  parent, après sa propre vérification et son propre push. Ce patch
  est local, testé, non poussé.
