# Phase 4 HARD — Scénarios difficiles contrôlés (CityResolve)

Statut : prototype DEV uniquement, données fictives, protocole
scientifique NON GELÉ, aucune formule Q ni aucun seuil modifié,
aucune supériorité scientifique déclarée. Rien n'a été poussé sur
GitHub, rien n'a été envoyé à ChatGPT. Travail uniquement dans
`phase4-hard/` ; `repo-mirror/`, `patch-e4-lock-app/` et
`phase4-dev/` n'ont été que lus, jamais modifiés. Aucune clé API
n'a été lue, copiée ou journalisée (vérifié par grep sur tous les
fichiers livrés : aucun secret, aucun substitut, aucune valeur).

## 1. Ordre de travail : vérité AVANT sorties Meta

1. `data/truth.json` écrit en premier : partition vraie de chacun
   des 10 scénarios, avec sa note d'interprétation.
2. `data/scenarios.json` construit à partir de ces partitions.
3. Comparateur déterministe (`compare_hard.py`) : classique +
   baseline synonymes, sans aucun appel Meta.
4. `meta_step_hard.py` seulement ensuite : extractions puis
   rapprochements Meta, puis 2 répétitions de dist-2inc.
5. `data/final_f1.json` calculé après coup sur les trois méthodes.

La vérité n'a jamais été modifiée après une sortie Meta. Si un
scénario est ambigu, sa note le dit explicitement (voir dist-1event
et inc-sans-lieu ci-dessous) au lieu de masquer l'ambiguïté.

## 2. Commandes exactes

```text
cd ~/workspace/cityresolve/phase4-hard
python3 compare_hard.py
python3 meta_step_hard.py
# puis calcul de final_f1.json (paires non ordonnées, 3 méthodes)
```

## 3. Scénarios et vérité prédéfinie (20 signalements, 10 paires)

Chaque scénario contient exactement 2 signalements, donc chaque F1
vaut 0 ou 1 : le F1 mesure ici la paire, pas une statistique large.

### Synonymes — vérité : fusionnée (4 paires)
- syn-panne : A1 « coupure courant quartier nord immeubles » /
  A2 « panne electrique quartier nord immeubles », même lieu (1,1),
  t 500/540.
- syn-fuite : B1 « fuite eau rue basse trottoir inonde » /
  B2 « ecoulement eau rue basse trottoir mouille », lieu (2,2),
  t 500/545.
- syn-nid : C1 « nid poule rue lilas chaussee degradee » /
  C2 « trou rue lilas chaussee degradee », lieu (3,3), t 500/530.
- syn-eclairage : D1 « reverbere eteint avenue nord nuit » /
  D2 « lampadaire defaillant avenue nord nuit », lieu (4,4),
  t 500/550.

### Même texte, lieux éloignés — 2 cas contrastés
- dist-2inc : E1/E2, texte identique « fuite eau trottoir inonde
  canalisation locale », lieux (1,1) et (8,1), soit 7 km, t 500/530.
  Vérité : 2 incidents distincts, ne pas fusionner.
- dist-1event : F1/F2, texte identique « coupure electrique
  generale reseau quartier courant coupe », lieux (1,1) et (8,1),
  7 km, t 500/520. Vérité : 1 incident étendu (coupure générale
  de réseau). ATTENTION : cette fusion est une CONVENTION de
  modélisation, pas une vérité déductible du seul texte ni de la
  seule distance. Une séparation y est défendable ; le F1 compte
  ici la convention prédéfinie. La mesure intéressante est donc
  moins le 0/1 que la justification et l'incertitude de Meta.

### Contradictions
- contra-1 : G1/G2, texte identique « fuite eau rue basse trottoir
  inonde », lieu (3,3), t 500/540. Gravité déclarée 2 contre 4,
  exposition déclarée 0 contre 3. Vérité : même incident, mais
  AUCUNE gravité ni exposition unique ne doit être inventée ;
  statut attendu : contradictoire, valeurs conservées.

### Incomplets
- inc-vide : I1/I2, textes vides « », lieu (1,1), t 500/530.
  Vérité : séparés. Un texte vide n'est aucune preuve de sameness ;
  fusionner serait inventer.
- inc-sans-lieu : K1/K2, « fuite eau trottoir inonde »,
  coordonnées absentes (x/y null), t 500/530. Vérité : fusionnés,
  mais lieu inconnu : fusion incertaine, aucun lieu à inventer.
- inc-sans-temps : L1/L2, « nid poule chaussee degradee »,
  lieu (1,1), temps absent (t null). Vérité : fusionnés, mais
  temps inconnu : fusion incertaine, aucun temps à inventer.

## 4. Méthodes

