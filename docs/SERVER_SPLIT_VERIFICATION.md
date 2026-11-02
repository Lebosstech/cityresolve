# CityResolve — Vérification serveur du découpage multi-problème (Windows)

À exécuter après le runbook de preuve serveur, sur la même machine Windows,
sans aucune clé Meta : la méthode `split` ne requiert pas Meta.
Aucune clé ne doit figurer dans les sorties transmises.

## Préparation

```powershell
cd E:\cytsense\app
git pull origin main
dart test/test_all.dart
dart test/test_exploratoire.dart
```

Attendu : 119 PASS, 0 FAIL, exploratoire 9 OK / 1 limite (E7 seule).

## Lancement

```powershell
dart bin/server.dart --port 8080
```

Charger dans l'interface un scénario DEV contenant un signalement à deux
problèmes (par exemple le cas d'origine : un signalement nid-de-poule +
réverbère éteint, plus un signalement nid-de-poule seul).

## 1. Découpage global

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8080/api/group `
  -ContentType 'application/json' -Body '{"method": "split"}'
```

Attendu : 2 incidents, dont un incident d'éclairage propre, avec des
identifiants de type `ORIGINE:FAMILLE` et l'origine récupérable.

## 2. Plan

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8080/api/plan
```

Attendu : 2 tâches, une par incident découpé. L'éclairage ne doit plus
disparaître du plan.

## 3. Non-régression classique, puis split sur classique

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8080/api/group `
  -ContentType 'application/json' -Body '{"method": "classique"}'
```

Attendu sans `split` : 1 incident (ancien comportement, inchangé).

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8080/api/group `
  -ContentType 'application/json' -Body '{"method": "classique", "split": true}'
```

Attendu avec `split: true` : de nouveau 2 incidents.

## 4. Persistance après redémarrage

Arrêter le serveur, le relancer, puis vérifier :

```powershell
Invoke-RestMethod -Uri http://127.0.0.1:8080/api/state
Invoke-RestMethod -Uri http://127.0.0.1:8080/api/db
```

Attendu : méthode `split` conservée, 2 incidents conservés, compteurs
`/api/db` cohérents avec l'état avant redémarrage.

Limite connue à signaler si elle se produit : un état découpé n'est
restauré comme découpé que si `groupMethod == 'split'` est persisté.
Sans cela, le redémarrage retombe sur le regroupement classique :
l'état reste lisible, mais les groupes découpés sont perdus.

## 5. Transmettre

Envoyer à Muse, sans clé, les sorties exactes des appels ci-dessus :
groupes `split`, plan à 2 tâches, classique sans `split` à 1 incident,
classique avec `split: true` à 2 incidents, état après redémarrage et
compteurs `/api/db`. Puis arrêter le serveur et vérifier qu'aucun
processus Dart ne reste.
