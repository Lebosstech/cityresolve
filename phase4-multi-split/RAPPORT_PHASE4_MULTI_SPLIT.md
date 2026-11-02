# Phase 4 MULTI-SPLIT — Découpage multi-problème (CityResolve)

Statut : prototype DEV uniquement, données fictives, protocole
scientifique NON GELÉ, seuils inchangés, aucune formule Q modifiée,
aucune supériorité scientifique déclarée. Rien n'a été poussé sur
GitHub, rien n'a été envoyé à ChatGPT, les dossiers interdits n'ont
pas été modifiés. Travail uniquement dans `phase4-multi-split/` et
dans le patch `patch-multi-split-app/` (local, non poussé).

## 1. Problème

En phase4-misleading, E1 (nid-de-poule + réverbère éteint) fusionné
avec E2 (nid-de-poule seul) donnait un seul groupe, donc un seul
incident pour l'optimiseur, et l'éclairage disparaissait du plan
malgré la justification. Le drapeau multi-problème signalait le cas,
il ne le résolvait pas. Cette mission teste si le découpage le résout.

## 2. Vérité prédéfinie et règle de comptage

Fichiers `data/truth.json` et `data/scenarios.json` écrits AVANT tout
appel Meta. Hash initial de `truth.json` : `90b54a49…`. Une seule
modification ensuite, AVANT tout appel Meta : la définition de survie
a été resserrée après un premier calcul déterministe qui révélait une
faille (un faisceau même-signalement `[E1:eclairage, E1:voirie]`
comptait à tort comme survie, alors que l'optimiseur y verrait une
seule tâche groupée). Les incidents vrais n'ont pas changé ; le hash
final est `d9c8830c…`.

Règle de comptage (dans `truth.json`) :
- Unité de vérité = le SOUS-signalement `ID:famille`, un par famille
  DEV explicite (lexique : voirie-nid, eclairage, eau, electricite).
- Incidents vrais = ensembles de sous-signalements de MÊME famille.
- Métriques principales : nombre d'incidents produits, et SURVIE du
  problème secondaire (vrai si et seulement si la méthode produit un
  incident contenant le secondaire ET aucun sous-signalement d'une
  autre famille, quel que soit le signalement d'origine ; un
  singleton secondaire compte comme survie).
- F1 adapté : paires de sous-signalements de MÊME famille uniquement.
  CAVEAT DÉMONTRÉ CI-DESSOUS : ce F1 vaut 1,0 même quand le
  secondaire est perdu. Il ne doit jamais être lu seul.
- Couverture exacte : fraction des incidents vrais reproduits
  exactement (même ensemble de sous-signalements).

Scénarios (textes DEV, lieu et temps proches sauf mention) :
- (a) split-origine : E1 nid-de-poule + réverbère éteint, E2
  nid-de-poule seul (textes repris verbatim de phase4-misleading).
  Vérité : 2 incidents, voirie [E1:voirie, E2:voirie] et éclairage
  [E1:eclairage]. Secondaire : E1:eclairage.
- (b) split-seul : M1 seul, fuite d'eau + réverbère éteint.
  Vérité : 2 incidents, [M1:eau] et [M1:eclairage].
- (c) split-faux : N1 seul, même problème deux fois (nid-de-poule,
  trou). Vérité : 1 incident, pas de découpage.
- (d) split-vague : V1 seul, nid-de-poule + mention vague
  (« quelque chose aussi la nuit », sans famille explicite).
  Vérité : 1 incident, PAS de découpage automatique, revue humaine.
- (e) split-trois : T1 seul, nid-de-poule + réverbère éteint + fuite
  d'eau. Vérité : 3 incidents.

## 3. Méthodes

- classique : miroir Dart (250 m, 6 h, Jaccard >= 0,75), sans découpage.
- synonymes : mêmes portes, jetons normalisés (dictionnaire
  phase4-hard), sans découpage.