CLASSIQUE : miroir fidèle du code Dart (distance ≤ 250 m, écart
≤ 6 h, Jaccard ≥ 0,75, composantes connexes, texte sans jeton = 0).
Jaccard brut sur les 4 paires synonymes : 0,429 / 0,500 / 0,571 /
0,429 — toutes sous le seuil, le classique échoue donc sur les 4
par construction, ce qui est le point de départ du test, pas une
surprise.

Extension documentée pour données manquantes (phase4 n'avait aucun
null) : si coordonnées ou temps absents, la porte correspondante
est passante (aucune preuve contre), MAIS le groupe est marqué
incertain avec la raison explicite. Jamais de lieu ni de temps
inventé pour combler un null.

BASELINE SYNONYMES : mêmes portes et même seuil 0,75, mais jetons
normalisés par un dictionnaire français écrit à la main, limité
strictement au vocabulaire urbain de ces scénarios :
panne, coupure → panne ; courant, electricite, electrique → courant ;
fuite, ecoulement → fuite ; canalisation, conduite → canalisation ;
inonde, mouille → inonde ; nid, poule, trou → niddepoule ;
abimee, degradee, degrade → degrade ;
reverbere, lampadaire, eclairage → luminaire ;
eteint, defaillant → defaillant.
Après normalisation, les 4 paires synonymes atteignent Jaccard 1,0.
CAVEAT DE CIRCULARITÉ, À NE PAS OUBLIER : ce dictionnaire a été
écrit en connaissant les paires testées. Son 4/4 sur synonymes
montre que la normalisation lexicale suffit sur ces cas, pas
qu'elle généralise à du vocabulaire imprévu. Il ne prétend à
aucune couverture générale.

META : modèle muse-spark-1.3 uniquement, via le helper du
connecteur, prompt système à raisonnement maximal et exhaustif.
Aucun paramètre reasoning_effort n'est utilisé (non documenté
dans le connecteur). Listing « id | x y t | catégorie | texte »,
avec « inconnu » pour les valeurs absentes ; pour contra-1
uniquement, le listing ajoute les colonnes « gravite declaree »
et « exposition declaree » et l'instruction explicite de ne pas
résoudre la contradiction en une valeur unique. Les signalements
omis par le modèle seraient forcés en singletons, comme dans le
code Dart (aucun cas ici).

## 5. Appels Meta : 16 sur 16 réussis, 0 échec

Limite 30 respectée, avec marge. 4 extractions + 10 rapprochements
+ 2 répétitions de dist-2inc. Modèle confirmé muse-spark-1.3 dans
les 16 réponses. Aucun appel en échec, donc aucun F1 calculé sur
un repli silencieux ; si un appel avait échoué, le scénario aurait
été marqué en échec dans final_f1.json.

- Extractions : latences min 11 518 ms, médiane 13 953 ms,
  max 15 483 ms, total 54 908 ms ; jetons : 889 en entrée,
  9 679 en sortie dont 8 524 de raisonnement, total 10 568.
- Rapprochements (12 appels) : latences min 5 876 ms, médiane
  18 024 ms, max 29 635 ms, total 206 127 ms ; jetons : 3 904 en
  entrée, 40 207 en sortie dont 35 267 de raisonnement,
  total 44 111.
- Total : 4 793 jetons en entrée, 49 886 en sortie dont 43 791 de
  raisonnement, 54 679 au total. Coût monétaire inconnu : l'API
  ne le renvoie pas, il n'est pas inventé.

## 6. Résultats F1 par paires non ordonnées

| Scénario | Classique | Synonymes | Meta |
|---|---|---|---|
| syn-panne | 0,0 | 1,0 | 1,0 |
| syn-fuite | 0,0 | 1,0 | 1,0 |
| syn-nid | 0,0 | 1,0 | 1,0 |
| syn-eclairage | 0,0 | 1,0 | 1,0 |
| dist-2inc | 1,0 | 1,0 | 1,0 |
| dist-1event | 0,0 | 0,0 | 1,0 |
| contra-1 | 1,0 | 1,0 | 1,0 |
| inc-vide | 1,0 | 1,0 | 0,0 |
| inc-sans-lieu | 1,0 | 1,0 | 0,0 |
| inc-sans-temps | 1,0 | 1,0 | 1,0 |
| **Moyenne (10 paires)** | **0,50** | **0,90** | **0,80** |

Désaccords (paires où les méthodes divergent) :
- Les 4 paires synonymes : classique séparé, synonymes et Meta
  fusionnés, vérité fusionnée.
- dist-1event (F1,F2) : classique et synonymes séparés, Meta
  fusionné, vérité conventionnelle fusionnée.
