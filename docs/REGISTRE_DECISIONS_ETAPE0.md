# Registre des décisions — Clôture de l'Étape 0 CityResolve (NON GELÉ)

> Document de clôture, pas de gel. Référence courante : `PREENREGISTREMENT_V1.5.md`
> (28254 octets, 2026-11-02). Aucune V1.6 créée. Aucun seuil modifié après un
> résultat (aucun résultat n'existe). Étape 1 non ouverte.

## 1. Registre des décisions

Statuts : TECHNIQUEMENT DÉFINI (spécifié, couvert par le gel global) /
VALIDATION MÉTIER REQUISE (expert externe) / VALIDATION UTILISATEUR REQUISE
(arbitrage humain) / BLOQUANT (spécification manquante, gel impossible).

| ID | Paramètre / problème | Valeur proposée | Justification | Risque si incorrect | Statut |
|---|---|---|---|---|---|
| D-C1 | Omission S4/S5 | zéro omission de détection observée, strict | retour aux sources ; 95 % reste descriptif | 0 trop sévère sur cas ambigus → échec injuste | VALIDATION MÉTIER REQUISE |
| D-C2 | Analyse statistique | bootstrap pairé par scénario, strates contributeurs, pas d'inférence inter-contributeurs | respecte la dépendance intra-scénario | pseudo-réplication si non apparié | TECHNIQUEMENT DÉFINI |
| D-C3 | Exclusions | définies et appliquées avant exécution, contrôleur aveugle, échecs conservés | seule barrière anti-exclusion opportuniste | biais de sélection des scénarios | TECHNIQUEMENT DÉFINI |
| D-C4 | Métrique de regroupement | F1 pairwise macro + règle singleton + conventions dégénérées (§1.1) | poids égal par scénario, cohérent C2 | bruit des petits dénominateurs | VALIDATION MÉTIER REQUISE |
| D-C5 | Sélection des baselines | baseline Q primaire + baseline F1 secondaire, gelées, budgets écrits | aligne sélection et verdict sur Q | avantage indu si sélection sur F1 seul | TECHNIQUEMENT DÉFINI |
| D-C6 | Plan d'injection | chiffré : types, instants, conséquences, matérialité, seuils de révision | rend PROTOCOLE §3.6 testable | révision non mesurable, critère vide | BLOQUANT |
| D-C7 | Seuils de contradictions | candidats 80 % détection / 10 % fusions, exploratoires | proposés par écrit avant évaluation | seuils arbitraires pris pour normes | VALIDATION MÉTIER REQUISE |
| D-C8 | Exposition inconnue | distincte de 0 ; E=4 + robustesse {E=2, intervalle} | protège les cas graves, symétrique | E=4 systématique fausse les poids | VALIDATION MÉTIER REQUISE |
| D-C9 | Seuil de gain conjoint | Δ≥5 ET G≥10 % (si réf >0), IC>0, futilité 5 %/2 pts, provisoire | ferme l'exploitation du ratio près de zéro | barre trop haute → échec forcé | VALIDATION MÉTIER REQUISE |
| D-DEV | Jeux de développement visibles | nombre, origine, auteurs, étanchéité contre A/B | sans eux, sélection baseline non auditable | fuite ou sur-ajustement au dev | BLOQUANT |
| D-SIMU | Distributions simulateur | valeurs V1.5 §2.2 ou convention déclarée | coûts/durées/déplacements gouvernent Q | effet fabriqué par les conventions | BLOQUANT |
| D-AGGR | Format de sortie + agrégateur | proposition V1.5 §2.3 (schéma, codes, groupes mixtes S5) | symétrie des deux branches | agrégateur asymétrique = biais | VALIDATION UTILISATEUR REQUISE |
| D-SENS | Doctrine des 60 configurations | réévaluation en primaire, réoptimisation en secondaire (V1.5 §2.4) | lève l'ambiguïté réévaluer/réoptimiser | verdict sensible non interprétable | VALIDATION UTILISATEUR REQUISE |
| D-TEMPS | Limite de temps optimiseur | 600 s par scénario, même machine consignée (proposition) | budget calcul identique exigé | comparaison faussée par le temps | VALIDATION UTILISATEUR REQUISE |
| D-ROLES | Désignation des 5 rôles | évaluateur, ≥3 contributeurs, contrôleur, tiers, expert (V1.5 §4) | indépendance non délégable à l'agent | conflits d'intérêts, fuites | VALIDATION UTILISATEUR REQUISE |
| D-B | Quotas ensemble B | 40 scénarios, 60/60/200, 40 contradictoires, escalade ≤1 min à ≥95 % | borne ~5 % si 0 omission sur 60 | quotas arbitraires pris pour normes | VALIDATION MÉTIER REQUISE |
| D-Q0 | Sévérité faisabilité | Q=0 à la 1re violation globale + 0 violation sur A | sources : « Violations : 0 » | falaise : micro-violation = plan nul | VALIDATION MÉTIER REQUISE |
| D-PUIS | Puissance n=30 | lecture préenregistrée sur précision + futilité, seuils inchangés (§4) | variance inconnue a priori | étude sous-dimensionnée, §4 | TECHNIQUEMENT DÉFINI |
| D-GIT | Dépôt versionné | initialisation proposée §5, non exécutée | traçabilité du gel exigée | documents non horodatés, gel fragile | VALIDATION UTILISATEUR REQUISE |

### 1.1 Conventions exactes C4, cas dégénérés (définitions, à geler telles quelles)

Univers : les 190 paires non ordonnées de signalements par scénario.
Précision P=TP/(TP+FP), rappel R=TP/(TP+FN), F1=2TP/(2TP+FP+FN).
Règle singleton : tout signalement en abstention est scored comme prédit
négatif sur toutes ses paires. Dégénérescences : 0/0 → 1 pour P, R et F1
(rien à prédire, rien raté) ; méthode sans paire prédite sur paires vraies
existantes → F1=0 ; paires prédites sans paire vraie → F1=0. Macro-moyenne
sur les scénarios A non exclus (C3) ; dénominateur publié.

## 2. Cinq notions à ne jamais confondre (rappel opposable au rapport final)

1. **Amélioration de Q** : le seul succès primaire (allocation simulée,
   D-C9). Un F1 élevé sans gain Q n'est pas un succès.
2. **Qualité du regroupement** : F1 macro ≥0,90 (D-C4). Condition
   intermédiaire, jamais suffisante seule.
3. **Respect des contraintes** : 0 violation sur A (D-Q0). Une violation
   annule le plan (Q=0) et fait échouer le primaire.
4. **Sécurité de l'escalade** : zéro omission de détection S4/S5 sur B
   (D-C1). Une alerte n'est pas une résolution ; zéro omission n'est jamais
   une garantie de sûreté (borne ~5 % publiée).
5. **Impact réel** : NON DÉMONTRÉ par cette étude quoi qu'il arrive. Seul un
   pilote indépendant en conditions réelles pourrait l'établir (PROTOCOLE §7).

## 3. Audit de symétrie : l'évaluation privilégie-t-elle CityResolve ?

| Exigence | État | Verdict |
|---|---|---|
| Mêmes entrées et prétraitements | prétraitement commun spécifié (V1.3 §3 repris V1.5) | défini, gel couvre |
| Mêmes attributs accessibles | mêmes estimations, mêmes cachés, des deux côtés | défini, gel couvre |
| Même agrégateur | proposition V1.5 §2.3 écrite | À VALIDER (D-AGGR) |
| Même optimiseur | code unique, départages écrits, hyperparamètres à geler, temps à fixer | À VALIDER (D-TEMPS) |
| Budget de réglage comparable | grille + égalité écrites côté baseline ; journal requis côté Meta ; dev non spécifié | INCOMPLET (D-DEV) |
| Aucun accès aux vérités cachées | aveuglement des deux branches + oracle de notation étanche + contrôleur aveugle | défini, gel couvre |

Conclusion : aucun avantage artificiel n'est dessiné dans le protocole ;
la garantie n'est complète qu'après validation de D-AGGR et D-TEMPS et
écriture de D-DEV.

## 4. Puissance statistique des 30 scénarios (test apparié, Δ vrai = 5 points Q, α = 0,05 bilatéral)

Méthode : approximation normale, puissance = Φ(Δ√n/σ−1,96), n=30.
Calcul exécuté (outils validés : √30=5,4772, Φ(1,96)=0,9750). Le test réel
sera un bootstrap (puissance asymptotique voisine) ; le t exact à 29 ddl
(seuil 2,045) donnerait des valeurs légèrement inférieures.

| σ des Δ par scénario (points Q) | Puissance pour Δ=5 | Effet min. détectable à 80 % | n requis à 80 % |
|---|---|---|---|
| 3 | 100 % | 1,5 | 3 |
| 5 | 100 % | 2,6 | 8 |
| 7,5 | 95 % | 3,8 | 18 |
| 10 | 78 % | 5,1 | 31 |
| 12,5 | 59 % | 6,4 | 49 |
| 15 | 45 % | 7,7 | 71 |
| 20 | 28 % | 10,2 | 125 |

Lecture : n=30 atteint ~80 % de puissance **si et seulement si** l'écart-type
des différences appariées σ ≲ 10 points Q. Or la règle falaise (Q=0 à la
première violation) fait basculer des scénarios entiers de dizaines de points,
ce qui peut porter σ à 12–20 et la puissance à 28–59 % : **l'étude peut être
sous-dimensionnée, et c'est constaté sans toucher aux seuils.**
Garde-fous préenregistrés : estimation de variance sur le seul dev visible
avant exécution (plausibilité, jamais sur les cachés), publication de la
largeur d'IC observée, règle de futilité (D-C9). La conjonction (F1, 0
violation, B) abaisse en outre la probabilité de succès global sous la
puissance du seul test sur Δ. Sur B : 0 omission sur 60 événements borne le
taux à ~5 % (3/60, indépendance supposée ; dépendance intra-scénario à publier).

