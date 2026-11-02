# Procédure d'enregistrement d'un jeu tenu à l'écart (vierge, aucun jeu réel)

1. L'utilisateur gèle d'abord le protocole : politique Q principale,
   seuils, règles de comptage, grille de sensibilité, comparateur.
   La date de gel est archivée. Aucun jeu tenu à l'écart n'est créé
   avant ce gel.
2. Un contributeur indépendant du développement prépare le jeu :
   incidents vrais, signalements, gravités, expositions, délais,
   équipes, budget. Il ne montre ni la vérité ni les scénarios aux
   développeurs ni aux systèmes évalués.
3. Le contributeur écrit le fichier de vérité au format de
   held_out_template.json, avec truth_created_utc, et calcule son
   hash SHA-256 immédiatement. Le hash est archivé avec la date.
4. Le statut jamais-utilisé-en-développement est enregistré avec
   l'auteur, l'index de contributeur (1 sur 3 ou plus pour
   l'ensemble A), et la source des signalements.
5. Les systèmes évalués produisent ensuite leurs sorties, horodatées
   après la vérité. Le harnais refuse toute sortie antérieure ou
   égale à la vérité, et toute vérité sans règle de comptage.
6. Les résultats sont journalisés par le harnais (entrée, version,
   hash de vérité, hash des sorties, métriques) dans logs/runs.jsonl.
   La journalisation est immuable : on n'édite jamais une ligne
   de log, on ajoute une nouvelle exécution.
7. Les ensembles A et B sont enregistrés et évalués séparément,
   jamais fusionnés. Un jeu de l'ensemble B porte la mention
   « fréquence artificielle de critiques, déclarée ».
8. Aucun jeu réel n'est rempli dans ce modèle. Le modèle seul ne
   constitue ni une vérité, ni une preuve, ni une évaluation.
