# Phase 4 DEV — Comparaison CLASSIQUE contre META (CityResolve)

Statut : prototype DEV uniquement, données fictives visibles, protocole
scientifique NON GELÉ, seuils inchangés, aucune supériorité scientifique
déclarée. Rien n'a été poussé sur GitHub, rien n'a été envoyé à ChatGPT,
le miroir du dépôt n'a pas été modifié. Travail uniquement dans
`phase4-dev/` (plus une copie de travail Dart dans `phase4-dev/work/`).

## 1. Scénarios extraits, sans invention

Source : `work/lib/scenarios.dart` (jouet-1, dev-7) et
`test_exploratoire.dart` (E1, E2, copiés verbatim), via
`work/export.dart` vers `data/scenarios.json`.

- jouet-1 : 6 signalements, 3 incidents vrais
  (R1,R2), (R3,R4), (R5,R6).
- dev-7 : 20 signalements, 8 incidents vrais, graine 7, générés par le
  code Dart lui-même (le générateur Python n'a PAS été réimplémenté,
  car l'aléatoire Dart et l'aléatoire Python diffèrent).
- e1-diagnostic : 3 signalements (A1, A2, B1). Le code exploratoire dit
  « 2 incidents vrais » mais ne spécifie PAS la partition. Vérité
  déclarée non spécifiée : PAS de F1 pour E1, diagnostic seulement.
  Inventer une partition aurait été une invention.
- e2-synonymes : 2 signalements (A1, A2), 1 seul incident vrai, d'après
  le commentaire du code (« même incident, mots complètement
  différents »).

## 2. Méthodes, à entrées comparables

CLASSIQUE (Python, `compare.py`) : miroir fidèle de `grouping.dart`.
Jetons en minuscules, découpe sur les caractères non alphanumériques,
longueur > 2. Arête si distance <= 250 m ET écart <= 6 h ET
Jaccard >= 0,75. Groupes = composantes connexes. Signal patch ajouté
pour les paires ambiguës : texte similaire, temps proche, distance
> 2 x 250 m = doublon distant à vérifier, NON fusionné.
Vérification : les ensembles classiques Python sont identiques, groupe
par groupe, à `groupReports` Dart (contrôle `work/check_classic.dart`).

