# SPECIFICATION D-SIMU — Simulateur neutre (BROUILLON, NON GELÉ)

> Statut : proposition technique non approuvée, non gelée. Références : V1.5
> §2.2–§2.3, V1.3 §2, V1.2 §3. Aucune validation métier. Aucune valeur
> ci-dessous n'est une mesure réelle.

Étiquettes de source : H = hypothèse expérimentale (choix d'expérience,
approbation utilisateur) ; N = décision normative (validation métier requise) ;
E (donnée empirique vérifiée) : **aucun paramètre ne porte cette étiquette
dans cette version — toutes les valeurs sont supposées, jamais mesurées.**

## 1. Équipes et compétences [N]

Domaines : voirie (chaussée, trottoirs, signalisation), réseaux
(eau, électricité), espaces verts (arbres, parcs). Chaque incident exige un
domaine unique. Équipe 1 : {voirie, espaces verts}. Équipe 2 : {voirie,
réseaux}. Sans croisement : un incident réseaux n'est traitable que par
l'équipe 2. Dépôt unique, point de départ de chaque journée.

## 2. Durées d'intervention [H]

Sur site (minutes) : S1 = 60, S2 = 120, S3 = 240, S4 = 180. Multiplicateur
caché par incident ∈ {0,8 ; 1,0 ; 1,25}, tiré par le contributeur, consigné
en vérité, invisible des méthodes. Estimations accessibles = tables de cette
spécification, identiques des deux côtés.

## 3. Déplacements [H]

Grille 5×5 km, distance Manhattan, vitesse 20 km/h (3 min/km), départ dépôt.
Fermetures de routes (T5) = arêtes retirées du graphe, notifiées via injection.

## 4. Coûts et budget [N]

Taux horaire sur site : 10 unités/h tous domaines. Déplacement : 2 unités/km.
Budget : 120 unités par scénario (convention V1.3). Rationnel de calibrage
[H] : 120 ≈ 3 équivalents-S3 + déplacements → sous-ensemble faisable seul,
Q discriminant ; calibrage métier restant ouvert (OD-SIMU-03).

## 5. Disponibilités [N]

Équipes 08:00–16:00 chaque jour, horizon 14 jours calendaires, arrivées des
signalements jours 1–7 aux heures de service (repris V1.3, conventionnel).

## 6. Échéances [N]

Depuis la première arrivée du signalement de l'incident (chronologie vérité) :
S1 = 7 j, S2 = 72 h, S3 = 24 h, S4 = 4 h. S5 : pas d'échéance, escalade
immédiate, jamais planifié (V1.5).

## 7. Faisabilité (6 conditions cumulatives)

Plan faisable ssi chaque intervention planifiée respecte : (1) compétence de
l'équipe ; (2) fenêtres de disponibilité ; (3) achèvement avant échéance
(déplacements + file inclus) ; (4) coût cumulé ≤ budget ; (5) pas de
chevauchement par équipe (tâche + trajets) ; (6) aucun S5 planifié. Violation
→ Q=0 du plan + comptage d'infaisabilité (V1.5 §3).

## 8. Terminaison d'une intervention simulée (R_i)

R_i = 1 ssi, selon le simulateur figé et les attributs cachés : équipe
compétente, démarrage compatible, fin (début + durée vraie) avant échéance,
coût imputé. Sinon 0. Pas de crédit partiel (binaire, V1.1). Les durées et
coûts vrais servent à noter ; les estimations servent à planifier.

## 9. Robustesse +20 % / +50 %

6 runs : durées vraies ×1,2 / ×1,5 seules, coûts vrais ×1,2 / ×1,5 seuls,
ensemble ×1,2 / ×1,5. **Plans figés, réévaluation seule, aucune
réoptimisation** (question : les plans survivent-ils à une réalité
pessimiste ?). Publiés par variante : taux d'infaisabilité, Q, changement de
classement. Interprétation (PROPOSITION) : tout changement de classement =
fragilité publiée, sans porte de décision (OD-SIMU-04).

## 10. Neutralité (exigences opposables au code de l'étape 1)

Code simulateur unique et partagé, aucune branche selon la méthode (contrôle
d'acceptation étape 1 : recherche des noms de méthodes dans le code simu =
0 occurrence) ; optimiseur unique, hyperparamètres gelés, même budget temps
(D-TEMPS), mêmes départages, déterminisme à graine fixée.

## 11. Paramètres arbitraires identifiés (tous [H] ou [N], aucun [E])

OD-SIMU-01 matrice de compétences §1 (N). OD-SIMU-02 table des durées +
multiplicateurs + vitesse 20 km/h (H). OD-SIMU-03 taux 10/h, 2/km, budget
120 (N). OD-SIMU-04 règle d'interprétation robustesse (utilisateur).
OD-SIMU-05 horizons et horaires §5 (N). OD-SIMU-06 échéances §6 (N).
OD-SIMU-07 schéma estimations = tables / vérité = tables × multiplicateur (H).
