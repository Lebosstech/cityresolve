# CityResolve — documents de référence à importer dans Muse

## Mode d'emploi
1. Extraire **ces cinq fichiers** dans `E:\cytsense\docs\references\` (ou autre répertoire explicitement choisi dans le dépôt).
2. Enregistrer chaque fichier de référence dans Git, sans modifier son contenu.
3. Demander à Muse de relire les trois sources et V1.3. Muse conserve son propre `docs/PREENREGISTREMENT_V1.0.md` comme historique ; il ne doit pas le déclarer « GELÉ ».
4. La V1.3 est une **proposition NON GELÉE**, et non une autorisation de lancer des essais confirmatoires.
5. Avant tout gel : examiner les lacunes, figer les définitions du simulateur, les versions exactes du comparateur, le plan d'indépendance des scénarios et les choix normatifs ; exiger une validation humaine explicite.

## Sources
- `PROTOCOLE_V1.md` : hypothèses, cadre expérimental.
- `ANNEXE_V1_1.md` : score Q, criticité S1–S5, exposition E.
- `ANNEXE_V1_2.md` : analyse de sensibilité et séparation A/B.
- `PREENREGISTREMENT_V1_3_PROPOSITION.md` : préenregistrement complet **proposé et non approuvé**.

## Décisions provisoires, **pas de gel**
- Seuil alternatif de gain Q lorsque le score de référence est nul : **5 points**, à confirmer.
- Grille de réglage de la référence sur les jeux visibles uniquement : DIST_MAX={100,250,500} mètres, DELTA_T_MAX={1,6,24} heures, SIM_MIN={0.65,0.75,0.85}.
- Choix des trois paramètres : validation croisée sur développement visible, selon des règles écrites avant l'accès aux jeux cachés. Ne pas sélectionner sur les jeux cachés.
- Politique principale proposée : poids 65/35, gain relatif 10 %, révision à 5 points ; validation **en attente**.
- Aucune évaluation confirmatoire ni accès aux scénarios cachés n'est autorisé.
