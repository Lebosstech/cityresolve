# Préenregistrement CityResolve — V1.4 consolidée — BROUILLON (NON GELÉ)

> STATUT : BROUILLON. Ce document n'est PAS gelé et ne vaut PAS approbation.
> Aucune évaluation confirmatoire n'est autorisée. Aucun scénario caché
> n'a été consulté. Aucun résultat expérimental n'existe.

- Version : 1.4-brouillon (consolidation de V1.0 et V1.3, non approuvée)
- Date de rédaction : 2026-11-02
- Rédacteur : Muse, agent de développement CityResolve
- Niveau du projet : 1, Idée.

## 0. Sources et intégrité vérifiée

Documents lus intégralement avant toute modification :

| Document | Empreinte SHA-256 | Contrôle |
|---|---|---|
| PROTOCOLE_V1.md | d468db6f…d925 | conforme au SHA256SUMS |
| ANNEXE_V1_1.md | ce9ec9c5…015fe | conforme au SHA256SUMS |
| ANNEXE_V1_2.md | 30890e69…7f1497 | conforme au SHA256SUMS |
| PREENREGISTREMENT_V1_3_PROPOSITION.md | 32d59d1b…cf5ef8 | conforme au SHA256SUMS |
| README_POUR_MUSE.md | bcae5895…5baaf7 | conforme au SHA256SUMS |

- `docs/PREENREGISTREMENT_V1.0.md` : conservé sans modification (historique).
- Les cinq fichiers de `docs/references/` : lus seulement, jamais modifiés.
- Décisions provisoires du message du 2026-11-02 : traitées comme des
  propositions à examiner, pas comme des validations.

## 1. Divergences V1.0 / V1.3

