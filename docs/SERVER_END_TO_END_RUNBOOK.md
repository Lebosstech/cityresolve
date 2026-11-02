# CityResolve — Preuve serveur bout en bout (Windows)

Objectif : prouver que le serveur CityResolve lui-même, sur la machine Windows,
appelle réellement l'API Meta Model API, sans simulation, et journalise l'appel.
Cette preuve n'existe pas encore : les preuves Meta obtenues jusqu'ici passent
par le connecteur externe de Muse, pas par ce serveur.

À ne jamais faire : coller une clé API dans le chat, dans un message, dans un
fichier commité, ni dans un fichier partagé. La clé se tape uniquement dans
le terminal PowerShell, pour la session en cours, et nulle part ailleurs.

## 0. Préparer

```powershell
cd E:\cytsense\app
git pull origin main
dart test/test_all.dart
dart test/test_exploratoire.dart
```

Attendu après les patches poussés sur main : 99 PASS, 0 FAIL, et exploratoire
9 OK / 1 limite (E7 seule). Si ces chiffres diffèrent, s'arrêter et signaler
les sorties exactes avant de continuer.

## 1. Définir la clé, pour la session seulement

Dans le même terminal PowerShell, taper directement (sans la copier ailleurs) :

```powershell
$env:MODEL_API_KEY = 'VOTRE_CLE_ICI'
```

La clé doit être celle créée dans le tableau de bord Meta, après révocation de
toute ancienne clé ayant transité par une conversation tierce. Ne pas utiliser
une clé copiée depuis un chat. Vérifier ensuite que le dépôt est propre :

```powershell
git status
```

Aucun fichier contenant la clé ne doit apparaître. Si c'est le cas, ne pas
committer.

## 2. Lancer le serveur

```powershell
dart bin/server.dart --port 8080
```

Puis, dans un second terminal ou dans le navigateur, vérifier :

- `GET http://127.0.0.1:8080/api/health`
- `GET http://127.0.0.1:8080/api/meta` : avant vérification, l'état doit être
  `unconfigured` (non configuré), pas un état inventé.

## 3. Vérifier l'accès Meta par le serveur lui-même

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8080/api/meta/verify
```

Noter exactement : état (`verified` attendu), modèle renvoyé, latence en ms,
et l'identifiant d'appel visible dans :

```powershell
Invoke-RestMethod -Uri http://127.0.0.1:8080/api/meta/calls
```

Si l'état est `accessError`, s'arrêter : copier le message d'erreur exact
(sans la clé), vérifier le tableau de bord Meta, et ne pas relancer en boucle
avec la même clé.

## 4. Extraction, regroupement, comparaison — dans le serveur

Dans l'interface web (`http://127.0.0.1:8080`), charger un scénario DEV, puis :

1. Noter un identifiant de signalement visible dans
   `GET http://127.0.0.1:8080/api/reports`.
2. Extraire ce signalement par le serveur :

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8080/api/meta/extract `
  -ContentType 'application/json' `
  -Body '{"reportId": "ID_DU_SIGNALEMENT"}'
```

3. Regrouper par Meta, puis par classique, dans cet ordre :

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8080/api/group `
  -ContentType 'application/json' -Body '{"method": "meta"}'
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8080/api/group `
  -ContentType 'application/json' -Body '{"method": "classique"}'
```

4. Consulter la comparaison et le journal :

```powershell
Invoke-RestMethod -Uri http://127.0.0.1:8080/api/compare-methods
Invoke-RestMethod -Uri http://127.0.0.1:8080/api/journal
Invoke-RestMethod -Uri http://127.0.0.1:8080/api/meta/calls
```

## 5. Ce qui constitue la preuve

Envoyer à Muse, sans aucune clé, les sorties exactes de :

- `/api/meta` après vérification (état, modèle) ;
- `/api/meta/calls` (identifiants d'appel, modèle, latences, erreurs éventuelles) ;
- `/api/meta/extract` pour le signalement choisi (sortie structurée) ;
- `/api/group` méthode meta (groupes, modèle) et méthode classique (groupes) ;
- `/api/compare-methods` et `/api/journal`.

La preuve est complète si et seulement si : l'état est `verified`, le modèle
renvoyé est un modèle réellement accessible, l'extraction est structurée,
les groupes Meta sont persistés par le serveur, et chaque appel est journalisé
avec son identifiant, son modèle et sa latence. Une sortie du connecteur
externe de Muse ne remplace pas cette preuve.

## 6. Nettoyer

Après la preuve, dans le terminal PowerShell :

```powershell
$env:MODEL_API_KEY = $null
```

Fermer le serveur (Ctrl+C). Ne committer aucun fichier contenant la clé, et
vérifier `git status` avant tout commit ultérieur.
