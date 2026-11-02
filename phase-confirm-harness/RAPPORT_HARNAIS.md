# Rapport du harnais d'évaluation confirmatoire — test du harnais uniquement

Statut : protocole TOUJOURS NON GELÉ. Ceci est un test du harnais,
pas une évaluation confirmatoire, pas une preuve de Niveau 3.
Aucun résultat DEV ci-dessous ne doit être présenté comme
confirmatoire. Aucun appel Meta n'a été fait dans cette mission.
Aucune clé n'a été lue, copiée ou journalisée. Aucun appel Atlas
n'a été fait. Rien n'a été poussé sur GitHub, rien n'a été envoyé
à ChatGPT. Travail uniquement dans phase-confirm-harness/.

## 1. Ce qui a été construit

- confirm_harness.py, version 0.1.0-dev-harness-only.
- Entrée : un dossier de scénarios au format vérité-écrite-avant,
  même structure que phase4-multi-split/data/truth.json, avec
  incidents vrais, signalements implicites par sous-signalements,
  et règle de comptage explicite obligatoire.
- Sorties calculées sans ambiguïté : nombre d'incidents produits,
  survie du secondaire, couverture exacte, F1 adapté avec sa limite
  documentée, violations de contraintes, critiques manqués
  (regroupement et escalade séparés), Q planifié et Q simulé avec
  la formule inchangée de l'annexe V1.1 (w = 0,65 × (S/4) +
  0,35 × (E/4), S5 exclu de Q), gain absolu et intervalle de
  confiance normal (indicatif pour petit n), gain relatif avec
  la réserve « indéfini si référence nulle ».
- Refus : le harnais refuse de tourner (code 2, aucune sortie
  écrite, refus journalisé) si truth_created_utc est absent ou
  illisible, si created_utc d'une prédiction est absent ou
  illisible, si la vérité n'est pas strictement antérieure à la
  prédiction, ou si counting_rule est absente.
- Journalisation : chaque exécution, y compris chaque refus, est
  ajoutée dans logs/runs.jsonl avec version du harnais, hash
  SHA-256 de la vérité, hash des prédictions, hash du fichier
  de résultats, agrégats et gain apparié.
- Interface Meta prévue sans appel : une prédiction Meta fournie
  plus tard devra porter un journal meta_calls au format
  meta_calls.jsonl déjà utilisé (une ligne JSON par appel, avec
  modèle, scénario et usage). Cette mission n'a lu ni produit
  aucun journal Meta.
- Options de sensibilité : --sensitivity recalcule Q sous les
  5 paires de poids préenregistrées (100/0, 80/20, 65/35, 50/50,
  0/100), sans toucher à la politique principale. --cost-stress
  recalcule les dépassements de budget sous un multiplicateur
  de coût, sans toucher au résultat d'origine.

## 2. Auto-test 1 : multi-split DEV, classique contre classique-split

Commande :

```text
python3 confirm_harness.py --truth test_dev/multi_split_dev/truth.json \
  --predictions test_dev/multi_split_dev/predictions_classique.json \
  test_dev/multi_split_dev/predictions_classique-split.json \
  --out results/multi_split_dev.json --log logs/runs.jsonl \
  --reference classique
```

Résultats réels, conformes à phase4-multi-split/data/final_f1.json :

| Scénario | classique : n, survie, couverture, F1 | classique-split : n, survie, couverture, F1 |
|---|---|---|
| split-origine (vérité 2) | 1, Non, 0,0, 1,0 | 2, Oui, 1,0, 1,0 |
| split-seul (vérité 2) | 1, Non, 0,0, 1,0 | 2, Oui, 1,0, 1,0 |
| split-faux (vérité 1) | 1, -, 1,0, 1,0 | 1, -, 1,0, 1,0 |
| split-vague (vérité 1) | 1, -, 1,0, 1,0 | 1, -, 1,0, 1,0 |
| split-trois (vérité 3) | 1, Non, 0,0, 1,0 | 3, Oui, 1,0, 1,0 |

Agrégats : classique, 5 incidents produits pour 9 vrais,
couverture moyenne 0,4, survie du secondaire 0,0 sur 3 cas,
F1 moyen 1,0. Classique-split, 9 incidents pour 9 vrais,
couverture moyenne 1,0, survie 1,0 sur 3 cas, F1 moyen 1,0.
Q planifié et Q simulé : null pour les deux méthodes, car ces
scénarios DEV ne définissent ni équipe, ni budget, ni échéance.
Ce null est le comportement correct, pas un échec.

Vérification attendue et obtenue : sans découpage, secondaire
perdu ; avec découpage, secondaire survit ; F1 classique 1,0
malgré la perte du secondaire dans les cas multi-problèmes.
Le harnais retrouve donc les résultats connus, y compris la
démonstration que le F1 adapté seul est trompeur. Cas dégénéré
signalé : pour split-seul, split-faux, split-vague et
split-trois, aucun incident vrai ni produit ne contient de paire
de même famille, donc le F1 1,0 est conventionnel avec zéro
paire (degenerate_no_pairs = true) ; il ne signifie rien seul.

## 3. Auto-test 2 : Q synthétique, gain apparié et sensibilité

Commande avec --reference reference --sensitivity --cost-stress 1.5.
Résultats réels, conformes aux valeurs vérifiées à la main :

- q1 : référence Q = 61,63 (résout A seul, wA 0,6625, wB 0,4125) ;
  méthode Q = 100,00 (résout A et B). Gain 38,37.
