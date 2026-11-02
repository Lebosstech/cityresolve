# SPECIFICATION D-DEV — Jeux de développement et séparation des ensembles (BROUILLON, NON GELÉ)

> Statut : proposition technique non approuvée, non gelée. Référence : V1.5
> §1.5, §4. Aucun scénario confirmatoire caché créé ni consulté ici.
> Amendement I6 appliqué le 2026-11-02 (pré-edit a865cb280268) ; I7 au §8.

## 1. Données visibles autorisées au développement (DEV)

- DEV = **12 scénarios visibles** (4 par strate : mineurs / mixte / pression),
  même format que A (20 signalements, 8 incidents, 2 équipes), auteurs =
  développeurs, stockés dans le dépôt, versionnés, vérité **visible**.
- La sélection sur DEV est **exploratoire** : DEV sert à construire et
  dégrossir, jamais à prouver. A/B servent uniquement à l'évaluation finale
  préenregistrée.
- Usages autorisés : débogage, sélection des 2 baselines, itérations Meta,
  contrôle de plausibilité de variance (V1.5 §1.9). **Interdit** : toute
  présentation d'un score DEV comme preuve de performance ; tout réglage
  postérieur à un accès, même partiel, aux cachés.

## 2. Données de calibration des paramètres

- Baseline Q (primaire) : grille 3×3×3 (DIST_MAX {100,250,500} m,
  DELTA_T_MAX {1,6,24} h, SIM_MIN {0,65 ; 0,75 ; 0,85}), sélection sur Q
  simulé DEV (simulateur figé). Égalité (ΔQ < 1e-9) : ordre lexicographique
  croissant (rayon, fenêtre, similarité) — déterministe, préenregistré.
- Validation croisée : **4 plis stratifiés** (1 scénario/strate/pli ;
  entraînement 9, validation 3) ; sélection sur Q moyen de validation ;
  écart entraînement/validation publié. **Limites explicites** : n=12, plis
  de 3, variance élevée du Q de validation, instabilité de sélection
  possible ; 4 plis ne prouvent aucune généralisation — d'où le statut
  exploratoire (§1) et l'évaluation finale sur cachés.
- Baseline F1 (secondaire) : même grille, même CV, même règle d'égalité,
  sélection sur F1 DEV. Les deux codes + paramètres + abstentions gelés
  avant cachés.
- Budget de réglage **vérifiable** (par méthode, journal obligatoire) :
  essais (IDs des candidats évalués sur DEV intégral), temps (horloge +
  machine), données consultées (IDs scénarios DEV + usages), paramètres
  gelés (valeurs + hash), ressources (versions de modèles, appels, volumes,
  coûts). Publication côte à côte ; disproportion constatée soumise à
  l'utilisateur avant le run caché (pas de porte automatique, pas
  d'équivalence numérique 27=27 : les natures de réglage diffèrent).
- Contrôle de variance : σ des Δ appariés calculé sur DEV seul, publié avant
  exécution, comparé à la borne de plausibilité 10 points (registre §4) ;
  descriptif, sans porte de sortie ni re-calibrage (IC large à n=12).

## 3. Ensembles confirmatoires cachés A et B (rappel gelé par V1.5)

- A : 30 scénarios, strates 10/10/10, ≥3 contributeurs (≥6 chacun),
  fréquences documentées non représentatives, pas de quota S5.
- B : 40 scénarios, 60 S5 / 60 S4 / 200 S1–S3, ≥10 sans critique, ≥40
  contradictoires annotés. Fréquence artificielle déclarée, jamais fusionné.
- Détention : évaluateur seul ; jamais dans le dépôt ni sur machines de
  développement ; contenus scellés (hash publiés, contenus secrets).

## 4. Mécanismes anti-fuites (7 barrières)

1. Séparation physique : cachés hors dépôt, hors postes dev.
2. Auteurs disjoints : DEV par développeurs, A/B par contributeurs
   indépendants (aucun auteur commun).
3. Antériorité : DEV avant gel ; A/B créés après le gel du protocole.
4. Canal unique : une seule exécution confirmatoire, lots évaluateur.
5. Gel du code : méthodes + paramètres hashés avant l'exécution cachée.
6. Graines disjointes : flux RNG DEV / A / B séparés, consignés.
7. Sanction : tout accès dev au contenu caché (hors sorties de l'exécution)
   invalide le run et est publié comme écart.

## 5. Diversité des scénarios et contributeurs

- Strates A et quotas B (§3) ; sources distinctes = événements et
  municipalités-graines distincts, aucun texte partagé, provenance consignée ;
  DEV miroir des strates (4/4/4). Instructions contributeurs : canevas imposé
  (objet, format, quotas, interdits, exemples), texte final rédigé par
  l'évaluateur, archivé avant génération (OD-DEV-02).

## 6. Parité d'information (procédure par exécution)

- Lots d'entrée bit-à-bit identiques, mêmes estimations accessibles, mêmes
  instants d'injection, même budget temps, même format de sortie (V1.5 §2.3).
  Partition des connaissances : SIMU §12. Check-list de parité signée par
  l'évaluateur à chaque phase ; tout écart = déviation au protocole, run
  invalide.

## 7. Points ouverts de cette spécification

OD-DEV-01 : 12 scénarios DEV et auteurs développeurs (utilisateur).
OD-DEV-02 : canevas d'instructions contributeurs + texte final évaluateur
(utilisateur, puis exécution évaluateur). OD-DEV-03 : règle d'égalité
lexicographique (utilisateur). OD-DEV-04 : procédure CV + cadre budgétaire
(utilisateur).

## 8. Diagnostic divergent regroupement/allocation (I7, descriptif, secondaire)

- Cas « ΔF1>0, ΔQ≈0 » (V1.2 §4) : Spearman des (ΔF1, ΔQ) par scénario sur A,
  proportion ΔF1≥+0,05 avec ΔQ<+2, nuage publié. Aucune condition de succès :
  pur diagnostic anti-masquage (le primaire reste la conjonction F1 ET Q).