V1.0 était un squelette avec des cases À DÉCIDER (documents absents à
l'époque). V1.3 remplit ces
cases par des propositions détaillées. Le tableau ci-dessous dit, pour chaque
case, si V1.3 la remplit de façon acceptable, discutable ou contradictoire.

| # | Rubrique | V1.0 | V1.3 | Avis V1.4 |
|---|---|---|---|---|
| D1 | Politique primaire | gain absolu ≥ S, S à décider | conjonction : G≥10 % ou Δ≥5, IC>0, F1≥0,90, 0 violation, B satisfait | discutable, voir N1 |
| D2 | Seuil réf nulle | pistes 2 / 5 / autre | Δ≥5 points | repris, justification manquante |
| D3 | Fréquences A | à fournir | 30 scénarios, strates 10/10/10, cumul consigné | repris, justification manquante |
| D4 | Comparateur | gabarit, valeurs à décider | baseline forte sémantique, grille 3×3×3, CV sur F1 visible | discutable, voir N2 |
| D5 | Intervention simulée | définition générique | R_i strict, violation globale → Q=0 | repris, sévérité à valider |
| D6 | Quotas/seuils B | à décider | 40 scénarios, 60 S5 / 60 S4 / 200 S1-S3, seuils chiffrés | contradictoire sur S4, voir N3 |
| D7 | Révision après injection | non couverte | oracle, +5 points, TP/FP/FN, matérialité | repris, plan d'injection manquant |
| D8 | Incertitude stats | non couverte | bootstrap stratifié, graine, leave-one-contributor-out | correction requise, voir N4 |
| D9 | Exclusion Q indéfini | non couverte | consignée avant affichage des résultats | faille, voir N5 |
| D10 | Agrégation du F1 | non couverte | seuil 0,90 sans agrégation précisée | manquant, voir N6 |
| D11 | Jeux de développement | non couverts | mentionnés, non spécifiés | manquant bloquant |
| D12 | Nom de l'annexe V1.1 | ANNEXE_V1_1.md | CityResolve_annexe_V1_1_score_criticite.md | coquille V1.3 à corriger |

Notes détaillées :

- N1 (D1) : la conjonction V1.3 reprend les seuils du protocole (F1≥0,90,
  0 violation, 0 critique oublié) mais en fait des conditions CONJOINTES du
  succès primaire. Conséquence : un gain Q de +15 % avec F1=0,88 serait un
  échec global. C'est un choix normatif défendable (exigeant), mais il doit
  être validé en connaissance de cause, avec une règle de futilité symétrique
  (voir §6). V1.4 conserve la conjonction comme proposition et ajoute la
  règle de futilité manquante.
- N2 (D4) : la baseline V1.3 est réellement compétitive (encodeur sémantique
  fixé, clustering hiérarchique, garde-fous, abstention) — point positif.
  Trois réserves : (a) sélection sur le F1 alors que l'indicateur primaire
  est Q — un comparateur optimal en F1 peut être sous-optimal en Q, ce qui
  avantagerait CityResolve sur le critère qui compte ; (b) règle d'égalité
  de validation croisée dite « déterministe » mais non écrite ; (c) nom et
  version de l'encodeur non fixés. Voir contradiction C5 et choix à valider.
- N3 (D6) : PROTOCOLE §4 et ANNEXE V1.1 §3 exigent « 0 S4/S5 oublié » ; V1.3
  propose « rappel S4 ≥95 % », ce qui tolère jusqu'à 3 omissions sur 60.
  Contradiction directe, voir C1.
- N4 (D8) : « bootstrap apparié stratifié par contributeur et scénario » —
  stratifier par l'unité même de rééchantillonnage (le scénario) n'a pas de
  sens. Correction V1.4 : rééchantillonnage des scénarios, stratifié par
  contributeur. Voir C2.
- N5 (D9) : « exclusion consignée avant affichage des résultats » laisse la
  possibilité d'exclure après avoir vu les sorties. Correction V1.4 :
  exclusion décidée avant l'exécution confirmatoire, sans accès aux sorties.
  Voir C3.
- N6 (D10) : avec 20 signalements pour 8 incidents, le F1 pairwise par
  scénario repose sur un petit dénominateur (de l'ordre de 8 à 16 paires
  positives). Micro-moyenne sur A et macro-moyenne des F1 par scénario
  peuvent diverger. Le choix change le verdict : à trancher, voir C4.

## 2. Examen des cinq risques demandés

### Risque 1 — Le comparateur classique est-il suffisamment compétitif ?

Partiellement. Points forts de V1.3 : similarité sémantique (pas de simples
mots-clés), clustering hiérarchique, garde-fous spatiotemporels, abstention,
grille 27 configurations, gel complet avant les cachés. Lacunes avant gel :
encodeur non nommé, jeux de développement non spécifiés (nombre, origine,
auteurs, indépendance contre A/B), règle d'égalité de validation croisée non
écrite, « même coût de calcul » non chiffré, règles d'abstention promises
mais non écrites, sélection sur F1 plutôt que sur Q (voir risque 2).
Verdict : compétitif sur le papier, pas encore spécifié au point d'être
auditable. Les lacunes listées sont bloquantes pour le gel, pas pour ce
brouillon.

### Risque 2 — La politique de score avantage-t-elle artificiellement CityResolve ?

Un point favorable présumé à CityResolve : la baseline est sélectionnée sur
le F1 de regroupement alors que le succès primaire se joue sur Q. Si F1 et Q
divergent (cas documenté en ANNEXE V1.2 §4 : F1 parfait, allocation
inchangée), la baseline peut arriver sous-optimale sur le critère décisif.
V1.4 exige de trancher : sélection sur Q simulé (dev visible, simulateur
figé) ou sélection sur F1 avec justification écrite.
Points neutres ou défavorables à CityResolve : Q=0 falaise en cas de
violation globale (symétrique par construction, optimiseur commun) ;
abstentions comptées en erreur au primaire (pénalise la branche qui
s'abstient le plus, à publier séparément comme prévu) ; poids 65/35 couverts
par les 60 configurations obligatoires. Aucun de ces points n'offre
d'avantage caché à CityResolve sous réserve que l'abstention de la baseline
soit effective et auditée.

### Risque 3 — Le simulateur peut-il favoriser une des deux méthodes ?

Par construction, non sur l'allocation : même optimiseur, mêmes entrées
agrégées, mêmes contraintes, mêmes estimations accessibles, même limite de
temps de calcul (valeur à chiffrer). Trois zones d'ombre : (a) le format de
sortie exigé des deux branches (ID de groupe, incertitude, refus) et
l'agrégateur déterministe commun ne sont pas spécifiés — un agrégateur qui
traiterait différemment l'incertitude Meta et l'abstention classique
romprait la symétrie ; (b) les conventions non calibrées (horizon 14 jours,
horaires 08:00–16:00, budget 120 unités) peuvent comprimer artificiellement
la variance informative de Q (ex. S4 structurellement non réalisables près
de la fermeture) — neutre entre méthodes mais dangereux pour la puissance ;
(c) la robustesse +20 % / +50 % est prévue mais le nombre exact de runs et
la règle d'interprétation d'un changement de classement manquent.
V1.4 exige la spécification écrite de l'agrégateur, du format de sortie, des
conventions (ou leur déclaration comme arbitraires) et du plan de robustesse.

### Risque 4 — L'indépendance des scénarios cachés est-elle suffisamment garantie ?

Dispositif V1.3 solide sur le papier : au moins 3 contributeurs, 6 scénarios
minimum chacun, instructions standardisées, sources distinctes, ordre
aléatoire, registre versionné avec empreintes, vérification par un tiers,
inaccessibilité jusqu'à l'exécution, aucune itération après résultats,
analyse leave-one-contributor-out. Lacunes : contributeurs et évaluateur
principal non désignés ; « sources distinctes » vague ; jeux de développement
visibles non spécifiés (qui les crée ? quelle étanchéité contre A/B ?) ;
asymétrie d'adaptation au développement possible (prompt Meta librement itéré
contre 27 configurations baseline) sans journal d'itérations exigé ;
hyperparamètres de l'optimiseur commun non mentionnés au gel.
V1.4 exige : désignation des acteurs, spécification du dev visible, journal
des itérations sur dev visible des deux côtés, gel des hyperparamètres de
l'optimiseur, avant tout accès aux cachés.

### Risque 3 — suite : « premier signalement vérifiable » (§1 V1.3) contre
« premier signalement » (§2 V1.3) : uniformiser avant le gel (le qualifier
« vérifiable » n'est défini nulle part).

### Risque 5 — Les métriques permettent-elles de conclure à une absence de valeur ajoutée ?

Non en l'état, mais c'est réparable. V1.3 prévoit une règle de succès
(conjonction stricte) et une transparence totale (60 configurations, résultats
appariés par scénario) qui permettent à un tiers de juger. Il manque la règle
de décision négative symétrique : distinguer « effet indéterminé » (intervalle
de confiance à cheval sur le seuil) de « absence d'effet notable » (borne
supérieure sous un seuil de pertinence). Sans elle, un échec du primaire se
conclut seulement par « preuve non établie », jamais par « pas de valeur
ajoutée démontrée dans la marge ». V1.4 propose au §6 une règle de futilité
préenregistrée (proposition, à valider).

## 3. Contradictions bloquantes (à trancher avant tout gel)

- C1 — S4 oubliés : PROTOCOLE §4 et ANNEXE V1.1 §3 disent « 0 S4/S5 oublié »,
  V1.3 propose « rappel S4 ≥95 % ». Trancher : 0 strict (conforme au
  protocole) ou ≥95 % avec justification écrite et amendement explicite du
  protocole. Recommandation V1.4 : 0 omission S5 observée (conforme), rappel
  S4 à trancher, et dans tous les cas publier numérateurs, dénominateurs et
  intervalles.
- C2 — Bootstrap : corriger « stratifié par contributeur et scénario » en
  « rééchantillonnage des scénarios, stratifié par contributeur » (5 000
  rééchantillonnages, graine 20261102, gelés).
- C3 — Exclusion Q indéfini : remplacer « consignée avant affichage des
  résultats » par « décidée avant l'exécution confirmatoire, sans accès aux
  sorties des systèmes ». Toute exclusion post-exécution est interdite.
- C4 — Agrégation du F1 primaire : trancher micro-moyenne sur l'ensemble A
  contre macro-moyenne des F1 par scénario. Recommandation V1.4 :
  micro-moyenne (paires agrégées sur A) comme primaire, macro-moyenne et
  B-cubed en secondaires — à valider.
- C5 — Métrique de sélection de la baseline : trancher F1 (avec justification
  écrite du lien F1→Q) contre Q simulé sur dev visible avec simulateur figé.
  Recommandation V1.4 : sélection sur Q simulé, F1 en critère secondaire de
  départage — à valider.
- C6 — Plan d'injection manquant : ensemble(s) concerné(s) (A ? B ? les
  deux ?), nombre de scénarios injectés, types d'injections, calendrier,
  prééquilibrage nécessaire/non nécessaire. À écrire avant le gel.
