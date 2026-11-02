# SPECIFICATION D-C6 — Plan d'injection d'information nouvelle (BROUILLON, NON GELÉ)

> Statut : proposition technique non approuvée, non gelée. Références : V1.5
> §1.6, PROTOCOLE §3.6, ANNEXE V1.1 §3, V1.3 §1. Aucune validation métier.
> Aucun essai confirmatoire. La vérité terrain n'est jamais déterminée à
> partir d'une sortie de méthode (voir §5).
> Amendements I1–I4 appliqués le 2026-11-02 (pré-edit 9204507d2ba0).

## 1. Types d'injection (un seul type par injection, §6)

| ID | Type | Contenu | Effet sur la vérité terrain |
|---|---|---|---|
| T1 | Signalement complémentaire | nouveaux signalements d'un incident connu | attributs affinés, groupes enrichis |
| T2 | Incident nouveau | signalements d'un incident sans antériorité | 8 incidents toujours, un révélé tard |
| T3 | Correction / annulation | rectification ou retrait d'un signalement antérieur | attributs modifiés ou supprimés |
| T4 | Reclassification de gravité | passage S↔S' décidé par l'évaluateur | délais et poids w_i modifiés |
| T5 | Changement de ressource | indisponibilité d'équipe, budget amputé, route coupée | faisabilité réduite |
| T6 | Signalement contradictoire | rapport incompatible avec l'état reconstitué | cas C7 en dynamique, classe annotée |

## 2. Calendrier exact et protocole de phases

- Instants d'injection (temps simulé, heures de service) : **t1 = J+2 12:00**,
  **t2 = J+4 09:00** (J = début du scénario). Proposition normative, à valider.
- Invariants conservés : 20 signalements et 8 incidents par scénario ; les
  signalements injectés (T1–T4, T6) font partie des 20 et portent une heure
  d'arrivée > t concerné ; T5 n'est pas un signalement.
- Phases : P0 (visible : arrivées ≤ t1) → plan initial ; P1 (≤ t2) → plan
  révisé ou « inchangé » ; P2 (tout) → plan révisé ou « inchangé ».
- Notification identique aux deux méthodes : même lot, même instant, même
  format (V1.5 §2.3). Budget de temps identique par soumission de plan
  (D-TEMPS s'applique à chaque phase). Aucune information entre phases.

## 3. Cas où le plan doit changer (nécessaire, verdict oracle §5)

- N1 : le plan antérieur devient **infaisable** selon le modèle décisionnel
  figé (observables + estimations accessibles + optimiseur commun) **ET une
  modification réalisable existe** → révision matérielle exigée.
- N1b : plan antérieur infaisable **sans alternative réalisable** → correct =
  **signalement d'infaisabilité motivé, sans réaffectation** (replanifier sans
  base = FP ; ne rien signaler = FN_report, descriptif).
- N2 : le plan oracle-décisionnel optimal (informations disponibles, jamais la
  vérité cachée) gagne **≥5 points Q** vs plan antérieur → révision exigée.
- N3 : l'injection révèle en vérité un S4/S5 : S5 → **escalade exigée**,
  scorée au §7 et jamais en replanification ; S4 → N1/N1b/N2.

## 4. Cas où le plan doit rester inchangé (non nécessaire, verdict oracle §5)

- U1 : injection redondante (doublon, confirmation) : ancien plan faisable
  et gain oracle-décisionnel < 5 points.
- U2 : reclassification sans effet sur les priorités ni la faisabilité.
- U3 : signalement d'un incident déjà couvert, sans changement de faisabilité.
- U4 : changement de ressource avec marge (route non utilisée, équipe de
  réserve) : ancien plan faisable et gain oracle-décisionnel < 5 points.

## 5. Oracle indépendant (formalisme V / P* / P̂ / R, sans circularité)

- **V** : vérité terrain indépendante, scellée avant exécution.
- **P*_dec** : plan optimal selon les informations disponibles à l'instant
  (observables + estimations + règles figées) = seule référence des verdicts.
- **P*_retro** : optimum à connaissance complète (V) = référence descriptive
  (regret) uniquement, jamais un verdict.
