# Patch local E4 + verrou serveur — Poussé sur main le 2026-11-02, commit 269911986d565b06c0d03e910b1f89e725151fc7

Base : dépôt Lebosstech/cityresolve, commit e478f66 (0.2.1), miroir local.
Dossier : ~/workspace/cityresolve/patch-e4-lock-app (copie, dépôt d'origine intact dans repo-mirror).

## Changements
1. lib/grouping.dart — ambiguousPairs : nouvelle branche pour texte similaire
   (Jaccard >= simMin) et temps proche, mais distance > 2 × distMax.
   La paire est signalée comme doublon distant à vérifier, NON fusionnée.
   Justification : deux incidents réels peuvent partager un texte ; fusionner
   serait une erreur, séparer en silence l'était aussi.
2. test/test_exploratoire.dart — E4 : l'idéal mesuré change, explicitement.
   Ancien idéal : 1 incident (fusion). Nouvel idéal : 2 incidents séparés
   ET paire ambiguë présente. Le regroupement n'a pas été modifié pour
   réussir le test ; c'est le signal qui a été ajouté.
3. lib/server_lock.dart (nouveau) + bin/server.dart (branchement) :
   création exclusive de data/server.lock, avec PID et date. Un second
   serveur sur le même répertoire refuse avec un message explicite et
   exit(2). Limite assumée : après un arrêt brutal, le fichier peut
   rester ; suppression manuelle après vérification qu'aucun serveur
   ne tourne. Ce n'est pas un verrou d'OS, ni une garantie de production.
4. test/test_all.dart — T23a/b/c : premier verrou acquis, second refusé
   avec PID signalé, libération puis réacquisition.

## Résultats vérifiés ici, Dart SDK 3.13.7
- test_all : 75 PASS, 0 FAIL (72 de base + 3 T23).
- test_exploratoire : 8 OK, 1 LIMITE (E7 falaise Q, inchangée).
- Serveur complet non lancé ici (dépendance mongo_dart non récupérée),
  donc le branchement dans main() est relu, pas exécuté en serveur.

## Non fait, volontairement
- Aucun push, aucun commit sur GitHub, aucune modification du dépôt.
- Aucun changement de seuil de regroupement, aucune fusion forcée E4.
- SQLite non ajouté : décision pile MongoDB vs SQLite toujours ouverte.
- Accès Meta réel non vérifié : toujours bloqué en attente d'une clé
  nouvelle après révocation, jamais en chat.