- C7 — Métrique de résistance aux contradictoires manquante : PROTOCOLE §4
  l'exige « séparément », V1.3 prévoit 40 cas sans définir la mesure.
  Proposition V1.4 : taux de fusions erronées impliquant un signalement
  contradictoire, rapporté séparément sur A et B — à valider.
- C8 — Mécanisme de « clarification » pour E inconnue non spécifié : à qui
  demande-t-on ? que révèle la réponse ? Proposition V1.4 : retirer la
  clarification (pas d'oracle en banc simulé), conserver E=4 conservateur
  symétrique avec signalement d'incertitude — à valider.

## 4. Choix restant à valider (porte de validation humaine)

Normatifs (avis métier externe requis) :

- [ ] Politique primaire 65/35, G≥10 % ou Δ≥5 si référence nulle, IC>0,
  F1≥0,90, 0 violation, B satisfait — et justification écrite du 10 %
  (PROTOCOLE §5 l'exige : pourquoi pas 5 ou 20 ?).
- [ ] Règle de futilité proposée au §6 (seuil de pertinence à figer).
- [ ] Délais simulés S1–S4, grille S1–S5 avec notice d'exemples, escalade S5.
- [ ] Conventions simulateur (horizon 14 j, 08:00–16:00, arrivées 7 premiers
  jours, budget 120 unités) : calibrées ou déclarées arbitraires.
- [ ] Quotas B (60 S5 / 60 S4 / 200 S1-S3), 40 scénarios B, 40 cas
  contradictoires, escalade ≤1 minute simulée : justifiés ou déclarés
  conventionnels.
- [ ] Sévérité Q=0 falaise à la première violation globale : confirmer le
  0 strict ou écrire une taxonomie des violations.

Techniques (à figer avant les cachés) :

- [ ] Jeux de développement visibles : nombre, origine, auteurs, étanchéité.
- [ ] Encodeur sémantique : nom, version, gel du code baseline complet.
- [ ] Règle d'égalité de validation croisée écrite ; coût de calcul chiffré
  des deux côtés ; limite de temps de calcul de l'optimiseur (valeur,
  environnement de référence).
- [ ] Format de sortie commun des deux branches + spécification écrite de
  l'agrégateur déterministe ; hyperparamètres de l'optimiseur gelés.
- [ ] Règles d'abstention écrites des deux côtés.
- [ ] Règles de départage de l'optimiseur (reprises V1.3 : Q, coût, durée,
  identifiant stable) confirmées.
