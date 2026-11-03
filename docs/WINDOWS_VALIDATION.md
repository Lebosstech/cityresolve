# CityResolve — Validation Windows en une session (pour le propriétaire)

Durée estimée : 30 à 45 minutes. Ne rien payer, ne rien publier, ne
communiquer aucune clé en chat. La clé Meta se tape uniquement dans la
session PowerShell, jamais dans une conversation.

## 0. Préparation (2 min)
- Fermer tout ancien serveur CityResolve (un seul serveur par dossier
  `data/` ; si le verrou bloque alors qu'aucun serveur ne tourne,
  supprimer `data/server.lock` puis relancer — jamais deux serveurs).
- Ouvrir PowerShell dans `E:\cytsense\app`.

## 1. Serveur Dart (5 min)
```powershell
dart test/test_all.dart
dart bin/server.dart --port 8080
```
Attendu : tests sans échec bloquant, puis `CityResolve DEV ... sur
http://localhost:8080`. Ouvrir http://127.0.0.1:8080 dans le navigateur.

## 2. MongoDB (5 min)
- Dans l'interface ou par `GET /api/db` : noter le backend effectif
  (MongoDB principal ou repli JSON) et les compteurs (state, reports,
  incidents, plans, teams, simulations, journals, meta_calls).
- Si MongoDB ne répond pas : le serveur bascule en repli JSON explicite
  — c'est un fonctionnement prévu, pas un crash, mais le noter comme tel.
- Ne pas lancer le chargement simulation (lots 11–500) pendant cette
  session, et ne jamais écrire dans `reports` (collection dédiée
  `simulation_video` uniquement, avec vérification après chaque lot).

## 3. Inférence Meta réelle depuis CityResolve (10 min)
```powershell
$env:MODEL_API_KEY = "TA_CLE_ICI"   # tapée dans cette session seulement
```
Puis, serveur relancé dans la même session :
- Bouton « Vérifier Meta » : attendu `verified`, 9 modèles, modèle
  serveur par défaut muse-spark-1.1 (distinct de muse-spark-1.3 utilisé
  via le connecteur Muse — les deux sont réels, ne pas les confondre).
- Extraction Meta sur D1 (DEV graine 7) : gravité null si non exprimée,
  aucune gravité inventée.
- Regroupement META, puis comparaison CLASSIQUE / META : noter les
  désaccords, F1 et Q séparés. Si CLASSIQUE est meilleur, le noter.
- Après la session : fermer PowerShell (la clé n'est écrite dans aucun
  fichier, aucun commit, aucun registre).

## 4. Démonstration complète (10 min)
Dans l'ordre, sur DEV graine 7 (20 signalements, 8 incidents) :
1. Regroupement CLASSIQUE, puis DÉCOUPÉ : 11 groupes, un signalement
   présent deux fois (électricité + éclairage).
2. Plan (optimiseur commun), puis simulation : expliquer Q 0,0 et la
   violation budget réalisée (142,2 > 120) — falaise Q connue.
3. Révision justifiée R1 : injection `team_down` equipe-2 → nécessité
   N1, PLAN-2 sur equipe-1, Q planifié 60,98 → 50,16 (baisse expliquée :
   equipe-1 n'a pas le domaine réseaux, I3/I5/I7 non affectés).
4. Révision S5 : injection d'un signalement gravité 5 → nécessité
   N3-S5, aucun nouveau plan, escalade humaine.
5. Cas de stabilité U (déjà vérifié) : injection d'un signalement
   ordinaire après plan → plan conservé (gain +0,0 < 5,0).

## 5. Vidéo (10 min, à tourner dans cette session si possible)
- Capturer l'interface réelle, dans l'ordre du script
  (docs/SUBMISSION_PACK.md, section B), narration anglaise.
- Garder visibles la bannière DEV et la mention « carte fictive ».
- Ne jamais simuler une inférence : si Meta n'est pas configuré,
  montrer le parcours classique + découpé et le dire.
- Si la capture est impossible : noter l'outil manquant et livrer le
  script + la narration, sans prétendre que la vidéo existe.

## 6. Bilan à renvoyer (2 min, message court)
Serveur OK / KO — MongoDB (principal ou repli) + compteurs — Meta
(verified / unconfigured + modèle) — Démo R1 / S5 / U OK / KO —
Vidéo tournée oui / non — Champs du portail (si connectés) : liste
exacte. Rien d'autre n'est demandé dans ce bilan.
