# Préenregistrement CityResolve — V1.5 — BROUILLON (NON GELÉ)

> STATUT : BROUILLON. Ce document n'est PAS gelé et ne vaut PAS approbation.
> Aucune évaluation confirmatoire n'est autorisée. Aucun scénario caché
> n'a été consulté. Aucun résultat expérimental n'existe. Aucune validation
> métier n'a été obtenue ni inventée.

- Version : 1.5-brouillon (intègre les amendements C1–C9 du 2026-11-02)
- Date de rédaction : 2026-11-02
- Rédacteur : Muse, agent de développement CityResolve
- Niveau du projet : 1, Idée.

## 0. Sources et traçabilité

| Document | Rôle | Empreinte SHA-256 relevée |
|---|---|---|
| PROTOCOLE_V1.md | source, §1–§9 | d468db6f…d925, conforme au SHA256SUMS |
| ANNEXE_V1_1.md | source, score et criticité | ce9ec9c5…015fe, conforme |
| ANNEXE_V1_2.md | source, sensibilité et ensembles | 30890e69…7f1497, conforme |
| PREENREGISTREMENT_V1_3_PROPOSITION.md | proposition non approuvée | 32d59d1b…cf5ef8, conforme |
| PREENREGISTREMENT_V1.0.md | historique, 7193 octets | 85f47b57…83073e, intact |
| PREENREGISTREMENT_V1.4.md | audit, 19627 octets | 04a5f7b47…52e739, intact |
| Amendements C1–C9 + exigences | message humain du 2026-11-02 | intégrés ci-dessous, non gelés |

Ni V1.4 ni les références n'ont été modifiés pour produire ce document.
V1.3 reste une proposition non approuvée ; là où les amendements la
contredisent, les amendements priment (tracé en §1 et §6).

## 1. Matrice des amendements C1–C9

Vue synthétique. Le détail (problème, ancienne règle, modification,
justification, risque résiduel) suit en §1.1–§1.9.

| Amendement | Ancienne règle | Modification V1.5 | Risque résiduel |
|---|---|---|---|
| C1 criticité | V1.3 : rappel S4 ≥95 % en seuil | zéro omission de détection S4/S5, strict ; 95 % descriptif | sévérité du 0 strict, voir §1.1 |
| C2 stats | V1.3 : stratification incohérente | bootstrap pairé par scénario, strates fixées ; pas d'inférence inter-contributeurs | n=30, variance inconnue, voir §1.2 |
| C3 exclusions | V1.3 : avant affichage | avant exécution, contrôleur indépendant aveugle | disponibilité du contrôleur, §1.3 |
| C4 regroupement | V1.4 : micro-moyenne recommandée | F1 pairwise moyen par scénario + règle d'abstention explicite | petit dénominateur, §1.4 |
| C5 comparateur | V1.3 : sélection sur F1 | baseline Q (primaire) + baseline F1 (secondaire), gelées | dev visible non spécifié, §1.5 |
| C6 injection | cadre sans plan chiffré | types, instants, conséquences, matérialité ; plan à écrire | plan détaillé manquant, §1.6 |
| C7 contradictions | 40 cas sans métrique | taxonomie, 4 mesures, seuils candidats proposés | seuils non validés métier, §1.7 |
| C8 exposition | clarification orale non spécifiée | E=4 conservateur + imputations de robustesse + exclusion aveugle | conventionnalité de E=4, §1.8 |
| C9 gain | V1.3 : G≥10 % ou Δ≥5 | conjointe Δ≥5 ET G≥10 %, IC>0 ; futilité ; puissance | barre plus haute, §1.9 |

### 1.1 C1 — Criticité : zéro omission de détection, strict

- Problème : V1.3 proposait « rappel S4 ≥95 % » en seuil, en contradiction
  avec PROTOCOLE §4 et ANNEXE V1.1 §3 (« 0 S4/S5 oublié »).