- inc-vide (I1,I2) : classique et synonymes séparés, Meta
  fusionné, vérité séparée. ÉCHEC META.
- inc-sans-lieu (K1,K2) : classique et synonymes fusionnés, Meta
  séparé, vérité fusionnée. ÉCHEC META par prudence excessive
  (voir §7).
- Aucun désaccord sur dist-2inc, contra-1, inc-sans-temps.

## 7. Où Meta échoue, et où il distingue vraiment

### Échec net : inc-vide — Meta fusionne deux textes vides
Meta regroupe I1 et I2 avec une incertitude de 1,0, la plus haute
possible, tout en fusionnant quand même. Sa propre justification
le dit : « aucune preuve positive du même incident réel »,
« très douteux et ambigu », fondé « uniquement sur co-localisation
exacte et proximité temporelle », « sans aucun élément factuel
vérifiable ». Décision et raisonnement se contredisent : le score
d'incertitude maximal n'a pas empêché la fusion. C'est le cas le
plus dangereux observé : un regroupement sans aucune preuve
textuelle, qui passerait inaperçu si l'on ne lisait que les groupes.

En revanche, l'extraction du même signalement vide, elle, est
prudente : problème « indéterminé - signalement vide »,
localisation, temps, gravité et exposition tous à null. La
prudence de l'extraction ne se retrouve pas dans le regroupement.
À retenir comme règle de conception : ne jamais laisser un
regroupement fusionner sur coordonnées + temps seuls quand le
contenu est vide ; un garde-fou déterministe (texte vide = pas de
fusion) est nécessaire, l'incertitude du modèle ne suffit pas.

### Échec par prudence : inc-sans-lieu — Meta sépare à tort
Meta sépare K1 et K2 avec incertitude 1,0, « maintenu isolé par
précaution », distance incalculable car lieu inconnu. La séparation
est défendable (le lieu est vraiment inconnu), mais elle contredit
la vérité prédéfinie (texte identique, temps proches) et coûte
le point F1. Symétriquement, le classique et la baseline fusionnent
en passant la porte distance et en marquant le groupe incertain.
Leçon : face à une donnée manquante, Meta choisit ici la prudence
maximale, alors que dans inc-vide il choisissait la fusion
maximale. Le comportement face au manque n'est pas cohérent.

### Calibration d'incertitude incohérente : inc-sans-temps
Meta fusionne L1 et L2 avec une incertitude de seulement 0,2,
alors que sa justification reconnaît que l'absence totale de temps
« empêche d'exclure formellement deux épisodes successifs
distincts au même point ». Le doute est écrit, mais le score est
faible. L'incertitude Meta ne reflète donc pas fidèlement
l'ambiguïté : 0,2 ici, 1,0 pour inc-sans-lieu, 1,0 pour une fusion
inc-vide. On ne peut pas s'appuyer sur ce score seul pour trier
les cas douteux.

### Distinction réelle : dist-2inc contre dist-1event
C'est le résultat le plus intéressant. Meta ne fusionne PAS à
l'aveugle sur le texte identique : il sépare E1/E2 (7 km, fuite
locale) et fusionne F1/F2 (7 km, coupure générale de réseau), en
pesant explicitement le type d'événement — « par nature réseau
diffusable, peut couvrir une zone large », contrairement à un
événement ponctuel. Les deux décisions sont accompagnées
d'incertitudes élevées (0,6 puis 0,4/0,4 pour dist-2inc ;
0,7 pour dist-1event) et de justifications signalant l'ambiguïté
résiduelle (« impossible de vérifier s'il s'agit du même quartier
en panne étendue ou de deux quartiers distincts »). Le classique
et la baseline, eux, séparent les deux cas par la porte distance
et ratent donc la convention dist-1event. Réserve : un seul
rapprochement par cas (hors répétitions dist-2inc), et la vérité
dist-1event reste une convention, pas une preuve d'inférence.

### Contradictions : préservées, mais score en dessous du seuil
Les trois méthodes fusionnent G1/G2 (F1 1,0). L'agrégation miroir
de incidents.dart donne, pour les trois méthodes, gravité
contradictoire (valeurs [2,4], valeur unique null) et exposition
contradictoire ([0,3], null) — aucune gravité unique inventée.
Le classique et la baseline marquent le groupe incertain pour
écart ≥ 2. Meta, lui, mentionne 3 fois la contradiction dans sa
justification (« aucune valeur unique inventee », « incertitude
maintenue non nulle à 0,3 uniquement en raison des contradictions
non resolues »), mais son incertitude 0,3 passe SOUS le seuil 0,35
de mon marquage « uncertain » : formellement, le groupe Meta n'est
pas marqué incertain. Le texte est bon, le score sous-estime la
contradiction. L'extraction de G1, texte seul, donne
graviteExprimee null — correct, le texte n'exprime aucun chiffre.

