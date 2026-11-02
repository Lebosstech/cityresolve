# SPECIFICATION D-C6 — Plan d'injection d'information nouvelle (BROUILLON, NON GELÉ)

> Statut : proposition technique non approuvée, non gelée. Références : V1.5
> §1.6, PROTOCOLE §3.6, ANNEXE V1.1 §3, V1.3 §1. Aucune validation métier.
> Aucun essai confirmatoire. La vérité terrain n'est jamais déterminée à
> partir d'une sortie de méthode (voir §8).

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

- N1 : le plan antérieur de la méthode devient **infaisable** sous la vérité
  mise à jour (délai, budget, compétence, disponibilité, graphe).
- N2 : le plan oracle-optimal sur la vérité mise à jour gagne **≥5 points Q**
  par rapport au plan antérieur évalué sur cette même vérité.
- N3 : l'injection révèle en vérité un S4/S5 : S5 → **escalade exigée** ;
  S4 → réplanification si N1 ou N2 tient, sinon escalade du non-réalisable.

## 4. Cas où le plan doit rester inchangé (non nécessaire, verdict oracle §5)

- U1 : injection redondante (doublon, confirmation) : ancien plan faisable
  et gain oracle < 5 points.
- U2 : reclassification sans effet sur les priorités ni la faisabilité.
- U3 : signalement d'un incident déjà couvert, sans changement de faisabilité.
- U4 : changement de ressource avec marge (route non utilisée, équipe de
  réserve) : ancien plan faisable et gain oracle < 5 points.

## 5. Oracle indépendant (détermination de la bonne décision, sans circularité)

- L'oracle = **l'optimiseur commun + un adaptateur de vérité** (code
  versionné, gelé avant les cachés). Entrées : vérité scellée avant/après,
  plan antérieur loggé de la méthode jugée. Sorties : nécessaire ? (N1/N2/N3
  ou U1–U4) + code motif. La **décision de révision testée n'entre jamais**
  dans le verdict : la nécessité se juge contre le plan antérieur, pas contre
  la réponse. Aucune sortie de CityResolve ni de la baseline ne sert à établir
  la vérité ou la règle.
- Ordre : vérité et codes oracle scellés (hash) avant exécution ; plans
  antérieurs journalisés immuables ; verdicts calculés après, rejouables à
  l'identique. Le contrôleur (C3) atteste l'antériorité des scellés.

## 6. Révisions correctes et injustifiées (calcul)

- Changement matériel : sélection, affectation ou ordre modifiant les
  échéances. Cosmétique exclu : purs décalages horaires < 30 min sans
  changement d'ordre ni d'affectation (seuil normatif, à valider).
- Par événement : nécessaire ? × révisé matériellement ? → TP (révisé si
  nécessaire), FN (inchangé si nécessaire), FP (révisé si non nécessaire),
  TN (inchangé si non nécessaire).
- Taux : rappel_nécessaire = TP/(TP+FN) ; taux_FP = FP/(FP+TN) ; publiés
  globaux et par type T1–T6. Injections à cause unique : les injections
  mixtes sont interdites (attribution propre).

## 7. Urgences S5 (traitement particulier)

- Une injection révélant un S5 exige une **escalade immédiate**, jamais une
  réaffectation d'équipes. Réaffectation suite à une injection S5 = FP, sauf
  N1/N2 établi indépendamment (impossible ici, cause unique §6 : donc FP
  toujours pour une injection T_S5 pure). Escalade omise = omission de
  détection (critères B si scénario B ; en A : rappel_escalade_S5 descriptif).
- Rappel d'escalade S5 sur injections : publié séparément, jamais fusionné
  aux critères B statiques.

## 8. Couverture et équilibre préenregistrés

- Ensemble A : **30/30 scénarios injectés**, 2 injections chacun (1 nécessaire
  + 1 inutile, ordre tiré par RNG évaluateur, scellé) = 60 + 60 événements.
- Ensemble B : **aucune injection** (objet = détection/escalade statique).
- Couverture minimale par type T1–T6 : ≥6 événements chacun (nécessaires et
  non nécessaires confondus pour T1–T5 ; T6 selon annotation C7). L'évaluateur
  produit le plan de couverture scellé avant génération.
- Statut des taux (PROPOSITION, à valider) : **secondaires, hors conjonction
  primaire** — Q capte déjà les conséquences d'une mauvaise révision ; les
  taux diagnostiquent le comportement. Seuils d'interprétation candidats
  (descriptifs) : rappel ≥80 %, taux_FP ≤20 %.

## 9. Points ouverts de cette spécification

OD-C6-01 instants t1/t2 et 30/30 (utilisateur) ; OD-C6-02 seuil N2 = 5 points
(métier) ; OD-C6-03 seuil cosmétique 30 min (métier) ; OD-C6-04 statut
secondaire des taux + seuils 80/20 (métier) ; OD-C6-05 plan de couverture
(évaluateur, avant génération). Seuil cosmétique et N2 repris de V1.3/V1.5,
jamais ajustés après résultats.