- [ ] Plan de robustesse : 6 runs (+20 % / +50 %, durées seules, coûts seuls,
  ensemble) et règle d'interprétation d'un changement de classement.
- [ ] Tranchement C1 à C8 ci-dessus.
- [ ] Désignation : évaluateur principal, au moins 3 contributeurs, tiers
  vérificateur, référent métier externe.
- [ ] Puissance : n=30/40 repris du protocole ; publier les largeurs
  d'intervalle ; à défaut de variance connue a priori, la règle de futilité
  tient lieu de garde-fou contre les conclusions vides.

Procédure de gel (rappel, inchangée) : chaque case tranchée par écrit,
document mis à jour, mention « gel validé » écrite par l'humain, puis statut
GELÉ avec date, valideur et empreinte SHA-256. Pas de gel partiel.

## 5. Politique primaire consolidée V1.4 (proposition, NON GELÉE)

Reprise de V1.3 §1 avec les corrections marquées [V1.4] :

1. Catégories S1–S5 et délais V1.3, uniforme : délais dès le premier
   signalement [V1.4 : « vérifiable » retiré tant que non défini].
   S5 : escalade humaine immédiate, exclue de Q, dispatch automatique
   interdit aux deux équipes.
2. Exposition E en bandes 0–4, personnes distinctes ; inconnue jamais 0 ;
   politique symétrique E=4 conservateur avec signalement d'incertitude
   [V1.4 : clarification retirée, voir C8].
3. Poids w_i = 0,65×(S_i/4) + 0,35×(E_i/4), S1–S4 uniquement.
4. R_i = 1 ssi intervention simulée achevée dans les contraintes avant la
   date limite selon le simulateur figé et la vérité cachée ; sinon 0.
   Violation d'une contrainte globale → Q=0 du plan + comptage séparé de
   l'infaisabilité. S4 non réalisable escaladé ≠ résolu.
