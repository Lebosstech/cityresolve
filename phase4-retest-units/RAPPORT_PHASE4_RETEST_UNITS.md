# Phase 4 RETEST-UNITS — Nouveau listing avec unités explicites (CityResolve)

Statut : prototype DEV uniquement, données fictives, protocole scientifique
NON GELÉ, aucune formule Q, aucun seuil existant, aucun protocole modifié.
Rien n'a été poussé sur GitHub, rien n'a été envoyé à ChatGPT.
Dossiers interdits intacts : repo-mirror, phase4-dev, phase4-hard,
phase4-misleading, patch-e4-lock-app, patch-guardrail-app non modifiés
(hash miroir `grouping.dart` vérifié inchangé après travaux :
`7e360ed506c4a037af836756b9d8e103fba2bb60bbf356f43271895d8afb6d74`).
Aucune clé lue, copiée ou journalisée (vérifié par grep : aucune valeur
d'authentification dans les fichiers livrés ; les seuls motifs `Bearer`
trouvés sont dans le patch Dart, pas ici, et ce sont des jetons factices
préexistants du code de test d'origine).

## 1. Commandes exactes

```text
cd ~/workspace/cityresolve/phase4-retest-units
python3 compare_retest.py          # classique + synonymes, sans appel Meta
python3 meta_step_retest.py        # 6 rapprochements Meta, nouveau listing
python3 compute_final.py           # F1 par étage, sans nouvel appel Meta
```

La vérité terrain `data/truth.json` est une copie byte pour byte de
phase4-misleading, faite AVANT tout appel Meta de ce retest, et jamais
réécrite ensuite. Hash SHA-256 avant et après les appels Meta :
`3dc6b3544e8cb679db17d78199a0fe6eaf7f9718b77221e91f2d5b73ac84f8e9`
(identique à phase4-misleading, donc la vérité n'a pas été ajustée aux
sorties). Aucun scénario n'a été ajouté.

## 2. Ancien listing contre nouveau listing

Ancien listing (phase4-misleading), exemple distinct-temps :

```text
B1 | x=1.0 y=1.0 t=500 | catégorie=nid-de-poule | "nid poule rue lilas chaussee degradee"
B2 | x=1.0 y=1.0 t=4820 | catégorie=nid-de-poule | "nid poule rue lilas chaussee degradee important"
```

Le modèle y répondait que « l'unité temporelle était absente » et
fusionnait [B1, B2] en invoquant une « dégradation persistante ».

Nouveau listing (ce retest), même scénario :

```text
Unités (données ici, ne jamais les supposer absentes) : x et y en kilomètres (km)
sur une grille fictive, t en minutes (min) depuis le début du scénario.
60 min = 1 heure, 1440 min = 1 jour.
B1 | x=1,0 km, y=1,0 km, t=500 min | catégorie=nid-de-poule | "nid poule rue lilas chaussee degradee"
B2 | x=1,0 km, y=1,0 km, t=4820 min | catégorie=nid-de-poule | "nid poule rue lilas chaussee degradee important"
Distances et délais calculés :
Paire B1-B2 : distance 0,00 km, délai 4320 min = 3,0 jours.
```

Le prompt système ajoute, en plus du raisonnement maximal : ne jamais
écrire qu'une unité est absente quand le listing la donne ; 4320 min
vaut 3 jours, pas un délai court ; pour un incident ponctuel, un délai
de plusieurs jours au même lieu ne prouve pas l'identité, même avec un
texte quasi identique.

Vérification textuelle : dans les 6 justifications de ce retest, aucune
ne dit qu'une unité est absente (0 occurrence, contre l'erreur explicite
de phase4-misleading). La justification distinct-temps écrit :
« délai 4320 min = 3,0 jours car 3x1440 min, délai long pas court ».

## 3. Résultats : F1 avant / après, par scénario

F1 par paires non ordonnées. Classique et synonymes sont recalculés
ici et reproduisent exactement phase4-misleading (même code, mêmes
règles) : classique moyenne 0,50 ; synonymes 0,67.