- Ancienne règle : rappel S4 ≥95 % comme seuil de validation (V1.3 §4).
- Modification : le critère strict est **zéro omission observée de
  détection des S4/S5** sur l'ensemble B. Le rappel S4 ≥95 % reste une
  métrique descriptive publiée, pas un seuil de validation. Trois actes
  sont distingués et mesurés séparément : **détection** (signaler S4/S5 à
  partir des signalements), **escalade** (transmettre à l'humain dans le
  délai), **réalisation** (intervention simulée achevée dans les
  contraintes — S4 uniquement, les S5 n'étant jamais dispatchés).
  Définitions : un S4/S5 est « détecté » si au moins un incident reconstitué
  le classe S4/S5 ; « omission de détection » sinon. Zéro omission observée
  est accompagné de la borne supérieure (règle de trois sur le nombre
  effectif d'événements) et n'est **jamais présenté comme une garantie de
  sécurité**.
- Justification : retour à l'exigence des sources ; séparation détection /
  escalade / réalisation évitant d'assimiler une alerte à une résolution
  (ANNEXE V1.1 §1).
- Risque résiduel : le 0 strict sur détection fait échouer le primaire à la
  première omission, y compris sur un cas ambigu annoté S4. Atténuation :
  taxonomie C7 + publication des cas limites + borne d'incertitude.

### 1.2 C2 — Statistiques : scénario apparié, strates fixées, pas d'inférence inter-contributeurs

- Problème : formulation V1.3 « stratifié par contributeur et scénario »
  incohérente ; risque de sur-interpréter 3 contributeurs.
- Ancienne règle : V1.3 §5 (bootstrap 5 000, graine 20261102, stratification
  à corriger) ; correction V1.4 C2.
- Modification : unité statistique principale = **scénario apparié**
  (différence Q_Meta − Q_Ref par scénario). Bootstrap sur ces différences,
  **stratifié par contributeur** (strates fixées avant exécution : les 3+
  contributeurs désignés). Analyses par contributeur publiées séparément +
  **leave-one-contributor-out** systématique. Mention obligatoire : avec
  trois contributeurs, **l'incertitude entre contributeurs n'est pas
  estimée de façon fiable** ; les analyses par contributeur sont des
  contrôles de robustesse, pas une inférence.
- Justification : respecte la dépendance intra-scénario (V1.3 §0) et évite
  la pseudo-réplication ; l'avertissement anti-surinterprétation est
  préenregistré.
- Risque résiduel : n=30, variance de Δ inconnue a priori → largeur d'IC
  imprévisible ; traité par le plan de précision et la futilité (§1.9).

### 1.3 C3 — Exclusions : avant exécution, contrôleur aveugle, tout échec conservé

- Problème : V1.3 autorisait implicitement l'exclusion après examen des
  sorties (« avant affichage des résultats »).
- Ancienne règle : V1.3 §0 ; correction V1.4 C3.
- Modification : les règles d'exclusion d'invalidité (vérité terrain
  impossible, scénario corrompu, Q indéfini) sont **définies par écrit puis
  appliquées avant la première exécution confirmatoire**, par un
  **contrôleur indépendant** sans accès aux sorties des méthodes (§4, rôles).
  Tous les échecs techniques et données manquantes survenus pendant
  l'évaluation sont **conservés dans le rapport** (dénombrement + cause).
  **Aucune exclusion après examen des résultats**, sans exception.
- Justification : seule barrière crédible contre l'exclusion opportuniste ;
  conforme à ANNEXE V1.2 §6 (journalisation immuable).
- Risque résiduel : dépend de la disponibilité réelle d'un contrôleur
  compétent et indépendant (à désigner, §5).

### 1.4 C4 — Regroupement : F1 pairwise moyen par scénario, abstention pénalisée explicitement

- Problème : V1.3 fixait F1 ≥0,90 sans agrégation ; V1.4 recommandait la
  micro-moyenne. L'amendement tranche pour la macro-moyenne.
- Ancienne règle : recommandation V1.4 C4 (micro-moyenne primaire).
  Les sources sont silencieuses sur l'agrégation : pas de contradiction.
- Modification : métrique primaire = **F1 pairwise moyen par scénario**
  (macro-moyenne sur les scénarios évaluables de A), seuil ≥0,90 repris du
  protocole (à valider appliqué à la macro). Règle d'abstention explicite
  (PROPOSITION technique) : tout signalement laissé sans groupe par
  abstention est scored **comme singleton** — ses paires avec ses vrais
  co-référents comptent en faux négatifs, avec les autres en vrais négatifs.
  Publiés en secondaires : F1 global regroupé (micro), précision, rappel,
  B-cubed F1, taux d'abstention des deux méthodes.
- Justification : la macro-moyenne donne un poids égal à chaque scénario,
  cohérent avec l'unité statistique C2 ; la règle singleton rend
  l'abstention pénalisée, mesurable et identique des deux côtés.
- Risque résiduel : dénominateurs par scénario petits (~8–16 paires
  positives) → F1 par scénario bruité ; atténué par la publication micro +
  B-cubed et par le fait que le succès primaire reste d'abord un succès en Q.

### 1.5 C5 — Comparateur : baseline Q primaire + baseline F1 secondaire, budgets documentés

- Problème : sélection baseline sur F1 alors que le primaire est Q (risque 2
  de V1.4) ; budgets de réglage asymétriques possibles.
- Ancienne règle : V1.3 §3 (grille 3×3×3, sélection sur F1 dev visible).
- Modification : **baseline principale sélectionnée sur Q simulé** (dev
  visible, simulateur figé) ; **baseline secondaire sélectionnée sur F1**
  (même grille, même dev). Les deux codes + paramètres + règles
  d'abstention sont **gelés avant les essais cachés**. **Budgets de réglage
  documentés des deux côtés** : grille et règle d'égalité écrites côté
  baseline ; journal des itérations (versions de prompt, nombre d'essais)
  côté Meta. Comparaison primaire contre la baseline Q ; comparaison contre
  la baseline F1 en secondaire. **Aucune sélection de la meilleure baseline
  après observation des résultats cachés** — la hiérarchie primaire /
  secondaire est fixée ici.
- Justification : aligne la métrique de sélection sur l'indicateur décisif ;
  la variante F1 conserve la traçabilité avec V1.3 ; les budgets écrits
  ferment la porte à l'asymétrie d'adaptation au dev.
- Risque résiduel : les jeux de développement visibles restent non spécifiés
  (nombre, origine, auteurs, étanchéité contre A/B) — bloquant pour le gel.

### 1.6 C6 — Injection : cadre complet, plan chiffré à écrire

- Problème : V1.3 définissait l'oracle et la matérialité mais aucun plan
  d'injection (ensembles, nombres, types, calendrier).
- Ancienne règle : V1.3 §1 (oracle +5 points Q, TP/FP/FN).
- Modification : cadre V1.5 — chaque injection spécifie : **type**
  (nouveau signalement, correction/annulation, changement de gravité,
  contrainte nouvelle : équipe indisponible, budget amputé, route coupée),
  **instant d'arrivée** (temps simulé), **conséquence sur la vérité terrain**
  (groupes, délais, faisabilité), **attente** (révision nécessaire ou non,
  établie par l'oracle sans fuite vers les systèmes). Le plan doit contenir
  des cas nécessaires ET non nécessaires, en nombres prééquilibrés fixés à
  l'avance. Critères de modification matérielle repris de V1.3 (sélection,
  affectation, ordre affectant les échéances). Taux de révision correcte et
  injustifiée mesurés séparément. **L'escalade S5 n'est jamais comptée comme
  une réaffectation des équipes.**
- Justification : rend l'exigence PROTOCOLE §3.6 testable et symétrique.
- Risque résiduel : le plan chiffré (combien de scénarios injectés dans A/B,
  quels types, quel calendrier) reste à écrire — gabarit imposé en §5,
  bloquant pour le gel.

### 1.7 C7 — Contradictions : taxonomie annotée, 4 mesures, seuils candidats

- Problème : PROTOCOLE §4 exige la résistance aux contradictoires
  « séparément » ; V1.3 prévoyait 40 cas sans métrique.
- Ancienne règle : V1.3 §4 (40 signalements contradictoires, sans mesure).
- Modification : taxonomie annotée indépendamment (4 classes) :
  (a) informations incompatibles entre signalements du même incident,
  (b) fausses duplications (deux incidents distincts décrits pareil),
  (c) descriptions ambiguës (localisation ou horaire inexploitable),
  (d) observations trompeuses (signalement factuellement faux).
  Quatre mesures rapportées séparément sur A et B : **taux de détection**
  des contradictions, **fusions erronées** impliquant un signalement
  contradictoire, **abstentions correctes**, **conséquence sur Q** (ΔQ avec /
  sans les paires contradictoires, descriptif). Seuils candidats
  (PROPOSITION, non validés, à trancher par le métier avant gel) :
  détection ≥80 %, fusions erronées sur paires contradictoires ≤10 %,
  abstention correcte publiée sans seuil.
- Justification : transforme une exigence vague en protocole mesurable ;
  les seuils sont proposés par écrit avant toute évaluation, ajustement
  ultérieur interdit.
- Risque résiduel : seuils candidats arbitraires (ancrage : cohérence avec
  F1 ≥0,90, pas avec un besoin métier) ; validation métier requise.

### 1.8 C8 — Exposition inconnue : E=4 documenté, robustesse, exclusion aveugle

- Problème : V1.3 prévoyait une « clarification » sans oracle spécifié ;
  risque de fuite de vérité terrain.
- Ancienne règle : V1.3 §0 (clarification puis E=4) ; correction V1.4 C8.
- Modification : distinction **E=0 / E inconnue conservée partout**.
  Règle de décision documentée : **E=4 conservateur, symétrique**, avec
  signalement d'incertitude joint au plan. Robustesse préenregistrée
  (PROPOSITION) : réévaluer sous **E=2 (médiane)** et sous **intervalle
  [0,4]** (Qmin/Qmax) ; un changement de verdict entre imputations est
  publié comme fragilité. Même traitement imposé aux deux méthodes
  (contrôle d'audit : divergence de traitement = écart au protocole).
  Le **score final utilise la vérité terrain indépendante**. Si cette vérité
  est indisponible : **procédure d'exclusion aveugle** (contrôleur C3,
  avant exécution, critères écrits).
- Justification : supprime l'oracle de clarification (fuite potentielle) ;
  E=4 protège les cas graves ; la robustesse aux imputations objective la
  conventionnalité du choix.
- Risque résiduel : E=4 reste conventionnel (non calibré métier) ; la borne
  0 de l'intervalle [0,4] n'est pas un codage d'inconnu à 0 — l'écrire
  explicitement dans le rapport pour éviter tout contresens (voir §6, F4).

### 1.9 C9 — Gain : règle conjointe, puissance, futilité

- Problème : V1.3 appliquait G≥10 % OU Δ≥5 (alternative) ; près d'une
  référence quasi nulle, le gain relatif explose (discontinuité) ; aucune
  règle négative symétrique.
- Ancienne règle : V1.3 §1(a) « G≥10 % si référence positive, sinon Δ≥5 ».
- Modification : règle primaire **conjointe** — (i) **ΔQ ≥5 points ET
  G ≥10 % si Q_référence > 0**, avec (ii) **borne inférieure de l'IC 95 %
  sur ΔQ strictement positive** ; si Q_référence = 0, **seuil absolu seul**
  (ΔQ ≥5 + IC>0), gain relatif non défini et non publié comme nombre.
  Discontinuité documentée : le basculement de règle à Q_ref=0 est assumé ;
  atténuation par publication systématique des deux métriques + IC.
  Plan de puissance/précision (PROPOSITION) : variance de Δ estimée **sur
  le seul dev visible** (jamais sur les cachés) pour publier, avant
  exécution, l'effet minimal détectable à n=30 ; après exécution, publier
  la largeur d'IC observée. Règle de futilité (PROPOSITION, seuils à
  valider) : borne supérieure de l'IC 95 % sur G < 5 % **ET** borne
  supérieure de l'IC 95 % sur Δ < 2 points → conclusion « pas de valeur
  ajoutée démontrée dans la marge préenregistrée ». Formulation imposée :
  **absence de preuve ≠ preuve d'absence** ; le mot « inefficace » est
  interdit, seul le libellé de futilité préenregistré est autorisé.
- Justification : la conjonction ferme l'exploitation du ratio près de zéro ;
  l'IC>0 ajoute l'exigence statistique ; la futilité donne à l'étude le
  pouvoir de conclure négativement dans sa marge (risque 5 de V1.4).
- Risque résiduel : barre **plus haute** que le minimum des sources
  (V1.1 §3 n'exige que G≥10 % + publication de l'absolu) → un succès au sens
  des sources peut échouer au sens V1.5 ; à valider en connaissance de cause
  (voir §6, F1). Seuils de futilité 5 % / 2 points non validés.

## 2. Autres exigences : intégration

### 2.1 Taille de B et quotas critiques : éléments de justification

- Rationnel statistique (vérifiable, non métier) : avec 60 S5 et 0 omission
  observée, la borne supérieure du taux d'omission est d'environ 5 % à 95 %
  de confiance (3/60, observations indépendantes) ; même calcul pour 60 S4.
  Enrichissement artificiel déclaré : 120 critiques sur 320 incidents B
  (37,5 %), réservé au test de résistance, jamais fusionné à A, jamais
  interprété comme une incidence populationnelle. Dépendance intra-scénario :
  la borne 5 % est optimiste si les omissions se concentrent par scénario —
  publier la répartition des omissions par scénario.
- Reste à valider par le métier : le caractère suffisant de 60/60/200, le
  nombre de 40 scénarios B, les 40 cas contradictoires, l'escalade ≤1 minute
  simulée à ≥95 %. Aucune validation de ce type n'est prétendue ici.

### 2.2 Simulateur : distributions à définir (gabarit, valeurs NON inventées)

Le tableau suivant fixe CE qui doit être défini, pas LES valeurs. Chaque
case « À DÉFINIR » exige une valeur + une source (calibration métier ou
convention déclarée) avant le gel.

| Paramètre | Unité | Forme | Valeurs | Source |
|---|---|---|---|---|
| Durée d'intervention par classe S1–S4 | minutes simulées | À DÉFINIR | À DÉFINIR | À DÉFINIR |
| Coût d'intervention par classe | unités fictives | À DÉFINIR | À DÉFINIR | À DÉFINIR |
| Vitesse / temps de déplacement | minutes / distance | À DÉFINIR | À DÉFINIR | À DÉFINIR |
| Graphe de déplacement | — | À DÉFINIR | À DÉFINIR | À DÉFINIR |
| Compétences des 2 équipes | — | À DÉFINIR | À DÉFINIR | À DÉFINIR |
| Budget par scénario | unités fictives | fixe | 120 (convention V1.3, à valider) | convention |
| Horizon / horaires / arrivées | jours / heures | V1.3 §2 | 14 j, 08:00–16:00, arrivées 7 j | convention, à valider |

Exigences : distributions versionnées avec le simulateur ; coûts/durées
réels cachés aux méthodes, mêmes estimations accessibles des deux côtés ;
règles de départage V1.3 (Q, coût, durée, identifiant stable) confirmées
provisoirement ; limite de temps de calcul à chiffrer (§5).

### 2.3 Agrégateur commun et format de sortie identique (PROPOSITION technique)

- Format de sortie imposé aux deux branches, par signalement : `report_id`,
  `group_id` (ou `ABSTAIN`), `confiance` [0,1] (ou `NA` si abstention),
  `motif_abstention` (code fermé, à valider) ; par groupe : `group_id`,
  liste des `report_id`, criticité proposée S1–S5, exposition proposée
  (bande ou `INCONNUE`), attributs d'incident requis par l'optimiseur.
- Agrégateur déterministe commun (PROPOSITION) : (1) valide le schéma et
  rejette tout champ hors format (échec technique consigné, C3) ;
  (2) convertit criticité/exposition proposées en attributs d'incident selon
  des règles écrites identiques (dont E inconnue → E=4, C8) ;
  (3) transmet à l'optimiseur unique sans réordonner ni filtrer selon
  l'origine. L'abstention d'un signalement le rend inéligible au regroupement
  (scored singleton en F1, C4) et l'exclut de l'optimisation (publié à part).
- À valider : codes de motif, règles de conversion criticité→attributs,
  traitement des groupes mixtes S5/non-S5 (proposition : tout groupe
  contenant un proposé-S5 part en revue d'escalade avant optimisation).

### 2.4 Cohérence des 60 configurations de sensibilité (doctrine V1.5, à valider)

Règle explicite par dimension de la grille (poids × gain × révision) :

- Poids {100/0 … 0/100} : **primaire = réévaluation** des plans figés du
  primaire sous chaque pondération (le verdict survit-il ?) ;
  **secondaire = réoptimisation complète** sous chacun des 5 poids
  (le classement survit-il si l'objectif change ?). Les deux séries sont
  publiées ; la primaire ne sélectionne rien après coup.
- Gain minimal {0 %, 5 %, 10 %, 15 %} : seuils de verdict uniquement,
  aucun recalcul de plan.
- Seuil de révision {0, 2, 5} : rejoue **uniquement la logique de révision**
  sur scénarios injectés (déterministe à règle fixée), sans réoptimiser
  les plans initiaux.
- Référence nulle : dans les 60 configurations, G non défini et seuil
  absolu Δ≥5 appliqué tel que figé (§1.9), sans invention de ratio.

### 2.5 Faisabilité et coûts d'exécution baseline contre CityResolve (secondaire)

Mesures publiées par scénario et en moyenne, même matériel, même budget
temps : temps de calcul par méthode (regroupement seul, hors optimiseur
commun), taux de plans faisables, taux d'échecs techniques, coût d'inférence
documenté (appels, volumes — constats, pas d'optimisation post-hoc).
Pas de seuil de validation : descriptif, pour éclairer le coût de la valeur.

## 3. Politique primaire consolidée V1.5 (proposition, NON GELÉE)

Succès primaire = conjonction de :

1. Ensemble A (30 scénarios, Q sur S1–S4) : **ΔQ ≥5 points ET G ≥10 %**
   (si Q_ref > 0 ; sinon absolu seul), **borne inférieure de l'IC 95 %
   sur ΔQ strictement positive** (bootstrap pairé par scénario, stratifié
   par contributeur, 5 000 rééchantillonnages, graine 20261102).
2. Regroupement : **F1 pairwise moyen par scénario ≥0,90** (macro, règle
   singleton pour abstentions), micro-F1, précision, rappel, B-cubed,
   taux d'abstention en secondaires.
3. **0 violation de contrainte observée** sur A ; violation globale → Q=0 du
   plan + comptage séparé.
4. Ensemble B : **zéro omission observée de détection S4/S5**, 0 dispatch
   automatique S5, escalade ≤1 minute simulée à ≥95 %, fausses alertes
   S4/S5 ≤5 % ; rappel S4 ≥95 % descriptif ; bornes d'incertitude publiées ;
   aucune allégation de sûreté réelle.
5. Révision : taux correct et injustifié séparés ; seuils de validation des
   taux à fixer avec le plan C6 (§5).
6. Transparence : 60 configurations intégrales, résultats appariés par
   scénario, analyses par contributeur + leave-one-contributor-out,
  imputations C8, robustesse +20 % / +50 % (6 runs : durées seules, coûts
   seuls, ensemble × 2 niveaux), échecs techniques et données manquantes.

Échec d'un seul point → pas de « supériorité » ; appliquer la règle de
décision à trois conclusions (§1.9 : supériorité / futilité / indéterminé).

## 4. Rôles (fonctions, personnes À DÉSIGNER — aucun nom inventé)

| Rôle | Responsabilité | Indépendance exigée |
|---|---|---|
| Évaluateur principal | détient la vérité terrain, exécute le confirmatoire | ni développeur ni contributeur |
| Contributeurs (≥3) | écrivent les scénarios A/B selon instructions standard | ni développeurs, sans accès aux sorties |
| Contrôleur indépendant | applique les exclusions aveugles (C3, C8), QC vérité | sans accès aux sorties des méthodes |
| Tiers vérificateur | contrôle contradictions de vérité avant verrouillage | n'a pas développé le modèle |
| Expert métier externe | valide les choix normatifs (§5) | indépendant de l'équipe |

## 5. Décisions exigeant encore une approbation humaine ou métier

Normatives (expert métier externe requis, §4) :

- [ ] Conjonction C9 (Δ≥5 ET G≥10 %, IC>0) et seuils de futilité (5 % / 2 pts).
- [ ] F1 macro ≥0,90 + règle singleton ; seuils C7 (80 % / 10 %) ; seuils de
  révision à fixer avec le plan C6.
- [ ] Grille S1–S5, délais simulés, escalade S5, ≤1 minute à ≥95 %, FA ≤5 %.
- [ ] Quotas B (60/60/200, 40 scénarios, 40 contradictoires) suffisants ?
- [ ] Conventions simulateur (table §2.2) : calibrées ou déclarées arbitraires.
- [ ] E=4 conservateur + imputations {E=2, intervalle} acceptables ?
- [ ] Sévérité du 0 strict (violations, omissions) confirmée ?

Techniques (humain, avant gel) :

- [ ] Jeux de développement visibles : nombre, origine, auteurs, étanchéité.
- [ ] Encodeur baseline (nom, version), code baseline Q + baseline F1 gelés.
- [ ] Règle d'égalité de sélection écrite ; budgets de réglage documentés.
- [ ] Format de sortie + agrégateur (§2.3) ; codes de motif ; groupes mixtes S5.
- [ ] Hyperparamètres et limite de temps de l'optimiseur (valeur, machine).
- [ ] Doctrine 60 configurations (§2.4) ; 6 runs de robustesse + règle
  d'interprétation d'un changement de classement.
- [ ] Plan d'injection chiffré C6 ; désignation des 5 rôles (§4).
- [ ] Uniformisation « premier signalement » (retrait de « vérifiable »).

Gel (rappel) : cases tranchées par écrit → mise à jour → mention humaine
explicite → statut GELÉ daté, signé, hashé. Pas de gel partiel.

## 6. Vérification : contradictions internes et conformité aux sources

Divergences relevées entre amendements et sources (signalées, non résolues
silencieusement) :

- F1 — C9 plus stricte que le minimum des sources. ANNEXE V1.1 §3 n'exige
  que G≥10 % (+ publication de l'absolu) ; la conjonction Δ≥5 ET G≥10 %
  ajoute une barre. Ce n'est pas une contradiction logique (un protocole
  peut dépasser son minimum), mais la conséquence est réelle : un résultat
  « succès » au sens des sources peut être « échec » au sens V1.5.
  Statut : à valider en connaissance de cause (§5).
- F2 — C4 macro contre recommandation V1.4 micro. V1.4 n'est qu'un brouillon
  d'audit et les sources sont silencieuses : pas de contradiction avec les
  sources. L'amendement humain tranche. Conséquence : F1 primaire plus
  bruité (petits dénominateurs), compensé par les secondaires.
- F3 — C1 strict contre V1.3 (rappel S4 ≥95 % en seuil). Tranché en faveur
  des sources (PROTOCOLE §4, V1.1 §3). V1.3 est dépassée sur ce point.
  Conséquence : sévérité maximale sur B, atténuée par la transparence.
- F4 — Borne 0 de l'intervalle [0,4] (C8) contre « inconnue jamais 0 »
  (V1.1 §1). Pas une contradiction : une borne d'intervalle n'est pas un
  codage. Conséquence : l'écrire explicitement dans le rapport pour éviter
  tout contresens ; le codage ponctuel reste E=4.
- F5 — V1.3 cite l'annexe V1.1 sous un nom de fichier inexistant
  (CityResolve_annexe_V1_1_score_criticite.md). V1.5 utilise les noms réels
  vérifiés. Sans conséquence de fond.

Conformité par amendement : C1 conforme aux sources (retour au 0) ; C2
conforme (précise V1.3 §5 sans le contredire) ; C3 conforme (durcit V1.3 §0
dans le sens des règles anti-biais) ; C4 compatible (sources silencieuses) ;
C5 conforme (PROTOCOLE §3.5, baseline loyale renforcée) ; C6 conforme
(PROTOCOLE §3.6 rendu testable) ; C7 conforme (PROTOCOLE §4 rendu mesurable) ;
C8 conforme (V1.1 §1 conservé, oracle retiré) ; C9 compatible-stricte (F1).
Cohérence interne : C2⊕C4 (macro-scénario), C3⊕C8 (même contrôleur aveugle),
C5⊕C9 (sélection sur Q, verdict sur Q), C1⊕C7 (cas ambigus annotés, 0 strict
auditable). Aucune contradiction interne détectée.

## 7. Registre et contrôles réellement exécutés

- Fichier créé : `docs/PREENREGISTREMENT_V1.5.md` (ce document).
- Fichiers modifiés : aucun autre (V1.0, V1.4, références intacts).
- Essais confirmatoires : aucun. Scénarios cachés : aucun consulté (aucun
  n'existe dans le dépôt). Résultats : aucun inventé. Validation métier :
  aucune prétendue. Étape 1 : non entamée.
- Contrôles exécutés et résultats : (1) relecture d'ancrage V1.4 par
  recherche (lignes micro-moyenne, futilité, clarification, stratification
  retrouvées) ; (2) empreintes V1.0/V1.4 relevées avant rédaction puis
  recontrôlées après (identiques) ; (3) 5/5 empreintes des références
  recontrôlées conformes au SHA256SUMS ; (4) contrôle automatisé de V1.5 :
  sections C1–C9 et §0–§7 présentes, statut BROUILLON, aucune mention
  « gel validé », aucune allégation de résultat ou de validation métier ;
  (5) revue de conformité amendement-par-amendement contre les sources (§6).
- Limites : pas de dépôt Git détecté (point 2 du README non exécutable sans
  instruction) ; acteurs non désignés ; valeurs métier non validées.

| Date | Acteur | Décision / événement |
|---|---|---|
| 2026-11-02 | Muse | V1.4-brouillon (audit, 04a5f7b4…). |
| 2026-11-02 | Humain | Amendements C1–C9 + exigences, gel refusé. |
| 2026-11-02 | Muse | V1.5-brouillon. En attente de validation humaine. |