## 5. Dépôt Git : état et proposition (non exécutée)

- État vérifié : aucun dépôt (`.git` absent), `git 2.56.0` disponible,
  dépôt actuel = documents seuls, **aucune valeur de secret** (balayage §7).
- Proposition, à approuver explicitement avant exécution :
  `git init -b main`, `.gitignore` (`.env`, `*key*`, `*credential*`,
  `*token*`, `__pycache__/`, `.venv/`), `git add docs .gitignore`,
  premier commit « Étape 0 CityResolve : préenregistrement V1.5 (brouillon,
  non gelé) + registre de clôture », puis tag `etape0-brouillon`.
  Le commit de gel, lui, interviendra après validation avec empreintes.

## 6. Blocages réels et recommandation

**Seuls blocages réels (spécifications manquantes, gel impossible sans elles) :**

- D-C6 : plan d'injection chiffré (types, instants, conséquences,
  matérialité, seuils de révision).
- D-DEV : spécification des jeux de développement visibles.
- D-SIMU : valeurs des distributions du simulateur (ou convention déclarée).

Approbations en attente (propositions écrites, non validées) : métier —
D-C1, D-C4, D-C7, D-C8, D-C9, D-B, D-Q0 ; utilisateur —
D-AGGR, D-SENS, D-TEMPS, D-ROLES, D-GIT.

