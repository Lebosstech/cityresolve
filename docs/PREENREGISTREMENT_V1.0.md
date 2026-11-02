# Préenregistrement CityResolve — V1.0 — BROUILLON (NON GELÉ)

> STATUT : BROUILLON. Ce document n'est PAS gelé.
> Aucune évaluation confirmatoire n'est autorisée tant que le statut n'est
> pas passé à GELÉ par validation humaine explicite (voir §9).

- Version : 1.0-brouillon
- Date de rédaction : 2026-11-02
- Rédacteur : Muse, agent de développement CityResolve
- Niveau du projet : 1, Idée. Aucun résultat expérimental n'existe.

## 0. Sources utilisées (traçabilité stricte)

Seule source disponible : le message de cadrage du 2026-11-02.

| Document | État dans le dépôt E:\cytsense |
|---|---|
| PROTOCOLE_V1.md | ABSENT — vérifié le 2026-11-02 (dépôt vide) |
| Annexe V1.1 | ABSENTE — vérifié le 2026-11-02 (dépôt vide) |
| Annexe V1.2 | ABSENTE — vérifié le 2026-11-02 (dépôt vide) |

Conséquence : tout ce qui n'est pas explicitement dans le message de cadrage
est marqué À DÉCIDER ou À FOURNIR ci-dessous. Aucune valeur manquante n'a
été inventée. Si les trois documents sont fournis, ce brouillon sera aligné
sur eux avant tout gel.

## 1. Hypothèse (formulation provisoire, à confirmer)

Reprise stricte du cadrage, sans extrapolation :

- Entrée : 20 signalements multimodaux.
- Vérité de terrain cachée : 8 incidents, jamais exposés au prototype.
- Moyens : 2 équipes d'intervention simulées.
- Question testée : le regroupement multimodal avec incertitude explicite
  améliore-t-il le score Q par rapport au comparateur classique, à
  optimiseur commun et contraintes strictes identiques ?

Formulation exacte de l'hypothèse du protocole : À FOURNIR (PROTOCOLE_V1.md).

## 2. Politique principale unique (PROPOSITION, à valider)

Proposition, non gelée :

> La politique principale est un succès si, sur l'ensemble A, le gain absolu
> moyen de Q (méthode CityResolve moins comparateur classique, même
> optimiseur commun, contraintes strictes identiques) est supérieur ou égal
> au seuil absolu S (en points de Q, voir §3), avec zéro violation de
> contrainte stricte imputable à la méthode, et sans qu'aucun signalement S5
> n'ait été envoyé en dispatch automatique.

Une seule politique principale. Aucune politique de rechange ne peut être
substituée après avoir vu un résultat.

## 3. Seuil absolu de gain, cas de référence nulle (À DÉCIDER)

- Seuil S (points de Q) : À DÉCIDER par l'humain.
- Cas de référence nulle : À DÉFINIR (PROTOCOLE_V1.md manquant).
  Interprétation provisoire, à confirmer : configuration où le regroupement
  n'apporte aucune information (ex. chaque signalement reste isolé) ; le gain
  attendu y est nul et sert de point zéro de l'échelle.