| Scénario | Classique | Synonymes | Meta ancien listing | Meta nouveau listing (brut) | Groupes Meta nouveau |
|---|---|---|---|---|---|
| contra-resolu | 0,0 (séparés) | 0,0 (séparés) | 0,0 (séparés) | 1,0 (fusionnés) | [A1, A2] (inc. 0,85) |
| distinct-temps | 1,0 (séparés) | 1,0 (séparés) | 0,0 (fusionnés à tort) | 1,0 (séparés) | [B1], [B2] (inc. 0,50) |
| distinct-detail | 1,0 (séparés) | 1,0 (séparés) | 1,0 (séparés) | 1,0 (séparés) | [C1], [C2] (inc. 0,35) |
| categorie-contredit | 1,0 (fusionnés) | 1,0 (fusionnés) | 1,0 (fusionnés) | 1,0 (fusionnés) | [D1, D2] (inc. 0,20) |
| multi-probleme | 0,0 (fusionnés à tort) | 1,0 (séparés) | 0,0 (fusionnés à tort) | 0,0 (fusionnés à tort) | [E1, E2] (inc. 0,15) |
| typo-abreviation | 0,0 (séparés) | 0,0 (séparés) | 1,0 (fusionnés) | 1,0 (fusionnés) | [F1, F2] (inc. 0,00) |

Moyenne des F1 par scénario, Meta : ancien listing 0,50 ; nouveau
listing brut 0,83 (5/6). **Le cas décisif distinct-temps est corrigé :
Meta sépare enfin les deux nids-de-poule à 3 jours d'intervalle.**

Deux nuances à ne pas lisser :
- contra-resolu passe de 0,0 à 1,0, mais avec une incertitude de 0,85
  et une justification qui signale explicitement la contradiction
  d'état (sec/résolu contre inondé/en cours). C'est une fusion
  correcte au sens de la vérité prédéfinie, mais une fusion douteuse
  au sens opérationnel : sans le statut contradictoire (section 4),
  elle serait trompeuse.
- multi-probleme reste à 0,0, avec l'incertitude la PLUS basse du
  retest (0,15) pour la fusion la plus dommageable (le réverbère
  éteint disparaît du plan). L'incertitude du modèle ne protège
  toujours contre rien : c'est le drapeau déterministe qui doit le
  faire (section 4).

## 4. Effet de chaque mécanisme, mesuré séparément

C'est le point méthodologique central : sans décomposition, on
attribuerait au listing un gain venu d'ailleurs, ou l'inverse.

### 4.1 Listing seul : tout le gain de F1

Meta ancien 0,50 -> Meta nouveau brut 0,83. Les deux scénarios gagnés
(contra-resolu, distinct-temps) le sont par la sortie modèle elle-même,
sans aucun post-filtre. La porte temps et les statuts ne changent pas
le F1 du nouveau listing (voir 4.2 et 4.3) : **le gain mesuré ici est
un gain de format d'entrée, pas un gain de garde-fou.**

### 4.2 Porte temps : 0 effet sur le nouveau listing, 1 correction sur l'ancien

Règle déterministe documentée (`mechanisms.py`, reprise dans le patch
Dart) : dans un groupe proposé par le modèle, deux signalements ne
restent liés que si leur délai <= seuil. Seuil local (incidents
ponctuels) : 360 min (6 h), aligné sur la porte classique. Exception
événements étendus : si TOUS les signalements du groupe ont une
catégorie dans {coupure-electrique, panne-reseau}, seuil 10080 min
(7 jours), car un événement réseau peut persister plusieurs jours.
Catégorie mixte -> seuil local (choix conservateur : on découpe).
La porte est appliquée APRÈS la sortie modèle, comme le garde-fou, et
chaque découpe est comptée.

- Appliquée au NOUVEAU listing : 0 découpe, F1 inchangé (0,83 -> 0,83).
  Elle n'a rien eu à corriger parce que le modèle avait déjà séparé
  distinct-temps. Attribuer le gain distinct-temps à la porte temps
  serait faux.