META (via le helper du connecteur uniquement, jamais de clé lue, copiée
ou journalisée) : modèle `muse-spark-1.3`, le plus récent de la liste
vérifiée. Prompt système à raisonnement maximal : analyse exhaustive,
chaque paire, chaque distance, chaque délai, chaque mot, aucun
raccourci, aucune certitude inventée, gravité absente = null.
Aucun paramètre `reasoning_effort` de l'API n'est utilisé : il n'est
pas documenté dans le connecteur, donc on ne l'invente pas. Le
« maximal » est donc un niveau de prompt, pas un paramètre vérifié.
Format identique au connecteur Dart : listing
`id | x y t | catégorie | texte`, JSON
`{"groupes": [{"reportIds": [...], "justification": string,
"incertitude": number 0..1}]}`. Les signalements omis par le modèle
seraient forcés en singletons, comme dans le code Dart.
Asymétrie à connaître : le listing Meta inclut la catégorie déclarée,
alors que le regroupement classique n'utilise que texte, distance et
temps (la catégorie ne sert ensuite qu'au domaine). Meta dispose donc
d'un signal de plus sur ce point précis.

Q (Dart réel, `work/q.dart`) : mêmes incidents agrégés par
`incidents.dart` pour les deux méthodes, même optimiseur exact
`optimizer.dart`, même simulateur `simulator.dart`, mêmes équipes.
Le Q officiel rapporté est le Q simulé, avec la règle documentée
violation globale => Q = 0. AUCUNE formule n'a été modifiée. Le Q
planifié est rapporté séparément, à titre descriptif uniquement.
Les identifiants d'incidents (I1, I2...) ne sont PAS comparables
d'une méthode à l'autre : ils dépendent de l'ordre des groupes.
La comparaison se fait par ensembles de signalements et par
identifiants de vérité terrain.

## 3. Commandes exactes

```text
cd ~/workspace/cityresolve/phase4-dev
../dart-sdk/bin/dart work/export.dart
python3 compare.py
../dart-sdk/bin/dart work/check_classic.dart
python3 meta_step.py
../dart-sdk/bin/dart work/q.dart data/scenarios.json data/meta_groups.json data/q_results.json
```

## 4. Résultats réels

### 4.1 Appels Meta : 17 sur 17 réussis, 0 erreur, sous la limite de 20

- Extractions : 13 appels (jouet R1,R3,R5 ; E1 A1 ; E2 A1 ;
  dev-7 D1,D5,D8,D11,D14,D16,D18,D20, premier signalement de chaque
  groupe vrai).
- Rapprochements : 4 appels, un par scénario.
- Modèle : `muse-spark-1.3` pour les 17 appels, confirmé par la
  réponse de l'API elle-même.
- Latences (mesurées par le helper, API) : extractions
  min 11 568 ms, médiane 21 450 ms, max 42 747 ms ;
  rapprochements min 10 731 ms, médiane 17 817 ms, max 28 612 ms ;
  total 354 707 ms (environ 5,9 minutes, wall clock plus longue car
  les appels sont séquentiels et le temps total mesuré est de
  356 888 ms).
- Jetons : prompt total 4 864 ; complétion totale 57 519, dont
  49 210 jetons de raisonnement ; total 62 383. Les jetons de
  complétion non raisonnement sont donc d'environ 8 309.
  Aucun prix en monnaie n'est fourni par la réponse de l'API :
  le coût monétaire est inconnu, non inventé.

### 4.2 Extractions : 13 sur 13 sans gravité inventée

- Gravité exprimée = null pour 13 extractions sur 13.
  Aucune gravité chiffrée n'a été inventée, alors que les textes ne
  contiennent aucun score 1..5.
- Exposition mentionnée : null pour 11 extractions sur 13.
  Les 2 mentions non nulles reprennent un mot présent dans le texte
  (« voitures » pour E2 A1, « piéton » pour D20), avec une incertitude
  explicite sur leur fonction. Ce ne sont pas des bandes d'exposition
  chiffrées.
- Localisation : plusieurs null prudents, par exemple E1 A1 et dev D1
  pour « rue basse », jugée ambiguë entre nom propre et description
  générique, sans numéro ni commune. C'est un refus d'inférer, pas un
  échec de format.
- Toutes les extractions listent des incertitudes et des éléments non
  vérifiés. Les sorties brutes analysées sont dans
  `logs/meta_calls.jsonl` (une ligne par appel, sans clé).

### 4.3 Regroupements et F1 par paires

| Scénario | F1 classique | F1 Meta | Désaccords |
|---|---|---|---|
| jouet-1 | 1,0 (TP 3, FP 0, FN 0) | 1,0 (TP 3, FP 0, FN 0) | 0 |
| dev-7 | 1,0 (TP 18, FP 0, FN 0) | 1,0 (TP 18, FP 0, FN 0) | 0 |
| e1-diagnostic | non calculable (vérité non spécifiée) | non calculable | 0 (les deux fusionnent A1,A2,B1) |
| e2-synonymes | 0,0 (TP 0, FP 0, FN 1) | 1,0 (TP 1, FP 0, FN 0) | 1 : paire A1,A2, classique séparée, Meta fusionnée, vrai fusionnée |

Groupes Meta exacts :
- jouet-1 : (R1,R2), (R3,R4), (R5,R6), incertitudes 0,0 partout.
- dev-7 : mêmes 8 ensembles que le classique, incertitudes 0,0 à 0,45
  (groupe D16,D17 à 0,45, donc marqué incertain ; D20 singleton forcé
  par construction, justification absente).
- e1 : (A1,A2,B1), incertitude 0,1, comme le classique.
- e2 : (A1,A2), incertitude 0,15, justification exhaustive citant
  position, temps et catégorie identiques.

Le seul cas où Meta bat le classique sur F1 est donc E2, le cas
synonymes, exactement le cas où le classique lexical est connu pour
échouer (Jaccard 0,00). Sur jouet-1 et dev-7, les deux méthodes sont
parfaites et identiques, donc ces scénarios ne discriminent rien :
ils étaient construits pour un regroupement parfait sous les
paramètres par défaut.

### 4.4 Q, même optimiseur, même simulateur

| Scénario | Méthode | Q planifié | Coût planifié | Q simulé | Coût simulé | Violations | Manqués (vérité) |
|---|---|---|---|---|---|---|---|
| jouet-1 | classique | 100,0 | 92,0 | 100,0 | 92,0 | aucune | aucun |
| jouet-1 | Meta | 100,0 | 92,0 | 100,0 | 92,0 | aucune | aucun |
| dev-7 | classique | 60,98 | 118,4 | 0,0 | 142,2 | budget dépassé : 142,2 > 120,0 | V2, V4, V7 |
| dev-7 | Meta | 60,98 | 118,4 | 0,0 | 142,2 | budget dépassé : 142,2 > 120,0 | V2, V4, V7 |
| e1 | les deux | non calculable | — | non calculable | — | vérité non spécifiée | — |
| e2 | classique | 100,0 | 44,0 | 100,0 | 44,0 | aucune | aucun |
| e2 | Meta | 100,0 | 24,0 | 100,0 | 24,0 | aucune | aucun |

Lecture honnête de E2 : le F1 passe de 0,0 à 1,0, mais le Q simulé
reste 100,0 dans les deux cas. Un meilleur F1 ne prouve donc PAS
automatiquement une meilleure allocation en Q. Ce qui change, c'est
l'efficacité : le classique traite un seul incident vrai comme deux
tâches (44,0 unités, deux passages), Meta comme une seule tâche
(24,0 unités, un passage). C'est un gain de coût et de charge, pas
un gain de Q, sur ce cas jouet.
Pour dev-7, les plans sont identiques en substance (mêmes vérités
achevées V1,V3,V5,V6,V8, mêmes manqués V2,V4,V7) : seuls les
identifiants d'incidents diffèrent, car ils dépendent de l'ordre
des groupes. Le Q simulé 0,0 des deux méthodes est la falaise
budgétaire documentée, pas un bug introduit ici, et la formule n'a
pas été touchée.

## 5. Erreurs rencontrées

- Aucune erreur d'appel Meta : 17 appels, retour 0, sorties JSON
  analysables, aucun résultat simulé, aucun repli.
- Un bogue de mon propre comparateur, corrigé avant livraison :
  la première version de `pair_disagreements` utilisait des paires
  ordonnées et comptait 78 faux désaccords sur dev-7, dus uniquement
  à l'ordre des groupes. Corrigé en paires non ordonnées : 0
  désaccord réel sur dev-7. Les F1 n'ont jamais été affectés, car
  ils sont calculés par paires non ordonnées dans le code Dart
  d'origine.
- `dart analyze` sur l'ensemble lib+test signale toujours 7 problèmes
  dus à l'absence du paquet `mongo_dart` non récupéré, déjà connus.
  Ils ne concernent ni le comparateur Python, ni `q.dart`, qui
  n'importent pas MongoDB.

## 6. Limites et non vérifié

- Données DEV uniquement, 31 signalements au total, 4 scénarios,
  dont 2 non discriminants (F1 parfait des deux côtés) et 1 sans
  vérité spécifiée (E1). Aucune conclusion scientifique, aucune
  généralisation à des signalements réels, aucun intervalle de
  confiance calculable sérieusement sur un seul cas discriminant.
- Une seule inférence par scénario pour le rapprochement : la
  variabilité inter-appels du modèle (température, échantillonnage)
  n'est pas mesurée. Un second appel pourrait donner d'autres groupes.
- Le classique comparé ici est le classique lexical du dépôt
  (Jaccard), pas une référence sémantique compétitive (embeddings,
  synonymes, modèle ouvert local). Battre Jaccard sur des synonymes
  ne prouve pas une supériorité sur une bonne référence sémantique.
- L'extraction n'a été testée que sur 13 signalements, tous avec
  gravité absente du texte. Le taux d'invention sur des textes
  ambigus, contradictoires ou avec gravité implicite reste inconnu.
- Le Q rapporté est le Q simulé DEV, avec durées, coûts et
  échéances fictifs. Il ne mesure pas une résolution réelle en ville.
- La preuve Meta porte sur l'accès via le connecteur de Muse, pas
  sur l'exécution bout en bout dans le serveur CityResolve lui-même
  (interface, MongoDB, navigateur). Cette preuve serveur reste à faire.
- La segmentation SAM 3.1 n'a pas été testée ici : aucun signalement
  n'a d'image, et l'endpoint chat ne fait pas de segmentation.
- Le coût monétaire total des 62 383 jetons est inconnu : l'API ne
  le renvoie pas dans ces réponses.

## 7. Conclusion

Sur ce petit jeu DEV, Meta apporte exactement une chose mesurée :
la fusion des synonymes E2, que le classique lexical rate, avec un
gain de coût (24,0 contre 44,0) mais sans gain de Q (100,0 partout).
Partout ailleurs, les deux méthodes sont identiques, et sur dev-7
elles échouent ensemble sur la même falaise budgétaire (Q simulé 0,0).
Cela ne prouve aucune supériorité scientifique, ni pour Meta ni pour
le classique : il faut des scénarios difficiles indépendants, une
vérité définie avant les sorties, une référence sémantique
compétitive, et une mesure répétée, après gel du protocole, pour
pouvoir parler de preuve. La prochaine étape utile, dans cet ordre,
est une comparaison contrôlée sur des cas difficiles avec vérité
prédéfinie, puis la preuve bout en bout dans le serveur CityResolve
lui-même, sans changer la formule Q ni le protocole en cours de route.

## 8. Fichiers livrés

- `compare.py` : classique miroir Dart, F1 par paires, désaccords,
  paires ambiguës (y compris signal patch, sans fusion forcée).
- `meta_step.py` : 17 appels Meta via le helper uniquement, journal
  par appel, budget respecté, erreurs non simulées.
- `work/export.dart`, `work/q.dart`, `work/check_classic.dart` :
  export DEV, Q Dart réel, contrôle classique Python contre Dart.
- `work/lib/` : copie de travail des bibliothèques Dart, miroir
  d'origine non modifié.
- `data/scenarios.json`, `data/classic_groups.json`,
  `data/classic_results.json`, `data/meta_groups.json`,
  `data/meta_extractions.json`, `data/final_f1.json`,
  `data/q_results.json`.
- `logs/meta_calls.jsonl` : 17 lignes, une par appel, avec modèle,
  latence, jetons, sortie brute analysée, sans clé.
- `data/meta_calls_summary.json` : total 17 appels, 0 erreur.