5. Q(P) = 100 × Σ(w_i R_i)/Σ(w_i) sur S1–S4 ; Q ∈ [0,100]. Scénario sans
   S1–S4 : Q non défini, réservé à la sécurité ; exclusion décidée avant
   l'exécution, sans accès aux sorties [V1.4 : voir C3].
6. Indicateur : Δ = moyenne par scénario de (Q_Meta − Q_Ref) sur scénarios
   évaluables ; publier Q_Meta, Q_Ref, écarts appariés. G = Δ/moyenne(Q_Ref)
   si référence strictement positive, sinon non défini.
7. Succès primaire (conjonction, à valider) : (a) G≥10 % ou Δ≥5 points si
   référence nulle ; (b) borne inférieure de l'IC 95 % sur Δ strictement
   positive (bootstrap 5 000, graine 20261102, scénarios rééchantillonnés,
   stratifié par contributeur [V1.4 : voir C2]) ; (c) F1 pairwise ≥0,90 en
   micro-moyenne sur A [V1.4 : voir C4], précision/rappel et B-cubed
   secondaires, abstentions en erreur au primaire et publiées à part ;
   (d) 0 violation observée sur A ; (e) critères B satisfaits (rappel S5
   100 % observé, S4 à trancher [V1.4 : voir C1], fausses alertes ≤5 %,
   0 dispatch auto S5, escalade ≤1 min à ≥95 %), sans fusion A/B.
8. Révision après injection : changer si ancien plan infaisable ou si l'oracle
   (vérité du test uniquement, sans fuite vers les systèmes) gagne ≥5 points
   de Q ; S5 = escalade, pas réaffectation mécanique ; TP/FP/FN avec
   matérialité V1.3 ; plan d'injection à écrire [V1.4 : voir C6] ; métrique
   contradictoires séparée [V1.4 : voir C7].
9. Sensibilité : 60 configurations publiées intégralement, politique primaire
   unique, aucune sélection après coup ; robustesse +20 % / +50 % (6 runs,
   règle d'interprétation à figer).

## 6. Règle de décision à trois conclusions (proposition V1.4, à valider)

Pour que l'étude puisse conclure à l'absence de valeur ajoutée (risque 5) :

- Supériorité : toutes les conditions du §5.7 remplies → « supériorité sous
  la politique primaire ».
- Absence d'effet notable (futilité, PROPOSITION) : borne supérieure de l'IC
  95 % sur G strictement inférieure à 5 % ET borne supérieure de l'IC 95 %
  sur Δ strictement inférieure à 2 points → « pas de valeur ajoutée
  démontrée dans la marge préenregistrée ». Seuils 5 % / 2 points à valider.
- Effet indéterminé : tous les autres cas → « preuve non établie ».
- Dans tous les cas : publier les 60 configurations, les résultats appariés,
  les violations, les analyses par contributeur ; recommander l'arrêt ou le
  changement de projet si le primaire échoue, sans retoucher les seuils.

## 7. Registre de travail de cette mission

- Fichier créé : `docs/PREENREGISTREMENT_V1.4.md` (ce document).
- Fichiers sources modifiés : aucun (V1.0 et références intacts).
- Tests confirmatoires lancés : aucun. Scénarios cachés consultés : aucun
  (aucun n'existe dans le dépôt). Résultats inventés : aucun. Appels Meta :
  aucun. Étape 1 : non entamée.
- Vérifications réellement effectuées : lecture intégrale des 6 fichiers de
  références ; contrôle des 5 empreintes SHA-256 (toutes conformes) ;
  contrôle automatisé de la présence des sections et du statut NON GELÉ de
  ce document ; contrôle de non-modification de V1.0 et des références.
- Limites connues : pas de dépôt Git détecté dans E:\cytsense — le point 2
  du README (« enregistrer les références dans Git ») n'a pas été exécuté,
  aucun commit n'étant demandé ; paramètres normatifs non validés par un
  métier ; acteurs (évaluateur, contributeurs, tiers, référent) non désignés.

| Date | Acteur | Décision / événement |
|---|---|---|
| 2026-11-02 | Muse | V1.0-brouillon créée (dépôt vide, références absentes). |
| 2026-11-02 | Humain | Étape 0 confirmée NON GELÉE ; références placées. |
| 2026-11-02 | Muse | V1.4-brouillon consolidée. En attente de validation humaine. |
