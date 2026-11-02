# MISSION : DÉMARRER LE DÉVELOPPEMENT DE CITYRESOLVE

Muse, je t'autorise explicitement à commencer le développement de CityResolve dans `E:\cytsense`.

Nous arrêtons temporairement les révisions documentaires répétitives. Notre objectif immédiat est de disposer d'une première application fonctionnelle et testable.

**AUTORISATIONS**

- Démarrer le développement exploratoire des Étapes 1, 2 et 3.
- Initialiser un dépôt Git local et créer un `.gitignore` adapté.
- Installer les dépendances nécessaires après inspection de l'environnement.
- Créer le backend, le frontend, le moteur de simulation, les tests et les scénarios de développement visibles.
- Exécuter les tests techniques et corriger les erreurs détectées.
- Avancer sans demander de validation à chaque fichier créé. Une validation humaine est requise en cas de changement majeur de périmètre, d'action extérieure sensible ou d'utilisation de ressources payantes.

**INTERDICTIONS MAINTENUES**

- Le protocole scientifique reste NON GELÉ.
- Aucun scénario confirmatoire caché ne doit être consulté.
- Aucun résultat DEV ne doit être présenté comme une preuve scientifique.
- Aucun appel Meta ne doit être simulé et présenté comme réel.
- Aucun résultat d'intervention simulée ne doit être présenté comme une intervention urbaine réelle.
- Aucun déploiement public ni publication de données sans autorisation.

## PHASE 1 — INITIALISATION TECHNIQUE

1. Inspecte les runtimes et outils disponibles : Node.js, npm, TypeScript, Git, Python, etc.
2. Privilégie TypeScript, React et Vite pour l'interface, ainsi qu'un backend Node.js léger, si ces outils sont disponibles.
3. Crée une architecture modulaire avec séparation stricte entre :
   - Interface utilisateur.
   - Gestion des signalements.
   - Regroupement des incidents.
   - Simulateur.
   - Optimiseur commun.
   - Connecteurs de modèles IA.
   - Calcul des métriques.
   - Journalisation et audit.
4. Initialise Git localement. Aucun dépôt distant.
5. Configure les tests automatisés et les commandes de lancement.

Livrable : application démarrable localement avec instructions d'installation reproductibles.

## PHASE 2 — PREMIÈRE CHAÎNE FONCTIONNELLE

Développe un parcours complet :

**Signalement → Regroupement → Incident → Priorité → Affectation → Résultat simulé.**

L'utilisateur doit pouvoir :

1. Créer un signalement contenant une description, une catégorie, une position, une date et éventuellement une photo.
2. Consulter les signalements reçus.
3. Regrouper les signalements similaires en incidents avec une méthode classique déterministe.
4. Afficher les incidents distincts et les informations inconnues.
5. Calculer les priorités selon la politique expérimentale explicitement indiquée.
6. Proposer des affectations à deux équipes en respectant leurs compétences, leur disponibilité, les délais et le budget.
7. Consulter les raisons d'une affectation ou d'une non-affectation.
8. Visualiser le résultat simulé et les contraintes violées, s'il y en a.
9. Ajouter une information nouvelle et déclencher une réévaluation.
10. Consulter le journal des opérations.

Utilise uniquement des scénarios de développement fictifs et visibles.

## PHASE 3 — MOTEURS TECHNIQUES

**Moteur de regroupement classique**

Implémente la comparaison géographique, temporelle et sémantique selon les paramètres de développement définis.

Produis des groupes d'incidents et des indications d'incertitude.

**Optimiseur commun**

Construis un moteur indépendant des méthodes de regroupement.

Entrées : incidents structurés, équipes, compétences, budget, disponibilités, distances et échéances.

Sorties : plan d'affectation, score Q calculé selon la politique active, justification et contraintes.

Pour les huit incidents du scénario initial, utilise un algorithme exact si le problème reste suffisamment petit. Sinon, documente clairement l'approximation et les garanties disponibles.

**Simulateur**

Implémente les hypothèses de `SPECIFICATION_D_SIMU.md`.

Les paramètres doivent être configurables. Ils ne sont pas présentés comme des mesures réelles.

Utilise des graines aléatoires reproductibles pour les tests.

**Métriques**

Implémente les calculs du F1 de regroupement, du score Q, des contraintes et des révisions de plan.

Vérifie ces calculs avec des exemples jouets dont les résultats attendus sont calculés indépendamment.

## PHASE 4 — INTERFACE UTILISATEUR

Je veux une interface moderne, claire et professionnelle.

Pages principales :
- Tableau de bord.
- Signalements.
- Incidents regroupés.
- Planification des équipes.
- Simulation et résultats.
- Journal des décisions.
- Comparaison des méthodes.

La carte peut commencer par une grille locale fictive. Ne bloque pas le projet sur une API cartographique payante.

Distingue visuellement :
- Données simulées.
- Résultats calculés.
- Informations inconnues.
- Décisions proposées.
- Validations humaines.

Aucune statistique inventée ne doit être présentée comme un résultat d'exécution.

## PHASE 5 — PRÉPARATION META

Crée une interface de connecteur permettant de brancher ultérieurement Meta Model API.

Prévois trois états explicites :
- Non configuré.
- Connecté et vérifié.
- Erreur d'accès.

Si l'accès Meta est disponible, vérifie les modèles réellement autorisés avant toute intégration.

Sinon, laisse le connecteur désactivé. Ne fabrique aucune réponse de Muse Spark ou de SAM 3.1.

La première version doit déjà fonctionner avec le moteur classique.

## PHASE 6 — TESTS ET LIVRAISON

Exécute des tests réels couvrant au minimum :

- Deux signalements du même incident.
- Deux incidents proches mais différents.
- Une exposition inconnue.
- Une équipe non compétente.
- Un budget insuffisant.
- Une échéance dépassée.
- Un incident S5 exclu du dispatch automatique.
- Une nouvelle information modifiant une décision.
- Une nouvelle information ne nécessitant aucune modification.
- Des résultats reproductibles à graine identique.

Ne présente pas les tests comme réussis avant leur exécution effective.

À la fin, fournis :
1. L'arborescence du projet.
2. Les fonctionnalités effectivement développées.
3. Les commandes exactes de lancement.
4. Les tests réussis, échoués et non exécutés.
5. Les captures ou l'adresse locale de l'application, si disponible.
6. Les limites connues.
7. Le prochain incrément fonctionnel recommandé.

**RÈGLE FINALE**

Ne reviens pas avec uniquement un nouveau document de planification.

Je veux du code source exécutable, une interface accessible localement, des calculs vérifiables et des tests effectivement lancés.

Commence maintenant par vérifier l'environnement, initialiser le projet et implémenter le premier parcours fonctionnel.

Continue de manière autonome dans ce périmètre autorisé, sans demander une validation pour chaque petite décision technique.