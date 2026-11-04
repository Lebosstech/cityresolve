# CityResolve — Évolution de la persistance vers le volume (NON IMPLÉMENTÉE)

> Statut : conception documentée uniquement. Le code actuel (snapshot
> d'état complet + miroirs) reste en place et suffit aux volumes DEV
> constatés (local : 18 signalements ; Atlas applicatif : 2 ; test de
> charge séparé : 1M synthétiques dans `cityresolve_loadtest`).
> Ne jamais exécuter cette migration sans : sauvegarde, test sur copie,
> procédure de retour arrière, et fenêtre hors démonstration.

## 1. Constat mesuré (nov. 2026)

- Écriture actuelle : `saveSnapshot()` réécrit le document `state`
  complet + reconstruit les miroirs (`incidents` effacés puis réinsérés,
  `reports` upsertés un par un + purge par lecture complète).
- Volumes réels : < 500 documents applicatifs → coût négligeable.
- Charge prouvée séparément : requêtes dashboard (récents, bbox,
  comptes) indexées et mesurées à 10k / 100k / 1M synthétiques, voir
  `app/test/load_dashboard.dart` et le rapport de la branche dashboard.
- Point dur mesuré à 1M : recherche plein-texte `$text` ≈ 3,5 s
  médiane → ne pas exposer en interactif sans moteur dédié.

## 2. Schéma cible (indicatif, à figer avant implémentation)

Collections opérationnelles, écritures unitaires :

| Collection | Clé | Écriture |
|---|---|---|
| `reports` | `_id` = identifiant permanent | insert + update ciblés |
| `report_units` | `_id` = `ORIGINE:FAMILLE` | insert à la détection split |
| `incidents` | `_id` permanent (NOUVEAU : aujourd'hui `I1..` renumérotés à chaque regroupement → casserait les liens ; figer des identifiants stables d'abord) | upsert par regroupement incrémental |
| `incident_report_links` | `(incidentId, reportId)` | insert/delete ciblés |
| `teams` | `_id` équipe | quasi-statique |
| `plans` | `planId` versionné | insert only |
| `assignments` | `(planId, incidentId)` | insert only par version |
| `events` | `_id` = seq monotone | insert only (journal) |
| `media` | `mediaId` | insert only |
| `dashboard_aggregates` | `(période, périmètre)` | upsert incrémental ou TTL + reconstruction |

Index cibles (à valider par `explain()` sur volume représentatif) :
`reports(receivedAt -1)`, `reports(category)`, `reports(status, receivedAt)`,
`reports(x, y)`, `events(seq)`, `incidents(id)`, `plans(version)`,
texte `reports(text)` en attendant mieux qu'Atlas Search (non supposé).
Pas de `2dsphere` : aucune coordonnée GPS réelle en base applicative.

## 3. Étapes réversibles proposées

1. Figer les identifiants d'incidents (prérequis bloquant, sinon les
   liens cassent à chaque regroupement).
2. Double écriture : conserver snapshot + écrire les collections
   opérationnelles ; comparer chaque nuit (job de contrôle).
3. Basculer les lectures du tableau de bord sur requêtes indexées
   (mêmes contrats JSON, curseurs inchangés).
4. Couper l'écriture snapshot après N jours sans écart ; garder le JSON
   comme export de secours.
5. Retour arrière à chaque étape : restaurer depuis la sauvegarde +
   rebasculer les lectures (interrupteur unique).

## 4. Non-objectifs confirmés

- Aucune transaction multi-documents aujourd'hui (pas de replica set
  en local) ; la cohérence reste « document d'état + réconciliation ».
- L'optimiseur exact (borne 9 incidents) ne planifiera jamais des
  millions d'incidents : à grande échelle, sélection de périmètre
  d'abord (non conçu), puis optimisation sur l'ensemble borné.
- Aucune donnée des jeux tenus à l'écart ne transite par ces agrégats.