- Pistes proposées au choix (l'humain tranche, avant tout résultat) :
  - (a) S = 2 points de Q ;
  - (b) S = 5 points de Q ;
  - (c) autre valeur justifiée par écrit dans le journal (§10).

## 4. Fréquences documentées de l'ensemble A (À FOURNIR)

- Fréquences des types de signalements / incidents dans l'ensemble A :
  À FOURNIR (PROTOCOLE_V1.md manquant).
- Règle de séparation rappelée : les ensembles A et B sont évalués
  séparément ; aucun scénario de A ne sert à régler quoi que ce soit pour B,
  et inversement.

## 5. Comparateur classique compétitif (gabarit, valeurs À DÉCIDER)

Le comparateur doit être compétitif et entièrement spécifié avant le gel.
Gabarit repris du cadrage ; chaque valeur numérique est À DÉCIDER :

1. Règles géographiques : regrouper deux signalements si leur distance est
   inférieure à DIST_MAX. DIST_MAX = À DÉCIDER.
2. Règles temporelles : regrouper si l'écart temporel est inférieur à
   DELTA_T_MAX. DELTA_T_MAX = À DÉCIDER.
3. Règles textuelles : regrouper si la similarité textuelle (mesure exacte
   À DÉCIDER, ex. Jaccard sur sac de mots normalisé) dépasse SIM_MIN.
   SIM_MIN = À DÉCIDER.
4. Ressources : 2 équipes, règles d'affectation À DÉCIDER (ex. plus proche
   disponible, file d'attente, préemption interdite/autorisée).
5. Limites explicites du comparateur : À DÉCIDER (ex. pas de refus, pas
   d'incertitude, pas de multimodalité image/audio s'il y a lieu).
6. Combinaison des règles (ET/OU, ordre, seuils de fusion) : À DÉCIDER.

Tant qu'une valeur ci-dessus est À DÉCIDER, le comparateur n'est pas défini
et le gel est impossible.

## 6. Définition de l'intervention simulée (terminologie imposée)

- Le symbole R_i est renommé « intervention simulée achevée dans les
  contraintes ». L'ancien libellé ne doit plus apparaître dans les rapports.
- Définition : une intervention simulée est « achevée dans les contraintes »
  si et seulement si le plan produit par l'optimiseur COMMUN a été exécuté
  jusqu'au bout dans le simulateur sans violer aucune contrainte stricte.
- Interdiction permanente : ne jamais présenter une intervention simulée
  comme une résolution réelle.
- Liste exacte des contraintes strictes : À FOURNIR (Annexe V1.1 manquante).

## 7. Ensemble B : quotas et seuils (À DÉCIDER)

- Quotas de composition de l'ensemble B : À FOURNIR / À DÉCIDER.
- Seuils appliqués sur B (même politique principale qu'en §2, ou seuils
  propres documentés) : À DÉCIDER.
- Rappel : A et B évalués séparément ; les 60 configurations de sensibilité
  conjointe (Annexe V1.2) portent sur les deux ensembles sans les mélanger.

## 8. Règles intangibles reprises du cadrage

1. Criticité S1 à S5 ; tout S5 part en escalade humaine immédiate, hors plan,
   pour les deux méthodes. Aucun S5 en dispatch automatique.
2. Score Q avec poids 65/35. Formule exacte des deux composantes :
   À FOURNIR (Annexe V1.1 manquante).
3. Exposition E en bandes 0 à 4 ; une exposition inconnue n'est jamais
   codée 0. Table des bandes : À FOURNIR (Annexe V1.1 manquante).
4. Contraintes strictes : identiques pour les deux méthodes ; toute
   violation est comptée et publiée.
5. Même optimiseur commun pour les deux méthodes, afin d'isoler la
   contribution du seul regroupement.
6. Sensibilité conjointe : 60 configurations, ensembles A et B séparés.
7. Tous les résultats sont publiés, y compris défavorables. Aucun seuil
   n'est modifié après avoir vu un résultat.
8. Aucune donnée réelle, collectivité partenaire ou résultat ne doit être
   inventé. Aucun accès, direct ou indirect, aux scénarios cachés.

## 9. Procédure de gel (seule voie vers l'évaluation confirmatoire)

1. L'humain fournit les documents manquants ou tranche chaque À DÉCIDER /
   À FOURNIR par écrit.
2. Le brouillon est mis à jour en conséquence, version 1.0.
3. L'humain écrit explicitement « gel validé ».
4. Le statut passe à GELÉ avec date, nom du valideur et empreinte du fichier
   (hash SHA-256 consigné au §10).
5. Seulement après le gel : les étapes 1 à 5 peuvent s'enchaîner ; l'étape 5
   (évaluation confirmatoire) reste interdite avant le gel.

## 10. Journal (vide tant que non validé)

| Date | Acteur | Décision / événement |
|---|---|---|
| 2026-11-02 | Muse | Création du brouillon 1.0-brouillon. Dépôt vide, documents de référence absents. |
| — | — | (en attente de validation humaine) |