- q2 : référence Q = 13,98 (résout D seul, wC 1,0, wD 0,1625) ;
  méthode Q = 86,02 (résout C seul). Gain 72,04.
- Gain absolu moyen : 55,21 points de Q, écart-type 23,81,
  intervalle de confiance 95 % normal [22,21 ; 88,21], n = 2,
  donc indicatif seulement. Gain relatif : 146,04 % par rapport
  à la moyenne de référence 37,80 ; le gain absolu reste la
  mesure principale, le relatif étant trompeur si la référence
  approche zéro.
- Sensibilité poids (moyenne Q, référence / méthode) :
  100/0 : 40,00 / 90,00 ; 80/20 : 38,77 / 91,67 ;
  65/35 : 37,80 / 93,01 ; 50/50 : 36,81 / 94,44 ;
  0/100 : 33,33 / 100,00. Le classement ne change pas dans ce
  cas synthétique, mais la sensibilité est publiée, comme exigé.
- Stress coût ×1,5 : aucun scénario ne dépasse le budget
  (80 × 1,5 = 120, égal au budget 120, pas supérieur). Le
  harnais ne signale un dépassement que si coût > budget.

## 4. Auto-test 3 : critiques synthétiques, S5 et violations

- Bonne méthode : Q simulé 100,00 (S4 résolu, S5 exclu de Q),
  0 violation, 0 critique manqué en escalade.
- Mauvaise méthode : Q simulé 100,00 également (S4 résolu),
  mais 1 violation automatique « S5 dispatched via teams » et
  1 critique manqué en escalade (S5 non escaladé).
- Leçon vérifiée par le harnais : un Q identique ne suffit pas.
  La violation et l'escalade manquée disqualifient le plan,
  même avec un Q maximal.

## 5. Test de refus

Une prédiction horodatée 2025-01-01, donc antérieure à la
vérité 2026-11-02, a été soumise au harnais. Résultat : refus,
code 2, message « truth_created_utc is not strictly before
prediction created_utc », aucun fichier de résultats écrit,
refus journalisé dans logs/runs.jsonl. Le journal contient
4 lignes au total : 3 exécutions réussies et 1 refus.

## 6. Modèle vierge de jeu tenu à l'écart

- held_out_template.json : champs à remplir, aucun jeu réel.
  Hash SHA-256, date de gel, nombre de jeux, provenance
  indépendante, statut jamais-utilisé-en-développement.
- held_out_procedure.md : gel d'abord, préparation indépendante
  ensuite, hash immédiat, sorties horodatées après la vérité,
  ensembles A et B séparés, jamais fusionnés, journalisation
  immuable.
- CHECKLIST_GEL.md : tout ce qui doit être figé avant toute
  évaluation confirmatoire (politique Q, 60 configurations de
  sensibilité, seuils, règles de comptage, cas S5 / vague /
  faux / multi-problème, au moins 30 jeux tenus à l'écart,
  répétitions, référence sémantique vraiment indépendante).

## 7. Ce qui reste bloqué en dehors de cette mission

- Gel du protocole par l'utilisateur : politique Q principale,
  justification du seuil de 10 %, seuil de révision, revue
  métier de la falaise Q, validation des poids 65/35.
- Préparation indépendante des jeux tenus à l'écart : au moins
  30 jeux pour l'ensemble A, par au moins trois contributeurs
  indépendants, plus un ensemble B séparé pour les critiques.
- Référence sémantique vraiment indépendante : le dictionnaire
  actuel a été écrit en connaissant les cas, il ne compte pas
  comme indépendant.
- Vérification serveur Windows du découpage, selon
  docs/SERVER_SPLIT_VERIFICATION.md (split vers 2 incidents,
  plan vers 2 tâches, persistance après redémarrage).
- Premiers appels Atlas : app ID, cluster, base et collections
  non fournis, donc aucune vérification Atlas dans cette mission,
  et le connecteur custom.mongodb n'a pas été touché.
- Répétitions pour la variabilité, à figer avant les essais,
  avec règle de comptage des échecs d'inférence.

## 8. Fichiers créés

- phase-confirm-harness/confirm_harness.py
- phase-confirm-harness/CHECKLIST_GEL.md
- phase-confirm-harness/RAPPORT_HARNAIS.md
- phase-confirm-harness/held_out_template.json
- phase-confirm-harness/held_out_procedure.md
- phase-confirm-harness/test_dev/README.md
- phase-confirm-harness/test_dev/multi_split_dev/truth.json
- phase-confirm-harness/test_dev/multi_split_dev/predictions_classique.json
- phase-confirm-harness/test_dev/multi_split_dev/predictions_classique-split.json
- phase-confirm-harness/test_dev/q_synthetic/truth.json
- phase-confirm-harness/test_dev/q_synthetic/predictions_reference.json
- phase-confirm-harness/test_dev/q_synthetic/predictions_method.json
- phase-confirm-harness/test_dev/critical_synthetic/truth.json
- phase-confirm-harness/test_dev/critical_synthetic/predictions_good.json
- phase-confirm-harness/test_dev/critical_synthetic/predictions_bad.json
- phase-confirm-harness/results/multi_split_dev.json
- phase-confirm-harness/results/q_synthetic.json
- phase-confirm-harness/results/critical_synthetic.json
- phase-confirm-harness/logs/runs.jsonl
