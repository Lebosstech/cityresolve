# SUIVI SOUMISSION — CityResolve

Date : 3 novembre 2026 (soir, Abidjan).
Deadline : 4 novembre 2026, 21:00 ET = 5 novembre 2026, 02:00 Abidjan.
Portail : https://cerebralvalley.ai/e/meta-ai-developer-hackathon/hackathon/submit
(la page publique redirige vers la page de l'événement ; les champs du
formulaire de soumission ne sont pas visibles sans connexion — NON VÉRIFIÉ,
à confirmer par le propriétaire connecté au portail.)
Statut scientifique : Niveau 1 — Idée. Protocole confirmatoire : NON GELÉ.
Ceci est un dossier de démonstration DEV, pas une preuve confirmatoire.

## Ce qui fonctionne (vérifié le 3 novembre 2026, en VM, copie du code main)

- Dépôt GitHub privé Lebosstech/cityresolve, main, 17 commits (dernier
  736d43eb, utilitaire de migration MongoDB, 2 novembre 21:40 UTC).
  ATTENTION : le miroir local ~/workspace/cityresolve/repo-mirror/app et la
  copie run-local sont ANTÉRIEURS au découpage (pas de split) — ne jamais
  pousser depuis ces copies, cela régresserait le découpage et l'utilitaire
  de migration. Le code de référence vérifié ici est
  patch-server-split-app (copie de staging du code main avec split).
- Tests : 119 PASS, 0 FAIL (test_all avec split) ; exploratoire 9 OK, 1 limite
  confirmée (E7, falaise Q=0, comportement publié, pas un bug masqué).
  Ancien total 72 PASS = suite sans split, obsolète.
- Serveur VM lancé sur 8081 (après `dart pub get`, mongo_dart) : /api/health
  ok, backend JSON (repli, MongoDB injoignable en VM — attendu).
- Parcours DEV graine 7 (20 signalements, 8 incidents) : regroupement
  classique 8 groupes, plan PLAN-1 (5 tâches), simulation Q 0,0 avec
  violation budget (142,2 > 120) — falaise Q connue, à expliquer, pas à cacher.
- Découpage multi-problème : 11 groupes, D10 présent deux fois
  (électricité + éclairage) — le problème secondaire survit, contre
  classique seul. Résultat DEV uniquement, pas une preuve générale.
- Injection après plan : oracle U, « ancien plan faisable, gain +0,0 < 5,0 :
  stabilité » — une information qui ne doit PAS déclencher de révision
  injustifiée, démontrée.
- S5 (jouet-s5) : plan PLAN-3, escalations [I1], justification « S5 :
  escalade humaine immédiate, jamais dispatché » — vérifié.
- Comparaison classique/Meta : route GET /api/compare-methods fonctionnelle
  (un appel POST renvoie « route inconnue » — méthode à respecter, pas un bug).
- Meta réel via connecteur Muse : muse-spark-1.3 vérifié (9 modèles,
  GET /v1/models 200), pilote 3/3 appels (moyenne 5,5 s, 672 jetons),
  phase 4 réelle (~20 s, ~3 670 jetons/appel). Coût monétaire non renvoyé
  par l'API : jamais affirmé.
- Interface existante : tableau de bord, signalements (+ ajout), incidents
  (classique / Meta / découpé), planification, simulation, journal,
  comparaison, carte locale fictive 5×5 km, bannière DEV explicite.
  Interface fonctionnelle mais sobre, en français ; pas de refonte
  risquée entreprise à 31 h de l'échéance.

## Ce qui est cassé / non vérifié (P0, hors de portée de cette VM)

- P0-1 Serveur Windows E:\cytsense\app : NON VÉRIFIÉ depuis cette VM
  (127.0.0.1 Windows inaccessible). À vérifier sur place : lancement,
  /api/health, /api/db, chargement dev-7, split, plan, simulation.
- P0-2 Meta sur le serveur Windows : état « unconfigured » en VM (normal,
  aucune clé dans la VM). Sur Windows : retaper MODEL_API_KEY en session
  PowerShell (jamais en chat), puis « Vérifier Meta » ; sans cela le
  parcours Meta de la démo ne fonctionne pas sur place.