- Appliquée aux ANCIENNES sorties Meta (mesure indépendante, sans
  nouvel appel) : 1 découpe, distinct-temps 0,0 -> 1,0, tous les autres
  scénarios inchangés. **La porte temps aurait corrigé l'ancienne
  erreur.** C'est donc un filet de sécurité réel, même si elle ne
  change rien sur ce run précis.
- Tests DEV unitaires (avant tout appel Meta) : découpe distinct-temps
  (4320 min > 360) ; non-découpe d'une coupure réseau à 5000 min
  (< 10080) ; découpe d'un groupe mixte à 500 min (seuil local).
  La porte ne casse donc pas les événements étendus par construction,
  mais l'exception repose sur la catégorie déclarée : une coupure
  mal catégorisée retomberait sur le seuil local. Limite assumée.

### 4.3 Statuts : 0 effet sur le F1, effet opérationnel décisif

Les statuts ne découpent JAMAIS un groupe : ils le marquent
(`uncertain = true` + raison explicite), donc le F1 strict est
inchangé par construction (0,83 -> 0,83). Leur effet se mesure en
fusions propres contre fusions signalées :

(a) Statut groupe contradictoire : un groupe fusionné est marqué si
ses signalements portent des états opposés (lexique DEV : résolu/sec/
terminé contre inondé/coule) OU si l'écart des gravités ou expositions
déclarées est >= 2. Valeurs conservées, jamais moyennées.
(b) Drapeau multi-problème : un signalement est marqué s'il touche
>= 2 familles de problèmes DEV (voirie-nid, éclairage, eau,
électricité — lexique limité documenté dans `mechanisms.py`). Son
groupe ne peut pas être compté comme un seul incident propre sans ce
drapeau.

Sur le nouveau listing Meta brut :

| Scénario | Fusions | Fusions propres | Fusions signalées |
|---|---|---|---|
| contra-resolu | 1 ([A1, A2]) | 0 | 1 (contradictoire) |
| categorie-contredit | 1 ([D1, D2]) | 1 | 0 |
| multi-probleme | 1 ([E1, E2]) | 0 | 1 (multi-problème, E1) |
| typo-abreviation | 1 ([F1, F2]) | 1 | 0 |
| distinct-temps, distinct-detail | 0 fusion | — | — |

Sur les groupes de vérité eux-mêmes (ce que les statuts auraient
signalé si la fusion de vérité avait eu lieu) : contra-resolu est
marqué contradictoire, multi-probleme est marqué multi-problème (E1),
les 4 autres ne sont marqués ni l'un ni l'autre. **Les deux statuts
requis par phase4-misleading sont donc exactement ceux qui se
déclenchent, et seulement là où ils sont requis.**

Autre enseignement : appliqués au classique, les statuts marquent
aussi la fusion classique multi-probleme [E1, E2] (drapeau
multi-problème) sans changer son F1 (0,0). Les statuts ne sont donc
pas un correctif Meta : ce sont des propriétés du regroupement,
quelle que soit la méthode. Appliqués aux synonymes multi-probleme
(séparés), le singleton E1 reste marqué multi-problème — correct :
le drapeau porte sur le signalement, pas seulement sur la fusion.

### 4.4 Synthèse de l'attribution

| Étage | F1 moyen Meta | Ce qui change |
|---|---|---|
| Ancien listing | 0,50 | référence phase4-misleading |
| Nouveau listing, brut | 0,83 | +contra, +distinct-temps (modèle seul) |
| Nouveau listing + porte temps | 0,83 | 0 découpe sur ce run |
| Nouveau listing + statuts | 0,83 | F1 inchangé ; 2 fusions signalées au lieu de propres |
| Nouveau listing + porte + statuts | 0,83 | idem, sans interaction |
| Ancien listing + porte temps (contrôle) | 0,67 | distinct-temps corrigé seul (0,50 -> 0,67) |

## 5. Appels Meta : 6 sur 6 réussis, 0 échec, sous la limite de 30