**Recommandation motivée : NON PRÊT POUR GEL.** Trois spécifications
manquent, aucune validation métier n'est obtenue (aucun expert désigné),
cinq arbitrages utilisateur pendent, et la puissance à n=30 n'est garantie
que sous σ ≲ 10 points — condition invérifiable avant le dev visible.
Chemin vers le gel : écrire D-C6/D-DEV/D-SIMU → revue métier → arbitrage
utilisateur → mention explicite de gel avec empreintes.

## 7. Contrôles réellement exécutés

1. Table de puissance calculée par script (Newton + Taylor + Abramowitz-Stegun,
   arithmétique de base, mode contraint) ; contrôles √30 et Φ(1,96) conformes.
2. État Git vérifié (`.git` absent, git présent) ; Python absent (calcul en
   PowerShell) ; aucune mutation Git effectuée.
3. Balayage anti-secrets sur `docs/` (motifs api-key/secret/password/token/
   credential, clef privée) : 5 lignes trouvées, toutes dans ce registre et
   toutes auto-référentielles (motifs `.gitignore` proposés au §5 et
   description du présent contrôle). Aucune valeur de secret dans le dépôt.
4. V1.5 et références non modifiés (tailles et contenus intacts, lecture
   seule) ; seul fichier créé : ce registre.
5. Aucun test confirmatoire, aucun scénario caché, aucun seuil modifié.

| Date | Acteur | Événement |
|---|---|---|
| 2026-11-02 | Humain | Consolidation V1.5 validée (démarche), gel refusé, clôture demandée. |
| 2026-11-02 | Muse | Registre de clôture créé. Recommandation : NON PRÊT POUR GEL. |