- P0-3 MongoDB : en VM, repli JSON (MongoDB absent). Sur Windows :
  confirmer MongoDB local ou Atlas comme base principale, compteurs
  /api/db cohérents, et que le chargement simulation (lots 11–500) n'est
  PAS lancé pendant la démo (il écraserait les collections miroirs si
  lancé dans reports — collection dédiée simulation_video obligatoire).
- P0-4 Champs du portail de soumission : NON VÉRIFIÉS (formulaire
  derrière connexion). À confirmer : titre, description, piste (Indie),
  thème (Build for Your World), lien dépôt, lien démo, vidéo (durée
  exigée ou facultative), et si un extrait autonome du dépôt est exigé
  pour le code préexistant.
- P0-5 Vidéo de démonstration : NON CRÉÉE. Aucune capture de l'interface
  réelle n'a été faite depuis cette VM (navigateur de l'utilisateur
  inatteignable vers la VM, 127.0.0.1 = sa propre machine). Parcours de
  capture + script fournis (SUBMISSION_PACK.md) ; la vidéo doit être
  tournée sur la machine Windows, sur l'interface réelle, sans simulation
  d'inférence.
- P0-6 Déploiement public : NON FAIT, et non autorisé sans feu vert
  (déploiement payant réservé). La démo peut se faire en local + vidéo ;
  Render a été évoqué comme option la plus simple (Dockerfile, serveur
  Dart en continu), Hostinger non adapté sans conteneur — décision
  réservée au propriétaire, après l'échéance si besoin.

## Tâches P0 (bloquant soumission)

- [ ] P0-1 Vérification serveur Windows (voir ci-dessus).
- [ ] P0-2 Réactivation Meta sur Windows + vérification d'une extraction
      réelle depuis l'interface.
- [ ] P0-3 Vérification MongoDB / compteurs sur Windows.
- [ ] P0-4 Confirmation des champs du portail par le propriétaire connecté.
- [ ] P0-5 Tournage vidéo sur Windows selon le script fourni.
- [ ] P0-6 Décision finale du propriétaire : soumettre ou non
      (soumission finale EXCLUE de ce mandat autonome).

## Tâches P1 (fortement utile)

- [x] Parcours démo DEV reproductible documenté (SUBMISSION_PACK.md).
- [x] Présentation anglaise (Problem / Solution / How it works / Meta AI /
      Tested / Limitations / Future) — sans impact réel revendiqué, sans
      supériorité sur Ushahidi.
- [ ] Refonte visuelle légère de l'interface (CSS seulement, sans toucher
      à la logique) — reportée : risque de régression à 31 h, interface
      actuelle lisible et honnête.
- [ ] Démonstration d'une révision de plan justifiée (oracle R) en plus
      du cas de stabilité (oracle U) — le code oracle existe
      (lib/oracle.dart), le cas R reste à exhiber sur un scénario DEV.

## Tâches P2 (facultatif, non entreprises)

- Animations, optimisations non bloquantes, refactoring, nouvelles
  statistiques, SAM 3.1 image (non testée, aucune image traitée).

## Tests exécutés (3 novembre 2026, VM)

- dart test/test_all.dart (code main avec split) : 119 PASS, 0 FAIL.
- dart test/test_exploratoire.dart : 9 OK, 1 limite confirmée (E7).
- Serveur VM 8081 : health, db, meta, scenario/load dev-7 + jouet-s5,
  group classique/split, plan, simulate, inject après plan,
  compare-methods (GET), plan S5 — tous conformes aux notes ci-dessus.
- Meta connecteur : models 200 (9 modèles), pilote 3/3.

## Questions réellement bloquantes (pour le propriétaire, pas pour ChatGPT)

1. Le serveur Windows tourne-t-il avec Meta configuré et MongoDB
   cohérent, oui ou non ?
2. Quels sont les champs exacts du portail une fois connecté ?
3. La vidéo est-elle exigée, et de quelle durée ?
4. Soumets-tu, oui ou non, et sous quelle piste / quel thème ?

## Prochain travail à exécuter

1. Pousser ce fichier et SUBMISSION_PACK.md sur main (docs/), sans
   toucher au code de l'application.
2. Attendre les réponses P0-1 à P0-4 (Windows + portail) ; ne pas
   prétendre que la démo Windows fonctionne avant ces confirmations.
3. Si la vidéo est tournée sur Windows, l'ajouter aux livrables et
   re-vérifier la liste des champs du portail avant toute soumission.
