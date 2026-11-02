# CityResolve — Preuve serveur bout en bout, 2026-11-02 (Windows, sans clé)

Preuve exécutée par l'utilisateur sur sa machine Windows, à partir du runbook
`docs/SERVER_END_TO_END_RUNBOOK.md`, et transmise sans aucune clé API.
Aucune clé ne figure dans ce fichier.

## 0. Préparation

- `git pull origin main` : déjà à jour, dernier commit `7baa95b`.
- `dart test/test_all.dart` : `== 99 PASS, 0 FAIL ==`.
- `dart test/test_exploratoire.dart` :
  `== EXPLORATOIRE : 9 OK, 1 LIMITE(S) CONFIRMEE(S) ==`, E7 seule
  (falaise Q, politique documentée).

## Incident au démarrage, géré selon la procédure du serveur

Le premier lancement a été refusé par le verrou : `data/server.lock`
pointait le PID 11872, tué brutalement lors du redémarrage de
l'environnement. PID vérifié mort, lock périmé supprimé, relance OK
(PID 14916). Le verrou mono-instance a donc fait son travail : il a
refusé un second serveur, et la suppression n'a eu lieu qu'après
vérification que le premier processus était mort.

## État avant vérification

- `GET /api/health` :
  `{"ok":true,"version":"0.2.0-dev","protocol":"NON GELÉ (brouillon)","groupMethod":"meta",…}`
  (le `groupMethod` meta reflète un état antérieur, pas un résultat
  de cette preuve).
- `GET /api/meta` (clé présente en session) :
  `{"state":"accessError","models":[],"model":"muse-spark-1.1","message":"Clé présente via MODEL_API_KEY mais accès non vérifié…","baseUrl":"https://api.meta.ai/v1","keySource":"MODEL_API_KEY"}`

## Vérification Meta par le serveur lui-même

- `POST /api/meta/verify` :
  `{"state":"verified","models":["muse-wonder-1.0","sam-3.1","muse-spark-1.3-contributor","muse-voice-transcribe-1.0","muse-spark-1.3","muse-image-1.0","muse-spark-1.2-contributor","muse-spark-1.2","muse-spark-1.1"],"model":"muse-spark-1.1"}`
- Appel `META-1-1793644897641`, statut ok, latence 1173 ms.
- Distinction importante : le serveur utilise par défaut
  `muse-spark-1.1`. Les preuves précédentes via le connecteur externe
  de Muse utilisaient `muse-spark-1.3`. Cette preuve serveur porte donc
  sur `muse-spark-1.1`, pas sur `muse-spark-1.3`.
- `/api/meta/calls` : 18 appels journalisés au total, dont 6
  refus/erreurs historiques, latence cumulée 54 470 ms, usages en
  jetons présents sur les appels chat. Les 18 ne sont pas 18 nouveaux
  appels de preuve : une partie est historique.

## Preuve dans l'interface et par l'API

Scénario DEV graine 7 chargé dans l'interface web : 20 signalements,
8 incidents, panneau Meta « verified — 9 modèle(s) ».

Signalement choisi :
`{"id":"D1","text":"nid poule rue basse chaussee trou grand","category":"nid-de-poule","x":0.565…,"y":0.645…,"t":649,"severityHint":1,"exposureHint":0,"source":"scenario"}`

- `POST /api/meta/extract {"reportId":"D1"}` :
  `{"probleme":"nid-de-poule","localisationMentionnee":"rue basse chaussee","graviteExprimee":null,"expositionMentionnee":null,"incertitudes":["Gravité exprimée comme 'grand' sans échelle numérique 1 à 5, donc non transposable en entier",…],"elementsNonVerifies":["taille réelle du trou","existence et emplacement exact sur chaussée"]}`
  Aucune gravité inventée.
- `POST /api/group {"method":"meta"}` : modèle `muse-spark-1.1`,
  8 groupes, F1 = 1,0 (G2 signalé uncertain par le modèle, confiance 0,9).
- `POST /api/group {"method":"classique"}` : 8 groupes, F1 = 1,0,
  0 paire ambiguë, groupes marqués incertains (seuil).
- `GET /api/compare-methods` : `metaAvailable=true`, 0 désaccord,
  classique et Meta : F1 = 1,0, Q planifié = 60,98, Q simulé = 0,0
  des deux côtés (falaise budget DEV-7, aucune supériorité attribuée).
- `GET /api/journal` (fin) : 263 `scenario.loaded dev-7` ·
  265 `meta.extract D1` · 266 `group.done method=meta model=muse-spark-1.1` ·
  267 `group.done classique`.

## Git et MongoDB

- `git status` : rien à committer du fait de l'utilisateur — seul
  `?? app/data/` (fichier `server.lock` runtime, non suivi).
  Aucun commit effectué par l'utilisateur.
- MongoDB : base locale `127.0.0.1:27017` sur cette machine, ni
  distante ni un export. Gardée chez l'utilisateur, rien à transmettre.
  Le serveur la consomme localement, backend confirmé
  `mongodb (principal)`, pas le repli JSON.

## Ce que cette preuve établit, et ce qu'elle n'établit pas

Établi : le serveur CityResolve lui-même, sur Windows, avec MongoDB
comme backend principal, vérifie l'accès Meta, extrait un signalement
de façon structurée sans inventer de gravité, regroupe en Meta et en
classique, et journalise les appels. Sur dev-7, les deux méthodes sont
à égalité (F1 1,0, Q simulé 0,0 des deux côtés).

Non établi : une supériorité de Meta sur le classique (aucune ici),
une preuve avec `muse-spark-1.3` côté serveur (le modèle serveur est
`muse-spark-1.1`), une généralisation à des signalements réels, ni
une évaluation confirmatoire après gel du protocole.

## Nettoyage / sécurité — à confirmer

La transmission s'est arrêtée sur l'intitulé « Nettoyage / sécurité »
sans contenu. À confirmer par l'utilisateur : variable
`$env:MODEL_API_KEY` effacée (`$null`) et serveur arrêté, avant tout
commit ultérieur. Ne pas considérer le nettoyage comme fait tant que
cette confirmation n'est pas reçue.