- **P̂_m** : plan proposé par la méthode m avec les informations disponibles.
- **R** : résultat obtenu dans le simulateur figé (SIMU §8).
- L'oracle = **l'optimiseur commun + un adaptateur** (observables scellés,
  estimations figées). Entrées : lots observables, estimations, P̂ antérieur
  loggé. **Interdits dans les verdicts** : multiplicateurs, durées et coûts
  vrais, groupes vrais, contenu des injections futures. Un système n'est
  jamais pénalisé pour une information future inaccessible au moment de
  décider. La décision de révision testée n'entre jamais dans le verdict.
  Aucune sortie de CityResolve ni de la baseline ne sert à établir V ou la
  règle.
- Ordre : V, lots et codes oracle scellés (hash) avant exécution ; P̂
  journalisés immuables ; verdicts calculés après, rejouables à l'identique.
  Le contrôleur (C3) atteste l'antériorité des scellés.

## 6. Révisions correctes et injustifiées (calcul)

- Changement matériel : sélection, affectation ou ordre modifiant les
  échéances. Cosmétique exclu : purs décalages horaires < 30 min sans
  changement d'ordre ni d'affectation (seuil normatif, à valider).
- Par événement REPLAN (§8) : nécessaire ? × révisé matériellement ? → TP
  (révisé si nécessaire), FN (inchangé si nécessaire), FP (révisé si non
  nécessaire), TN (inchangé si non nécessaire). N1b : correct = signalement
  sans réaffectation (compté à part, descriptif).
- Taux : rappel_nécessaire = TP/(TP+FN) ; taux_FP = FP/(FP+TN) ; publiés
  globaux et par type T1–T6, par méthode et poolés (§8). Injections à cause
  unique : les injections mixtes sont interdites (attribution propre).

## 7. Urgences S5 (indicateurs d'escalade exclusifs, jamais de replanification)

- Une occasion révélant un S5 exige une **escalade immédiate**, jamais une
  réaffectation : toute réaffectation = FP. Une **escalade correcte n'est
  jamais une erreur** (ni FP ni FN de replanification). Escalade omise =
  omission de détection (critères B si scénario B ; descriptif si A).
- Rappel_escalade_S5 = occasions escaladées / occasions S5, par méthode ;
  publié séparément, jamais fusionné aux critères B statiques ni aux taux §6.

## 8. Couverture et équilibre préenregistrés

- 30 scénarios × 2 occasions (t1, t2) = **60 occasions**. Typées par le plan
  de couverture scellé : REPLAN (60−K) ou ESCALADE (K = occasions révélant
  un S5, documenté sans quota). REPLAN : nécessaires/stables au plus
  équilibré, nombres exacts scellés.
- Décisions-méthodes **appariées et dépendantes** : 2 méthodes × 60 occasions
  = 120 décisions, grappes = scénarios, occasions séquentielles P0→P1→P2.
  Taux secondaires ; tout IC par bootstrap de grappes (scénario).
- Cohérence quotas/dénominateurs : couverture ≥6/type T1–T6 sur occasions
  REPLAN → 36 ≤ 60−K, vérifié par le contrôleur pré-exécution ; dénominateurs
  effectifs (replan, escalade) publiés depuis le plan scellé.
- Hypothèse [H] non obligatoire (OD-C6-06) : cibler échéance > t_inj + 2h
  pour les nécessaires ; écarts autorisés et enregistrés.
- Ensemble B : **aucune injection** (objet = détection/escalade statique).
- Statut des taux (PROPOSITION, à valider) : **secondaires, hors conjonction
  primaire** — Q capte déjà les conséquences d'une mauvaise révision ; les
  taux diagnostiquent le comportement. Seuils d'interprétation candidats
  (descriptifs) : rappel ≥80 %, taux_FP ≤20 %.

## 9. Points ouverts de cette spécification

OD-C6-01 instants t1/t2 et 30/30 (utilisateur) ; OD-C6-02 seuil N2 = 5 points
(métier) ; OD-C6-03 seuil cosmétique 30 min (métier) ; OD-C6-04 statut
secondaire des taux + seuils 80/20 (métier) ; OD-C6-05 plan de couverture
(évaluateur, avant génération) ; OD-C6-06 marge 2h comme hypothèse (utilisateur).
Seuils repris de V1.3/V1.5, jamais ajustés après résultats.