### Extractions : aucune invention constatée
- contra-1 G1 : gravité null, localisation « rue basse,
  trottoir » (reprise du texte), temps null.
- inc-vide I1 : problème indéterminé, tout à null.
- inc-sans-lieu K1 : localisation « trottoir » (mot du texte,
  pas un nom de rue inventé), temps null, gravité null.
- inc-sans-temps L1 : localisation null, temps null, gravité null.
Aucune extraction n'a fabriqué un lieu, un temps ou une gravité.

## 8. Variabilité : dist-2inc, 3 sorties identiques

Rapprochement dist-2inc répété 3 fois au total (run 1 + 2
répétitions, même prompt) : les trois sorties séparent E1 et E2.
Décision stable sur ce cas. En revanche, l'incertitude varie :
0,6 au run 1, puis 0,4 aux runs 2 et 3. La décision est stable,
la calibration ne l'est pas. Trois runs ne mesurent pas une
distribution ; ils excluent seulement un basculement systématique
sur ce cas précis.

## 9. Q : non calculé, et pourquoi

Aucun Q n'est calculé pour ces scénarios, délibérément, sans Q
bricolé :
- ces scénarios de paires n'ont ni équipes, ni délais, ni budget
  d'allocation définis ;
- contra-1 n'a pas de gravité ni d'exposition uniques (statut
  contradictoire) ;
- dist-1event n'a pas de localisation unique (deux quartiers) ;
- inc-sans-lieu et inc-sans-temps ont une donnée manquante.
Le script work/q.dart de phase4-dev exige des incidents de vérité
avec gravité, exposition, position et premier passage uniques ;
les fournir ici exigerait d'inventer exactement les valeurs que
cette mission interdit d'inventer. Le Q reste donc celui de
phase4-dev, sur ses propres scénarios, et n'est pas étendu ici.

## 10. Limites, à ne pas dépasser

- 10 paires seulement, 20 signalements, 1 paire par scénario :
  les moyennes 0,50 / 0,90 / 0,80 sont des fractions de paires,
  pas des performances générales.
- Baseline synonymes écrite en connaissant les paires testées :
  son 0,90 n'est pas une validation indépendante.
- Une seule sortie Meta par scénario (sauf dist-2inc, 3 sorties) :
  la variabilité générale n'est pas mesurée.
- dist-1event : la vérité est une convention de modélisation.
- Textes DEV en style mots-clés, sans bruit réel, sans fautes,
  sans photos, sans voix : rien ne dit que ces comportements
  tiennent sur des signalements réels.
- Preuve toujours via le connecteur de Muse uniquement, pas de
  bout en bout dans le serveur CityResolve ; SAM 3.1 non testé ;
  coût monétaire inconnu.

## 11. Conclusion honnête

Sur ce petit jeu difficile, aucune méthode ne domine partout :
le classique échoue sur les 4 synonymes ; la baseline synonymes
réussit 9/10 mais elle a été écrite pour ces cas ; Meta réussit
8/10, avec la seule réussite sur l'événement étendu, mais deux
échecs sur données incomplètes, dont une fusion de textes vides
malgré une incertitude maximale. Le point le plus utile n'est pas
le classement 0,50 / 0,90 / 0,80 : c'est que l'incertitude Meta
ne protège pas, à elle seule, contre une mauvaise fusion, et que
son comportement face au manque oscille entre fusion maximale
(textes vides) et prudence maximale (lieu inconnu). La prochaine
étape utile n'est pas d'ajouter des paires, mais de décider d'un
garde-fou déterministe pour les cas vides ou sans contenu, et de
tester Meta sur des cas où le texte seul est trompeur (même
incident décrit de façon contradictoire, ou incidents distincts
décrits de façon presque identique au même lieu).

## 12. Fichiers livrés

- `RAPPORT_PHASE4_HARD.md` (ce rapport)
- `compare_hard.py` (classique + baseline synonymes + F1)
- `meta_step_hard.py` (appels Meta via le helper du connecteur)
- `data/truth.json` (vérité prédéfinie, écrite avant tout Meta)
- `data/scenarios.json`
- `data/classic_groups.json`, `data/synonym_groups.json`,
  `data/meta_groups.json`, `data/meta_groups_repeat_dist-2inc.json`
- `data/classic_synonym_results.json`, `data/final_f1.json`
- `data/meta_extractions.json`, `data/meta_calls_summary.json`
- `logs/meta_calls.jsonl` (16 appels journalisés, sans clé)
