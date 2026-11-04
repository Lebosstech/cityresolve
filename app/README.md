# CityResolve — Bac à sable DEV 0.2.1

Application locale de développement exploratoire.
**Données fictives. Protocole scientifique NON GELÉ. Aucune preuve.**

## Prérequis

- SDK Dart seul, aucune dépendance réseau (`app/pubspec.yaml` vide).
- Vérifié ici : Dart SDK 3.13.7 via le cache Flutter, Windows hors-ligne.

## Lancement

```powershell
cd E:\cytsense\app
dart test/test_all.dart
dart test/test_exploratoire.dart
python test/e2e_redemarrage.py
dart bin/server.dart --port 8080
# puis ouvrir http://127.0.0.1:8080
# port occupé : le serveur l'affiche et s'arrête ; relancer avec --port 8081
```

## Persistance (Phase 1 + MongoDB 0.2.1)

**Base principale : MongoDB local** `mongodb://127.0.0.1:27017/cityresolve_dev`
(pilote `mongo_dart`, collections reports/incidents/plans/teams/simulations/
journals/meta_calls/state, index sur ids, `t`, `(x,y)`, `seq`). Démarrer
MongoDB (lié à 127.0.0.1 uniquement, aucun accès public) :

```powershell
& "C:\Users\brunotanguy\AppData\Local\Temp\opencode\mongo-bin\mongodb-win32-x86_64-windows-7.0.14\bin\mongod.exe" --dbpath "C:\Users\brunotanguy\AppData\Local\MongoDB\data" --bind_ip 127.0.0.1 --port 27017 --logpath "C:\Users\brunotanguy\AppData\Local\MongoDB\mongod.log" --logappend
dart run test/mongo_check.dart
```

Chaque mutation HTTP attend l'écriture Mongo avant de répondre. Aucune
transaction multi-documents (pas de replica set) : document d'état + miroirs
collection par collection. Sauvegarde JSON conservée, lue en repli explicite
si MongoDB est injoignable (`GET /api/db` affiche le backend effectif).
Sauvegarde pré-migration : `app/data/backup-pre-mongo-20261102/`.

État complet également persisté dans `app/data/state.json` : signalements et leurs
sources, groupes/incidents, plans, validations, simulations, appels Meta,
compteurs d'identifiants. Écriture quasi-atomique (tmp -> rotation `.bak` ->
rename, `lib/store.dart`). Identifiants permanents : signalements `M<n>` et
plans `PLAN-<version>` issus de compteurs monotones persistés, jamais
réattribués après redémarrage (vérifié par `test/e2e_redemarrage.py`).

Cohérence journal/état : l'audit JSONL est écrit **avant** l'état (champ
`auditSeq` dans le document). Ce n'est **pas** une opération atomique : un
arrêt brutal entre les deux écritures laisse un écart, détecté au démarrage
et journalisé (`store.reconciled`), reprise journalisée (`server.resumed`).
Ne pas lancer deux serveurs sur le même répertoire `data`.
Supprimer `data/state.json` (+ `.bak`) repart du jouet nº1.

## Données inconnues (Phase 2)

Gravité et exposition ne sont **jamais** déduites de la catégorie.
Chaque attribut d'incident porte valeur + statut (`declaree`, `estimee`,
`contradictoire`, `inconnue`) + valeurs déclarées conservées
(`lib/incidents.dart`). Gravité inconnue ou contradictoire : aucun dispatch
automatique, motif « vérification humaine requise », échéance non fabriquée.
S5 déclaré : escalade humaine, jamais dispatché à aucune équipe.
Regroupements limites signalés : groupes `uncertain` (similarité proche du
seuil, chaînage transitif, gravités contradictoires) et paires
`séparées mais ambiguës` (`ambiguousPairs`). Les signalements manuels restent
opérationnels ; ils sont exclus du F1 faute de vérité, et cette absence est
affichée explicitement (jamais un score fabriqué).

## Page publique + espaces (branche work/public-homepage)

- `/` : page publique réelle (formulaire connecté, carte des incidents,
  signalements récents, suivi par identifiant, à propos). Fidèle à la
  maquette ; héros en illustration SVG (aucune photo de personne) ; vidéo
  et message vocal affichés « Bientôt disponible », désactivés, aucun faux
  téléversement ; GPS désactivé (choix sur la grille fictive uniquement) ;
  carte étiquetée « Carte de démonstration — Données fictives ».
- `/municipal` : interface DEV existante, inchangée fonctionnellement,
  sous écran de connexion quand un jeton est configuré.
- Carte publique : fond OpenStreetMap gratuit (Leaflet 1.9, tuiles OSM
  avec attribution, repli propre hors-ligne). Les positions restent des
  données fictives explicitement étiquetées « projetées » autour d'un
  ancrage de démonstration (Abidjan-Plateau) — jamais présentées comme
  des relevés GPS. Le sélecteur convertit le clic en coordonnées grille.
- GPS navigateur : bouton « Ma position » actif, consentement navigateur,
  refus explicite hors zone démo (3,54 km), refus/absence/délai gérés.
  Relevé stocké (`gpsLat/gpsLon/gpsAccuracy`, validé) et visible
  uniquement sur la fiche de suivi (jamais en liste). Grille x/y inchangée
  pour l'optimiseur.
