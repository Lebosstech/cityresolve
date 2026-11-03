# CityResolve — Textes courts pour le portail (champs exacts NON VÉRIFIÉS)

Les champs exacts du portail de soumission ne sont pas visibles sans
connexion (la page publique redirige vers la page de l'événement).
Les textes ci-dessous sont préparés pour les champs habituels ; ils ne
doivent être collés que dans les champs correspondants, après
vérification sur place. Aucune soumission n'a été envoyée.

## Titre proposé
CityResolve — Citizen reports that keep every problem, not just the first one

## Description courte (une phrase)
CityResolve turns messy citizen reports into distinct, prioritised urban
incidents — splitting multi-problem reports so the second problem is not
lost — and plans interventions with one shared optimiser, revising the
plan only when new information justifies it.

## Description longue (à adapter au champ "About / Description")
CityResolve is a DEV prototype that structures citizen reports into
incidents: multi-problem splitting (ORIGIN:FAMILY units), classical
grouping as a transparent baseline, real Meta AI extraction and matching
(Muse Spark via the Meta Model API), one exact optimiser for both
methods, plan simulation, and an oracle that revises a plan only when
justified (team down, new S5 escalation, or a Q gain above threshold).
Severity-5 incidents are never dispatched to ordinary teams; they trigger
immediate human escalation. Status: Level 1 — Idea. The confirmatory
protocol is NOT frozen, and no held-out evaluation has been run. All
demo numbers are fictitious DEV results.

## Piste / thème proposés (à confirmer sur le portail)
- Track: Indie Developer (solo builder).
- Theme: Build for Your World.
- Models used: Muse Spark 1.3 (via connector) and Muse Spark 1.1
  (server default) via https://api.meta.ai/v1. SAM 3.1: not used
  (image segmentation untested, no image processed).

## Ce qu'il ne faut jamais écrire dans le formulaire
- Aucun impact municipal réel, aucun déploiement en ville réelle.
- Aucune supériorité sur Ushahidi ou une autre plateforme.
- Aucun coût monétaire (l'API ne le renvoie pas).
- Aucune affirmation que le protocole est gelé ou que la preuve
  confirmatoire existe.
- Aucun lien vers un dépôt rendu public sans autorisation explicite
  (le dépôt Lebosstech/cityresolve est privé).

## Liens à préparer (tous à confirmer)
- Dépôt : Lebosstech/cityresolve (privé) — extrait autonome à préparer
  seulement si le portail l'exige ; ne pas rendre le dépôt public
  sans autorisation.
- Démo : vidéo tournée sur l'interface réelle (Windows), ou, à défaut,
  parcours de capture + script (docs/SUBMISSION_PACK.md, section C).
- Documentation : docs/SUIVI_SOUMISSION.md et docs/SUBMISSION_PACK.md
  sur main, README de l'application (voir note de cohérence ci-dessous).

## Note de cohérence README / dépendances / main (vérifiée le 3 nov. 2026)
- README de l'application (main) : titre 0.2.1, mais aucune mention du
  découpage multi-problème, de l'utilitaire de migration MongoDB, ni
  d'Atlas ; il dit encore « SDK Dart seul » dans les prérequis alors
  que pubspec.yaml déclare mongo_dart ^0.10.10 (dépendance unique).
- Versions incohérentes : README 0.2.1, serveur appVersion 0.2.0-dev,
  pubspec version 0.1.0. À harmoniser avant soumission, sans toucher
  au code, par une correction ciblée du README sur main.
- Modèle serveur par défaut : muse-spark-1.1 (README et serveur),
  distinct de muse-spark-1.3 (connecteur Muse). Les deux sont réels ;
  ne pas les fusionner dans le formulaire.
- README dit « ne pas lancer deux serveurs sur le même data/ » :
  toujours vrai, et le verrou data/server.lock existe désormais
  (à supprimer uniquement si aucun serveur ne tourne).
- Le README n'est pas réécrit ici depuis une copie périmée : toute
  correction doit partir du fichier main actuel, pas du miroir local.