6 rapprochements uniquement (aucune extraction dans ce retest : les
statuts sont déterministes, ils n'ont pas besoin d'extraction).
Modèle confirmé `muse-spark-1.3` pour les 6 réponses. Latences :
min 6 636 ms, médiane 12 115 ms, max 36 543 ms, total 103 975 ms.
Jetons : prompt 3 908 ; complétion 23 366, dont 20 767 de raisonnement ;
total 27 274 (hors raisonnement : 2 599). Coût monétaire inconnu,
non renvoyé par l'API, non inventé. Journal : `logs/meta_calls.jsonl`
(avec le listing envoyé par appel, sans aucune clé).

## 6. Pourquoi le Q n'est PAS calculé ici

Même raison que phase4-misleading : la vérité exige un statut
contradictoire non représentable comme incident propre, et un seul
signalement vaut deux incidents (multi-probleme), donc fusionner ou
séparer change le nombre d'incidents lui-même ; aucun scénario ne
définit équipe, budget ni échéance d'allocation. Calculer un Q
obligerait à inventer ces entrées. Le F1 par paires reste la seule
mesure rapportée.

## 7. Limites, à ne pas dépasser

- 6 scénarios, 12 signalements, 6 paires, une seule inférence Meta par
  scénario : aucune généralisation, aucune significativité statistique.
  Le gain 0,50 -> 0,83 repose sur 2 scénarios ; une répétition pourrait
  le faire bouger dans les deux sens (variabilité inter-appels non
  mesurée ici).
- Le nouveau listing et le nouveau prompt changent deux choses à la
  fois (format + instruction explicite sur les unités). L'effet ne peut
  pas être attribué séparément au format seul ou à l'instruction seule
  avec ce run : l'intervention testée est l'ensemble « unités
  explicites + instruction ».
- Le lexique des statuts est DEV et limité : une abréviation inédite,
  une formulation d'état hors lexique, ou une catégorie mal déclarée
  échappent au drapeau ou à l'exception étendue. Les statuts signalent,
  ils ne vérifient pas : une fusion marquée contradictoire ou
  multi-problème exige toujours une vérification humaine avant toute
  décision opérationnelle.
- L'exception événements étendus repose sur la catégorie déclarée et
  sur un seuil de 7 jours choisi par convention (pas mesuré sur des
  pannes réelles). Un événement étendu réel plus long, ou une panne
  locale de plusieurs jours, restent des cas non couverts.
- Aucune preuve serveur bout en bout dans ce retest (le patch Dart
  correspondant est livré séparément, testé sans appel Meta réel),
  aucune image, SAM 3.1 non testé, coût monétaire inconnu.
- Les justifications Meta complètes sont dans `logs/meta_calls.jsonl`
  (champ raw_content) et les groupes dans `data/meta_groups.json`
  (brut), `data/meta_groups_gated.json` (porte temps),
  `data/meta_groups_full.json` (porte + statuts).

## 8. Conclusion honnête, sans supériorité scientifique

Le défaut de format est confirmé comme cause principale de l'échec
distinct-temps : avec des unités explicites, le modèle ne prétend plus
que l'unité est absente, il convertit 4320 min en 3 jours, et il sépare.
La porte temps, elle, n'explique pas le gain de ce run, mais elle
aurait corrigé l'ancienne erreur : elle reste justifiée comme filet
de sécurité, pas comme explication. Les statuts ne changent aucun F1,
mais ils transforment les deux fusions trompeuses restantes (contra,
multi) en fusions signalées au lieu de fusions propres — ce qui est
exactement le progrès opérationnel attendu, sans prétendre résoudre
les cas : contra exige toujours un humain pour trancher résolu contre
en cours, multi exige toujours un découpage ou une revue pour ne pas
perdre l'éclairage. Il reste un seul échec de regroupement (multi,
F1 0,0), et il est désormais signalé, pas silencieux. Aucune
supériorité scientifique n'est prouvée : 6 paires, une inférence par
scénario, données fictives.