- Sécurité exposition publique (§6) : `POST /api/reports` et
  `POST /api/photos` limités en fréquence (429 + Retry-After), texte
  1–500 caractères, catégories fermées, 500 signalements max ; tout le
  reste (scénarios, regroupement, plan, simulation, injection, comparaisons,
  journal, Meta, db/state/plans) exige le jeton municipal
  (`CITYRESOLVE_MUNICIPAL_TOKEN`, cookie HttpOnly ou Bearer).
  Sans jeton configuré : mode ouvert documenté (dev local uniquement).
- Changement assumé : `POST /api/reports` ne regroupe plus (un visiteur
  ne doit pas invalider le plan municipal) ; l'interface municipale
  regroupe explicitement. `Report.receivedAt` (ISO-8601 serveur) ajouté.
- Render : ajouter `CITYRESOLVE_MUNICIPAL_TOKEN` (sync: false) dans
  `render.yaml` — fait. Ne jamais déployer sans ce jeton. La clé Meta
  reste côté serveur, jamais exposée au navigateur.

## API (JSON, locale)

Santé/politique : `GET /api/health`, `GET /api/policy`, `GET /api/state`, `GET /api/plans`.
Connecteur IA : `GET /api/meta`, `POST /api/meta/verify` (appel réel GET
`api.llama.com/v1/models`), `POST /api/meta/extract` `{reportId}`,
`GET /api/meta/calls` (modèle, entrées, sorties, erreurs, latence, usage).
Scénarios visibles : `GET /api/scenarios`, `POST /api/scenario/load` `{kind: jouet-1|jouet-s5|dev, seed}`.
Signalements : `GET /api/reports` (municipal), `POST /api/reports`
(public, limité, texte 1–500, catégorie fermée, `receivedAt` serveur,
sans regroupement).
Public : `GET /api/public/reports`, `GET /api/public/reports/<id>` (suivi),
`GET /api/public/incidents` (données filtrées, `fictive: true`).
Public scalable (jamais de chargement complet) :
`POST /api/public/report` (alias canonique de création),
`GET /api/public/reports/recent?limit&cursor` (pagination curseur),
`GET /api/public/incidents/map?bbox&limit` (bbox grille + limite stricte),
`GET /api/public/report/<id>` (suivi canonique),
`GET /api/public/stats/summary` (compteurs uniquement).
Municipal : `POST /api/municipal/login|logout`, `GET /api/municipal/status`.
Tableau de bord municipal (`/municipal/dashboard`, protégé) : `GET
/api/municipal/dashboard/{summary,latest-report,incident-status,map,
activity,priority-plan,search}` — agrégats bornés et paginés par curseur,
jamais de lecture complète (voir `docs/PERSISTANCE_EVOLUTION.md` pour la
trajectoire grand volume ; charge mesurée à 1M synthétiques via
`dart run test/load_dashboard.dart --n=1000000`).

## Scalabilité homepage (raisonnée, pas de million en base applicative)

- La page publique ne lit JAMAIS MongoDB directement : elle sert l'état
  de travail en mémoire (borné : 500 signalements max + scénario), trié et
  paginé côté serveur (`sortPublicReports`, curseur = dernier id vu,
  curseur inconnu → page vide, pas de saut). Aucun `SELECT *`, aucune
  jointure : incidents pré-calculés par le regroupement municipal,
  compteurs seuls pour les stats, photos en vignettes à la demande.
- Index Mongo (miroirs + accès directs éventuels) : `reports(receivedAt
  -1, category, x/y, t, source)`, `journals(seq unique, event)`,
  `incidents(id)`, `plans(version)`, `simulations(planId)`,
  `meta_calls(kind)`. La collection `simulation_video` (1M, hors
  application) n'est jamais touchée par la homepage.
- Limites : tri/pagination en mémoire valent jusqu'à la borne 500 ; au-delà
  (changement de borne), il faudra requêter Mongo avec ces index
  (requêtes déjà indexées, pas de refactor des routes).
Regroupement : `POST /api/group` `{distMaxM, deltaTMaxH, simMin, method: classique|meta}` -> groupes + incidents + incertitudes + F1 (vérité DEV).
Planification : `POST /api/plan` (optimiseur exact commun aux deux méthodes, plan versionné), `POST /api/plan/validate` `{decision: valide|rejete}`.
Simulation : `POST /api/simulate` -> R simulés, violations, robustesse ×1,2/×1,5.
Injection : `POST /api/inject` `{type: reports|team_down, ...}` -> nécessité oracle + révision.
Comparaisons : `POST /api/compare` `{configs: [...]}` (paramètres classiques),
`GET /api/compare-methods` (CLASSIQUE vs META, désaccords, F1/Q séparés, DEV uniquement).
Journal : `GET /api/journal` (miroir de `app/data/journal.jsonl`, non versionné).

## Meta Model API (Phase 3, corrigée en 0.2.1)