- classique-split / synonymes-split : découpage déterministe avant
  regroupement. Chaque signalement est expansé par famille ; deux
  sous-signalements ne sont groupés que s'ils partagent la même
  famille et passent les portes distance et temps. Aucun seuil
  Jaccard après découpage (la famille explicite est l'appariement) ;
  le découpage par synonymes est identique au découpage classique,
  car il ne dépend pas de la normalisation des jetons.
- meta_nosplit : regroupement Meta historique, groupes de
  signalements, un signalement dans au plus un groupe.
- meta_split : regroupement Meta avec découpage. Le prompt impose de
  découper UNIQUEMENT un problème explicite distinct, jamais un même
  problème décrit deux fois, jamais à partir d'une mention vague.
  Groupes de sous-signalements `ID:famille` ; les unités omises sont
  forcées en singletons.

## 4. Commandes exactes

```text
cd ~/workspace/cityresolve/phase4-multi-split
python3 compare_multi.py
python3 meta_step_multi.py
python3 compute_final.py
```

## 5. Appels Meta : 10 réussis, 0 échec, limite 30 respectée

Modèle `muse-spark-1.3` uniquement, via le helper du connecteur,
prompt à raisonnement maximal, aucun paramètre `reasoning_effort`
inventé. 5 rapprochements sans découpage + 5 avec découpage, 0
extraction. Latences : min 7 323 ms, médiane 13 930 ms, max
27 511 ms, total 145 389 ms. Jetons : entrée 3 924, sortie 31 590
dont 28 043 de raisonnement, total 35 514. Coût monétaire inconnu,
l'API ne le renvoie pas.

## 6. Résultats

Tableau : (nombre d'incidents, survie secondaire, couverture exacte,
F1 adapté). Survie = null quand il n'y a pas de secondaire.

| Scénario | classique | synonymes | classique-split | meta_nosplit | meta_split |
|---|---|---|---|---|---|
| (a) origine (vérité 2) | 1, Non, 0,0, 1,0 | 2, Non, 0,0, 0,0 | 2, Oui, 1,0, 1,0 | 1, Non, 0,0, 1,0 | 2, Oui, 1,0, 1,0 |
| (b) seul (vérité 2) | 1, Non, 0,0, 1,0 | 1, Non, 0,0, 1,0 | 2, Oui, 1,0, 1,0 | 1, Non, 0,0, 1,0 | 2, Oui, 1,0, 1,0 |
| (c) faux (vérité 1) | 1, -, 1,0, 1,0 | 1, -, 1,0, 1,0 | 1, -, 1,0, 1,0 | 1, -, 1,0, 1,0 | 1, -, 1,0, 1,0 |
| (d) vague (vérité 1) | 1, -, 1,0, 1,0 | 1, -, 1,0, 1,0 | 1, -, 1,0, 1,0 | 1, -, 1,0, 1,0 | 1, -, 1,0, 1,0 |
| (e) trois (vérité 3) | 1, Non, 0,0, 1,0 | 1, Non, 0,0, 1,0 | 3, Oui, 1,0, 1,0 | 1, Non, 0,0, 1,0 | 3, Oui, 1,0, 1,0 |

Lecture :
- **L'éclairage survit désormais avec découpage, dans les 3 cas
  multi-problèmes, pour le découpage déterministe ET pour Meta avec
  découpage.** Meta_split reproduit exactement la vérité dans les
  5 cas : origine [E1:voirie, E2:voirie] + [E1:eclairage] ; seul
  [M1:eau] + [M1:eclairage] ; trois [T1:voirie] + [T1:eclairage] +
  [T1:eau] ; faux et vague non découpés, avec justifications
  explicites (reformulation du même problème ; mention vague sans
  problème explicite, donc aucun second sous-signalement créé).
- **Sans découpage, l'éclairage est perdu partout, y compris chez
  Meta.** Meta_nosplit donne 1 incident dans les 3 cas, avec une
  justification qui signale pourtant le double problème (origine :
  « (b) reste non corroboré sans groupe séparé faute d'autre
  signalement » ; seul et trois : signalement explicite de
  l'hétérogénéité, incertitude 0,5 et 0,8). Le signalement ne suffit
  pas : il faut le découpage pour que l'optimiseur voie la tâche.
- **Le F1 adapté seul est trompeur, et c'est démontré.** Le classique
  affiche F1 = 1,0 dans les 5 cas, alors qu'il perd le secondaire
  dans les 3 cas multi-problèmes et que sa couverture exacte y est
  de 0,0. Raison : le F1 ne compte que les paires de même famille,
  et un secondaire singleton perdu ne crée ni faux positif ni faux
  négatif de paire. Ne jamais rapporter ce F1 sans la survie et le
  nombre d'incidents.
- Les synonymes sans découpage séparent E1 et E2 à l'origine
  (Jaccard synonymes 0,67 < 0,75), mais l'éclairage reste groupé avec
  la voirie de E1 : 2 incidents, survie Non, couverture 0,0,
  F1 0,0. Séparer n'est pas découper.

## 7. Patch application (local, non poussé)

Dossier `patch-multi-split-app/` (base : copie de
`patch-units-status-app/app/`, 99 PASS avant modification).
Fichiers modifiés : `lib/grouping.dart` (`Subunit`,
`expandToSubunits`, `groupSplitReports`, `splitGroupsByFamily`),
`lib/incidents.dart` (`familyDomain`, `aggregateSplitGroups`),
`test/test_all.dart` (section 26, 11 vérifications T26a–h).
Notes : `PATCH_MULTI_SPLIT_NOTES.md`.

Résultats réels, SDK Dart de `~/workspace/cityresolve/dart-sdk` :
- `dart test/test_all.dart` : **110 PASS, 0 FAIL** (99 + 11).
- `dart test/test_exploratoire.dart` : **9 OK, 1 LIMITE (E7 seule)**.
- `dart analyze` sur les 3 fichiers modifiés : **No issues found!**

Limites du patch, à ne pas dépasser : lexique DEV limité (une
formulation hors lexique échappe au découpage) ; vague non découpé
par choix, revue humaine requise ; deux volets d'un même signalement
partagent les valeurs déclarées de l'origine (aucune gravité ni
exposition propre à un volet n'est créée) ; un signalement découpé
augmente le nombre d'incidents, donc le coût et le plan changent ;
la persistance des identifiants `ORIGINE:FAMILLE` par le serveur réel
et le branchement de `aggregateSplitGroups()` dans le serveur sont
des travaux d'intégration séparés, non faits ici (le serveur actuel
appelle `aggregate()` sur des groupes de signalements).

## 8. Q : non calculé, délibérément

Aucune équipe, aucun budget, aucune échéance d'allocation n'est
défini dans ces scénarios de test par paires et par volets. Calculer
un Q exigerait d'inventer exactement ces entrées. Le patch Dart
produit bien des incidents pour l'optimiseur, mais sans paramètres
d'allocation définis, aucun Q n'est rapporté.

## 9. Limites générales

- 5 scénarios, 7 signalements, une seule inférence Meta par
  variante et par scénario : aucune portée statistique, aucune
  supériorité scientifique déclarée.
- Le découpage déterministe et Meta_split donnent ici les mêmes
  résultats : cela valide le mécanisme sur ces cas, pas une valeur
  ajoutée de Meta sur le découpage (Meta suit ici l'instruction de
  découpage, il ne la découvre pas seul).
- Textes DEV en style mots-clés, sans bruit réel ; preuve toujours
  via le connecteur uniquement, pas de bout en bout dans le serveur
  CityResolve pour le découpage ; SAM 3.1 non testé.
- La règle de survie a été resserrée avant tout appel Meta (voir
  section 2) : c'est une clarification de métrique, pas un
  changement de vérité, et elle est documentée comme telle.
