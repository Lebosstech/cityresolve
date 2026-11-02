# Phase 4 MISLEADING — Textes trompeurs (CityResolve)

Statut : prototype DEV uniquement, données fictives, protocole scientifique
NON GELÉ, aucune formule Q, aucun seuil, aucun protocole modifié.
Rien n'a été poussé sur GitHub, rien n'a été envoyé à ChatGPT.
Dossiers interdits intacts : repo-mirror, phase4-dev, phase4-hard,
patch-e4-lock-app non modifiés (hash miroir grouping.dart vérifié inchangé
après travaux : 7e360ed506c4a037af836756b9d8e103fba2bb60bbf356f43271895d8afb6d74).
Aucune clé lue, copiée ou journalisée (vérifié par grep : aucun motif
de clé, aucune valeur d'authentification dans les fichiers livrés).

## 1. Commandes exactes

```text
cd ~/workspace/cityresolve/phase4-misleading
python3 compare_misleading.py
python3 meta_step_misleading.py
python3 - << 'PY'   # calcul final_f1.json (classique/synonymes/Meta, paires non ordonnées)
```

## 2. Vérité terrain prédéfinie (écrite AVANT tout appel Meta, jamais modifiée)

Hash SHA-256 de `data/truth.json` avant et après les appels Meta :
`3dc6b3544e8cb679db17d78199a0fe6eaf7f9718b77221e91f2d5b73ac84f8e9`
(identique, donc la vérité n'a pas été ajustée aux sorties).

| Scénario | Signalements | Vérité prédéfinie |
|---|---|---|
| contra-resolu | A1 « fuite eau rue basse trottoir sec travaux termines fuite resolue » t=500 ; A2 « fuite eau rue basse trottoir inonde eau coule » t=520, même lieu | Fusionnés, MAIS avec statut contradictoire à vérifier (résolu contre en cours). Une fusion propre, sans drapeau, serait trompeuse. |
| distinct-temps | B1 « nid poule rue lilas chaussee degradee » t=500 ; B2 quasi identique + « important » t=4820, même lieu | Séparés : DEUX nids-de-poule distincts, 3 jours d'intervalle (4320 minutes). Ne pas fusionner malgré le texte. |
| distinct-detail | C1 « nid poule trottoir nord rue lilas » t=500 ; C2 « nid poule trottoir sud rue lilas » t=510, même lieu et temps | Séparés : DEUX incidents distincts, détail discriminant nord/sud. Ne pas fusionner malgré le texte. |
| categorie-contredit | D1 catégorie nid-de-poule, texte « fuite eau rue basse trottoir inonde » ; D2 catégorie fuite-eau, même texte + « canalisation », même lieu et temps | Fusionnés sur le TEXTE : c'est la catégorie déclarée de D1 qui est fausse, avec signalement de l'incohérence catégorie/texte. |
| multi-probleme | E1 « nid poule rue lilas chaussee degradee reverbere eteint » ; E2 « nid poule rue lilas chaussee degradee », même lieu et temps | CONVENTION de regroupement : séparés. E1 contient DEUX problèmes ; le regroupement ne peut pas découper E1, donc fusionner masquerait l'éclairage. Un drapeau multi-problème est requis (non implémenté). Ce n'est pas une affirmation que les deux ne parlent pas du même nid-de-poule. |
| typo-abreviation | F1 « nid poule rue lilas chaussee degradee » ; F2 « ndp rue lilas chaus abim », même lieu et temps | Fusionnés : même nid-de-poule, F2 avec fautes fortes et abréviations. Robustesse sémantique attendue. |

## 3. Méthodes

- CLASSIQUE : miroir fidèle de `grouping.dart` (≤ 250 m, ≤ 6 h, Jaccard ≥ 0,75,
  composantes connexes, jetons longueur > 2).
- SYNONYMES : mêmes portes et seuil, dictionnaire français limité repris de
  phase4-hard (nid/poule/trou → niddepoule, degradee → degrade, etc.), sans
  prétention de couverture générale. Il a été écrit en connaissant le
  vocabulaire de ces scénarios : il n'est donc pas une validation
  indépendante, comme en phase4-hard.
- META : via le helper du connecteur uniquement, modèle muse-spark-1.3,
  prompt système à raisonnement maximal, aucun paramètre reasoning_effort
  inventé (non documenté dans le connecteur). Le listing Meta inclut la
  catégorie déclarée, contrairement au classique (texte/distance/temps
  seuls) : asymétrie connue, qui joue ici en défaveur de Meta sur
  categorie-contredit et en sa faveur nulle part ailleurs.
- F1 par paires NON ordonnées, une paire par scénario (6 paires au total).

## 4. Appels Meta : 8 sur 8 réussis, 0 échec, sous la limite de 30

2 extractions (D1, E1) + 6 rapprochements, modèle confirmé muse-spark-1.3
pour les 8 réponses. Latences : min 8 043 ms, médiane 19 949 ms,
max 29 501 ms, total 158 000 ms. Jetons : prompt 2 878, complétion 27 459
dont 23 400 de raisonnement, total 30 337. Coût monétaire inconnu,
non renvoyé par l'API, non inventé. Journal : `logs/meta_calls.jsonl`.

## 5. Résultats : F1 par scénario et par méthode

| Scénario | Classique | Synonymes | Meta | Groupes Meta (incertitude) |
|---|---|---|---|---|
| contra-resolu | 0,0 (séparés) | 0,0 (séparés) | 0,0 (séparés) | [A1], [A2] (0,3 / 0,3) |
| distinct-temps | 1,0 (séparés) | 1,0 (séparés) | 0,0 (FUSIONNÉS À TORT) | [B1, B2] (0,4) |
| distinct-detail | 1,0 (séparés) | 1,0 (séparés) | 1,0 (séparés) | [C1], [C2] (0,4 / 0,4) |
| categorie-contredit | 1,0 (fusionnés) | 1,0 (fusionnés) | 1,0 (fusionnés) | [D1, D2] (0,2) |
| multi-probleme | 0,0 (fusionnés à tort) | 1,0 (séparés) | 0,0 (FUSIONNÉS À TORT) | [E1, E2] (0,2) |
| typo-abreviation | 0,0 (séparés) | 0,0 (séparés) | 1,0 (fusionnés) | [F1, F2] (0,15) |

Moyenne des F1 par scénario (chaque scénario pèse autant) :
classique 0,50 ; synonymes 0,67 ; Meta 0,50.

F1 agrégé sur les 6 paires (seules les 3 vérités fusionnées fournissent
des paires positives ; une séparation correcte donne TP=0, FP=0, FN=0,
donc elle ne compte pas dans cet agrégat — c'est pourquoi il diffère de
la moyenne par scénario) : classique TP=1, FP=1, FN=2, F1=0,40 ;
synonymes TP=1, FP=0, FN=2, F1=0,50 ; Meta TP=2, FP=2, FN=1, F1=0,57.
Aucun de ces chiffres n'a de portée statistique : 6 paires, une seule
inférence Meta par scénario, variabilité inter-appels non mesurée ici.

## 6. Cas par cas : où chaque méthode a tort, et pourquoi c'est instructif

### (a) contra-resolu — les trois méthodes ratent la vérité, mais pas de la même façon
Classique et synonymes séparent (Jaccard ≈ 0,45 < 0,75) sans rien signaler
sur la contradiction. Meta sépare aussi, mais sa justification signale
explicitement la contradiction d'état « résolu contre en cours » et refuse
la fusion « à l'aveugle », avec incertitude 0,3. Au regard de la vérité
prédéfinie (fusion + statut contradictoire), c'est un échec de F1 pour les
trois. Sur le plan opérationnel, la séparation flaggée de Meta est plus
sûre qu'une fusion propre, mais elle ne résout rien : aucun statut
« même incident, états contradictoires » n'existe dans le regroupement,
donc la contradiction reste une phrase dans une justification, pas un état
exploitable par l'optimiseur. Leçon : il manque un statut de groupe
contradictoire, pas seulement un meilleur score de similarité.

### (b) distinct-temps — LA fusion à tort la plus grave, par Meta
Classique et synonymes séparent correctement grâce à la porte temps
(4320 min > 360 min). Meta fusionne [B1, B2] avec incertitude 0,4, et sa
justification explique l'erreur : « unité temporelle absente des données
donc impossible de dire si délai court ou éloigné », puis « dégradation
persistante pouvant persister dans le temps, ce qui rend plausible qu'un
même incident soit signalé deux fois à 4320 d'écart ». Autrement dit, le
listing Meta ne dit pas que t est en minutes ni que x/y sont en km, donc
le modèle neutralise lui-même le signal temporel au lieu de l'appliquer.
Ce n'est pas seulement un échec sémantique : c'est un défaut de format
d'entrée, corrigeable (indiquer les unités dans le listing), qui doit
être corrigé et retesté avant de conclure que « Meta ignore le temps ».
En l'état, une porte temps déterministe (comme le classique) protège
contre cette fusion ; le modèle seul, non.

### (c) distinct-detail — tout le monde a raison, mais de justesse côté classique
Classique sépare avec Jaccard 0,71 (< 0,75) et synonymes avec 0,67 :
la marge est de 0,04 et 0,08 sous le seuil. Un mot discriminant de plus
ou de moins, et le classique fusionnerait. Meta sépare en respectant
explicitement nord/sud (incertitude 0,4). Ce scénario ne prouve donc pas
la robustesse du classique : il montre un seuil qui passe tout juste.

### (d) categorie-contredit — tout le monde a raison, Meta le mieux documenté
Classique et synonymes fusionnent sur le texte (Jaccard 0,86). Meta
fusionne aussi (incertitude 0,2) et, surtout, l'extraction de D1 suit le
texte et non la catégorie : problème extrait « fuite d'eau ; trottoir
inondé », gravité null (non inventée), avec l'incohérence catégorie/texte
signalée explicitement dans les incertitudes. La catégorie fausse n'a pas
trompé l'extraction. C'est le seul scénario où Meta apporte une
documentation supérieure, pas un meilleur regroupement.

### (e) multi-probleme — fusion à tort par classique et Meta, synonymes corrects
Classique fusionne (Jaccard exactement 0,75, au seuil). Synonymes séparent
(0,71) : la normalisation fait passer sous le seuil, par accident de
seuil plus que par compréhension. Meta fusionne « uniquement au titre du
volet nid-de-poule », avec incertitude 0,2, tout en écrivant lui-même
qu'E1 décrit deux problèmes et que « fusion intégrale impossible sans
réserve ». Au niveau regroupement, le résultat reste une fusion : un seul
groupe, donc un seul incident pour l'optimiseur, et le problème
d'éclairage disparaît du plan malgré la phrase dans la justification.
L'extraction de E1, elle, liste correctement les deux problèmes
(« nid poule ; chaussee degradee ; reverbere eteint ») et signale que la
catégorie ne couvre pas tout le texte. Leçon : l'extraction voit les deux
problèmes, le regroupement les écrase. Il faut un découpage ou un drapeau
multi-problème avant le regroupement, pas après.

### (f) typo-abreviation — seule Meta réussit, et c'est le seul gain sémantique net
Classique et synonymes séparent (Jaccard ≈ 0,25 : « ndp », « chaus »,
« abim » ne recouvrent presque rien). Meta fusionne avec incertitude
0,15, la plus basse de la série, en interprétant les abréviations.
C'est le même type de gain que la fusion synonymes de phase4-dev/phase4-hard,
mais sur un texte dégradé que le dictionnaire de synonymes ne couvre pas.
Gain réel sur ce cas, non généralisable : un seul cas, une seule inférence.

## 7. Incertitudes Meta : elles ne protègent contre aucune des deux fausses fusions
Fausses fusions Meta : distinct-temps incertitude 0,4, multi-probleme
incertitude 0,2. La fusion multi-probleme, la plus dommageable
(disparition d'un problème entier du plan), a l'incertitude la plus basse
après typo-abreviation. La séparation correcte distinct-detail a une
incertitude de 0,4, égale à celle de la fausse fusion distinct-temps.
L'incertitude ne sépare donc pas le bon du mauvais ici : un seuil
d'incertitude n'aurait rien sauvé, et c'est le même enseignement que le
cas inc-vide de phase4-hard (fusion avec incertitude 1,0). Les garde-fous
doivent être déterministes (portes, statuts, découpage), pas des seuils
sur l'incertitude du modèle.

## 8. Pourquoi le Q n'est PAS calculé ici
Comme en phase4-hard pour les scénarios par paires, le Q n'est calculable
proprement avec le code Dart existant que si chaque incident de vérité a
une sévérité, une exposition, une échéance et une localisation uniques
pour l'optimiseur, avec des équipes, un budget et des délais définis.
Ici : (a) la vérité exige un statut contradictoire, non représentable
comme un incident propre ; (e) un seul signalement vaut deux incidents,
donc fusionner ou séparer change le nombre d'incidents lui-même, et
l'optimiseur ne peut pas recevoir « un demi-incident » ; aucun scénario
ne définit d'équipe, de budget ni d'échéance d'allocation. Calculer un Q
obligerait à inventer ces entrées. Le Q est donc volontairement absent,
et le F1 par paires est la seule mesure rapportée.

## 9. Limites, à ne pas dépasser
- 6 scénarios, 12 signalements, 6 paires, une seule inférence Meta par
  scénario : aucune généralisation, aucune significativité statistique.
- Baseline synonymes écrite en connaissant le vocabulaire testé : elle
  n'est pas une validation indépendante.
- Le listing Meta ne précise pas les unités (t en minutes, x/y en km) :
  l'échec distinct-temps est en partie un artefact de ce format, à
  corriger et à retester avant tout jugement définitif sur le temps.
- Aucune répétition : la variabilité inter-appels Meta n'est pas mesurée
  sur ces scénarios (phase4-hard l'avait mesurée sur dist-2inc seulement).
- Aucune preuve serveur bout en bout, aucune image, SAM 3.1 non testé,
  coût monétaire inconnu.
- Les justifications Meta complètes sont dans `logs/meta_calls.jsonl`
  (champ raw_content) et les groupes dans `data/meta_groups.json`.

## 10. Conclusion honnête, sans supériorité scientifique
Sur ces 6 cas trompeurs, aucune méthode ne domine. Classique et synonymes
gagnent sur le temps (porte déterministe) et, pour les synonymes, sur le
multi-problème par accident de seuil. Meta gagne seule sur les
abréviations et documente le mieux la contradiction de catégorie, mais
elle fusionne à tort deux incidents séparés de 3 jours et écrase un
deuxième problème malgré sa propre justification. Le bilan net n'est pas
« Meta est meilleure » ni « le classique suffit » : c'est que les cas
trompeurs exigent des mécanismes déterministes que ni le Jaccard ni le
modèle seul ne fournit — porte temps avec unités explicites, statut de
groupe contradictoire, découpage ou drapeau multi-problème — et que
l'incertitude du modèle ne peut pas servir de garde-fou. La prochaine
étape utile, avant toute nouvelle comparaison, est de corriger le format
du listing (unités explicites) et de spécifier ces trois statuts, puis de
les retester sur ces mêmes scénarios.