Documentation officielle Meta Model API (developer.meta.ai) : base
`https://api.meta.ai/v1`, Bearer `MODEL_API_KEY`, `GET /models`,
`POST /chat/completions` (compatible OpenAI, `choices[0].message.content`,
usage standard). Clé **côté serveur uniquement**, jamais au navigateur.
Variable principale : `MODEL_API_KEY` (alias `LLAMA_API_KEY` /
`CITYRESOLVE_META_API_KEY` en repli explicite seulement, source affichée).
Clé utilisée telle que fournie, côté serveur uniquement, jamais journalisée.

État vérifié le 2026-11-02 : **accès réel confirmé** — `GET /v1/models`
HTTP 200, 9 modèles autorisés (muse-spark-1.1/1.2/1.3, muse-wonder-1.0,
muse-image-1.0, sam-3.1, etc.). Inférences réelles (muse-spark-1.1) :
extraction de R1 sans invention (gravité absente -> null + incertitude),
rapprochement jouet-1 identique au classique (F1 = 1,0 et Q = 100 des deux,
0 désaccord), divergence réelle sur synonymes DEV (CLASSIQUE sépare, META
fusionne, F1 inchangé car manuels hors vérité). Latences 1,7–5 s, usage
journalisé. Aucune conclusion de supériorité : données DEV uniquement.
Le moteur classique fonctionne intégralement sans Meta.

## Politique active (provisoire, NON validée)

Q 65/35, S1 7j / S2 72h / S3 24h / S4 4h calendaires, S5 escalade hors plan,
E bandes 0–4 (inconnue≠0, décision E=4 ; gravité de décision 4 pour le seul
calcul de poids, sans dispatch), 2 équipes (voirie+EV / voirie+réseaux),
08:00–16:00, grille 5×5 km à 20 km/h, budget 120 unités fictives.
Détail : `lib/policy.dart`. Aucune valeur n'est une mesure réelle.

## Score Q et falaise (vérifié, inchangé)

DEV graine 7 : plan estimé à 118,4/120, coût réalisé simulé 142,2, Q = 0.
Règle « violation globale → Q=0 » de SPECIFICATION_D_SIMU §7 et
PREENREGISTREMENT_V1.5 §3 (registre D-Q0 : validation métier requise),
appliquée dans `lib/simulator.dart`. Formule Q inchangée.

## Photos et analyse visuelle (P1, branche work/multimodal-vision)

- `POST /api/photos` (octets bruts, jpeg/png/gif/webp ≤ 5 Mo, contrôle par
  octets magiques) → `{mediaId, mime, size}` ; `GET /api/photos/<id>` sert
  le fichier. Stockage : `app/data/uploads/` (jamais dans l'état JSON ni
  en base ; `Report.photo` ne porte que le mediaId).
- `POST /api/meta/analyze-image` `{reportId}` ou `{mediaId}` : appel réel
  (images base64 uniquement en message `user`, modèle documenté compatible
  : `muse-spark-1.3`), contrat validé côté serveur (observations /
  hypothèses / incertitudes obligatoires, gravité non inventée). Sans clé :
  refus 502 explicite, « analyse visuelle IA non disponible », la photo
  reste une pièce jointe et l'analyse continue sur le texte.
- Découpage multi-problème : la description « caniveau + lampadaires »
  (§8) produit 2 volets (assainissement→reseaux, eclairage→voirie),
  gravité inconnue conservée (test T30). Lexique DEV étendu de façon
  documentée (famille `assainissement`, pluriel `lampadaires`).

## Tests

- `dart test/test_all.dart` : 161 assertions (moteur, inconnues, incertitudes,
  persistance unitaire, connecteur Meta + régression fournisseur api.meta.ai,
  médias T28, corps de requête image + contrat visuel T29, démo §8 T30,
  oracle T31, sécurité publique T32–T35).
- `dart test/test_exploratoire.dart` : 9 OK, 1 limite confirmée publiée
  (falaise Q politique).
- `python test/e2e_redemarrage.py` : 14 vérifications réelles de redémarrage.
- `python test/e2e_mongo.py` : 12 vérifications MongoDB réelles (backend
  principal, 8 écritures concurrentes sans doublon, redémarrage, collections).

## Limites connues

- Optimiseur exact ≤ 9 incidents S1..S4 connus (garde, erreur 400 explicite).
- Persistance mono-poste : fichier JSON local, pas de verrou inter-processus ;
  ne pas lancer deux serveurs sur le même `data/`.
- Moteur classique : fusions/scissions limites signalées mais non résolues
  sémantiquement (c'est le rôle attendu de la méthode META, non vérifiée ici).
- Analyse visuelle IA : implémentée et câblée, mais inférence réelle non
  exécutée dans cet environnement (sans clé Meta) ; à prouver sur Windows
  via docs/SERVER_END_TO_END_RUNBOOK.md. Sans clé : message explicite.
- Audio/vidéo : NON entrepris (décision P2 explicite) — pas de fausse
  transcription ni de fausse compréhension vidéo ; fonctionnalités futures.
- Frontend testé réellement dans le navigateur, pas de harnais JS automatisé.
