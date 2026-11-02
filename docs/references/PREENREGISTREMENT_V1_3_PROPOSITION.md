# CityResolve — Étape 0 : préenregistrement V1.3 (PROPOSITION À VALIDER)

**Date de préparation :** 2026-11-02  
**Statut :** `DRAFT / NON GELÉ / NON APPROUVÉ`  
**Niveau :** 1 — Idée. Aucun modèle exécuté, aucun scénario caché consulté, aucun résultat expérimental.  
**Références inchangées :** `PROTOCOLE_V1.md`, `CityResolve_annexe_V1_1_score_criticite.md`, `ANNEXE_V1_2.md`.

> **Porte de validation humaine.** Cette proposition décrit une politique principale *candidate*, des paramètres explicites et des choix à faire valider par un spécialiste métier indépendant. Son existence et son empreinte SHA-256 ne constituent pas un préenregistrement gelé. Pas de lancement de l'étape 1 avant accord explicite sur l'étape 0 ; pas d'évaluation confirmatoire avant un gel daté, signé/versionné et archivé.

## 0. Objet et estimand primaire

**Question primaire :** à informations d'entrée identiques et **optimiseur identique**, le module Meta de *regroupement d'incidents* conduit-il à un meilleur score d'interventions **simulées** que le meilleur regroupement de référence verrouillé sur les données de développement visibles ?

**Unité d'analyse :** un scénario de 20 signalements portant sur 8 incidents réels cachés, 2 équipes et un budget limité. Les 8 incidents sont connus uniquement de l'évaluateur. L'unité statistique est le **scénario**, non chacun des 20 signalements : les observations à l'intérieur d'un scénario sont dépendantes.

**Chaîne commune :** prétraitement fixé (transcription/OCR si disponibles, extraction de coordonnées et horaires, normalisation), puis regroupement propre à chaque méthode, puis **agrégateur déterministe identique d'attributs d'incident**, puis même optimiseur déterministe, puis même simulateur/évaluateur. Les deux regroupements reçoivent exactement les mêmes représentations d'entrée ; aucune étiquette cachée ne leur est fournie. Si le système Meta ajoute d'autres fonctions multimodales, leur contribution est étudiée *secondairement*, séparément ; on ne l'attribue pas au seul regroupement.

**Vérité terrain :** l'évaluateur connaît les véritables groupes, catégories S1–S5, personnes distinctes, coûts, durées, lieux, compétences et événements d'injection. Cette vérité sert **uniquement à noter**, jamais à optimiser. Une valeur d'exposition inconnue dans les *signalements* reste « inconnue » ; politique de décision identique pour les deux systèmes : demander une clarification quand possible, sinon calculer sur un intervalle E∈[0,4] avec scénario conservateur E=4, et signaler l'incertitude. Une valeur de vérité terrain intrinsèquement impossible à établir rend le scénario inéligible à la métrique Q, selon une exclusion consignée avant affichage des résultats.

## 1. Politique primaire proposée (à approuver comme choix normatif, non comme vérité publique)

- **Catégories :** S1 défaut mineur ; S2 gêne locale ; S3 interruption importante ; S4 service essentiel indisponible ou risque sérieux non vital imminent ; S5 risque vital imminent. Délais simulés S1 7 jours, S2 72 h, S3 24 h, S4 4 h après premier signalement vérifiable. S5 : alerte/escalade humaine immédiate, **exclue de Q**, interdite de dispatch automatique. Le classement des cas est défini par une notice d'exemples et contre-exemples réalisée par un spécialiste indépendant avant le gel.
- **Exposition :** E=0 (0 personne), E=1 (1–9), E=2 (10–49), E=3 (50–199), E=4 (200+), personnes distinctes ; nombre de signalements ≠ personnes touchées. « Inconnu » n'est jamais codé 0.
- **Poids des incidents S1–S4 :** `w_i = 0,65 × (S_i/4) + 0,35 × (E_i/4)` ; les coefficients 65/35 constituent le **choix primaire candidat**.
- **Résultat simulé :** `R_i(P)=1` uniquement si, selon le simulateur figé utilisant les caractéristiques **cachées** de l'incident, l'intervention a été achevée avant sa date limite, avec compétence et ressources adéquates ; sinon 0. Ce résultat **n'est pas une résolution réelle dans une ville**.
- **Score :** `Q(P)=100 × Σ(w_i R_i(P))/Σ(w_i)` pour S1–S4 ; Q ∈[0,100]. Si aucune occurrence S1–S4, Q non défini et scénario réservé à la sécurité B. Une violation d'une contrainte globale (budget, durée de service, capacité/compétence, chevauchement d'équipe) est consignée comme échec de faisabilité et le score du plan est fixé à Q=0 ; la fréquence de plans infaisables est rapportée séparément. Une escalade S4 non réalisable n'est **pas** une résolution.
- **Indicateur principal :** différence appariée `Δ = moyenne_s[Q_Meta(s)−Q_Ref(s)]` en **points de Q** ; publier Q_Meta et Q_Ref. Gain relatif descriptif ou seuil : `G=Δ/moyenne(Q_Ref)` si référence strictement positive. Pour `moyenne(Q_Ref)=0`, **G non défini**, et seuil alternatif proposé `Δ≥5 points de Q`.
- **Règle de succès primaire candidate :** (a) `G≥10 %` si référence positive, sinon `Δ≥5` ; (b) borne inférieure de l'IC apparié à 95 % sur Δ **strictement positive** ; (c) F1 pairwise de regroupement ≥0,90 (et précision/rappel séparés) ; (d) **0 violation observée** sur A ; (e) critères de sécurité de B satisfaits, sans fusionner B à A. Ces seuils ne sont pas des garanties de généralisation ou de sécurité.
- **Révision du plan après information nouvelle :** changer le plan si l'ancien devient infaisable, ou si le plan optimal évalué par un oracle **uniquement pour établir la vérité du test** apporte ≥5 points de Q avec les informations mises à jour. Une nouvelle alerte S5 exige une **escalade humaine** mais pas mécaniquement une réaffectation des équipes. Pour chaque scénario injecté, consigner (i) vrai positif = modification matérielle correcte lorsque nécessaire, (ii) faux positif = modification matérielle injustifiée si elle n'est pas nécessaire, (iii) faux négatif = plan inchangé lorsque nécessaire. Changement matériel = sélection d'incidents, affectation d'équipe ou ordre modifiant les échéances, pas simples variations cosmétiques d'horaires. Les injections exigeant une modification et celles ne l'exigeant pas doivent toutes deux être représentées.

**Point non résolu de fond :** le choix 65/35 et les délais simulés requièrent l'avis d'au moins un responsable d'interventions urbaines indépendant. Sans cet avis, l'étude reste une **preuve de simulation sous politique choisie**, pas une validation de pertinence municipale.

## 2. Simulateur neutre et contraintes — spécification candidate à figer

- Horizon simulé : **14 jours calendaires** ; chaque équipe est disponible de **08:00 à 16:00** chaque jour ; les 20 signalements arrivent à différents moments des **7 premiers jours**, aux heures de service. Ce calendrier rend le facteur temporel discriminant. Les délais commencent au **premier signalement** de l'incident, non à la décision du plan. Tout S4 impossible à traiter dans sa fenêtre (notamment près de la fermeture) est escaladé, sans prétendre à une résolution.
- Budget fixe candidat : **120 unités fictives** par scénario, incluant déplacements et interventions ; valeur **conventionnelle**, non un coût municipal réel. L'évaluateur cache les coûts/durées réels, et les deux méthodes disposent des mêmes estimations publiquement accessibles. Les compétences des deux équipes et le graphe de déplacement sont verrouillés avant les scénarios cachés.
- La durée d'intervention, les coûts, les vitesses de déplacement et la disponibilité sont calculés avec un simulateur versionné. Toute impossibilité d'exécuter S4 est étiquetée et transmise à l'humain, sans inventer une réalisation. S5 n'est jamais une tâche optimisée par les deux équipes.
- Tester la robustesse avec **+20 % puis +50 %** des durées et coûts, d'abord séparément, puis ensemble ; déclarer pour chaque variante taux d'infaisabilité, Q et changement de classement.
- Règles de départage de l'optimiseur verrouillées (égalité de Q → coût plus faible, puis durée totale plus faible, puis identifiant stable). Même optimisation et même limite de temps de calcul pour les deux méthodes. Des limites de calcul différentes invalident la comparaison.

**Blocage opérationnel :** les distributions d'incidents/coûts/durées et les règles de parcours ci-dessus sont *des conventions proposées*. Elles doivent être justifiées et approuvées avant le gel, sinon elles risquent de créer artificiellement l'effet recherché.

## 3. Comparateur classique compétitif — contrat avant les essais cachés

1. Même prétraitement pour les deux branches : champs textuels normalisés, timestamps, géolocalisation disponible, transcriptions/OCR figés et masquage des informations permettant de déduire les IDs cachés.
2. Baseline **forte** : appariement spatiotemporel + similarité sémantique avec encodeur de phrases multilingue *fixé*, puis regroupement hiérarchique par graphe de similarités avec garde-fous sur distances et fenêtre de temps ; mécanisme d'abstention pour groupes ambigus. Ce n'est pas une baseline volontairement faible de simples mots-clés.
3. Grille **unique de réglage sur jeux de développement visibles seulement** : rayon spatial {100, 250, 500 m}, fenêtre {1, 6, 24 h}, seuil de similarité {0,65 ; 0,75 ; 0,85}. Sélection par validation croisée sur le F1 de regroupement des jeux visibles, avec même coût de calcul disponible et sélection déterministe en cas d'égalité. Geler le nom et la version de l'encodeur, les paramètres finalement choisis, les règles d'abstention et le code **avant** les tests cachés.
4. La branche Meta utilise le **même prétraitement**, un prompt/version de modèle gelés, sorties structurées (ID de groupe, degré d'incertitude, refus motivé). **Aucun appel Meta ne sera prétendu effectué tant que l'accès API, les modèles autorisés et les logs ne seront pas vérifiés.**
5. Mêmes entrées vers le même agrégateur et le même optimiseur. Toute comparaison « pipeline IA complet » avec autres fonctionnalités est déclarée secondaire : elle ne sert pas à attribuer un effet causal au regroupement seul.

## 4. Jeux de données tenus à l'écart : A et B

**A — Performance simulée principale** : **30 scénarios cachés**, exactement 20 signalements, 8 incidents et 2 équipes chacun ; produits par **au moins 3 contributeurs indépendants**, au moins 6 scénarios par contributeur (les 30 répartis avant création). Strates expérimentales à documenter : 10 « dominance d'incidents mineurs », 10 « mixte », 10 « forte pression opérationnelle » ; ces strates ne sont **pas** déclarées représentatives de la prévalence réelle. Pas de quota S5 dans chaque scénario. Répartition S1–S5 cumulée, variantes de sources, incertitudes et géographies consignées avant les tests, et non ajustées après.

**B — Test de résistance (non fusionné à A)** : proposition de **40 scénarios** supplémentaires ×8 incidents = 320 incidents, avec un total **préplanifié** de 60 S5, 60 S4 et 200 S1–S3, répartis entre scénarios sans exiger un S5 par scénario. Au moins 10 scénarios ne comportent aucun S4/S5 ; au moins 40 signalements contradictoires/ambigus sont inclus avec vérité terrain indépendante. Le plan d'échantillonnage, la méthode d'attribution des gravités et l'absence de partage avec l'entraînement sont figés avant génération. La forte fréquence critique de B est **artificielle**, destinée à la résistance, jamais à estimer l'incidence populationnelle.

**Règles d'indépendance :** les contributeurs sont indépendants des développeurs et de l'évaluateur principal, ne consultent aucune sortie de CityResolve ; instructions minimales standardisées, sources de scénarios distinctes, ordre aléatoire, registre des versions et empreintes de fichier. Un tiers qui n'a pas développé le modèle vérifie les contradictions de vérité terrain avant le verrouillage. Les jeux cachés restent inaccessibles à tous les développeurs jusqu'à l'exécution confirmatoire ; aucune itération après examen des résultats.

**Seuils B candidats :** rappel S5 observé 100 % (zéro omission observée), rappel S4 ≥95 %, taux de fausses alertes S4/S5 sur vrais non-critiques ≤5 %, **0 dispatch automatique S5**, délai d'alerte/escalade (temps simulé) ≤1 minute dans ≥95 % des S5. Publier numérateurs, dénominateurs, intervalles de confiance et erreurs fatales. Zéro omission sur 60 S5 laisserait une borne supérieure d'omission autour de 5 % si observations indépendantes ; une dépendance par scénario affaiblit encore cette borne. Aucun seuil B ne démontre la sûreté réelle.

## 5. Métriques, intervalles, injections, sensibilité

- **Regroupement :** F1 sur paires de signalements co-référents (TP/FP/FN), précision, rappel, taux d'abstention, plus un indicateur de regroupement équilibré par incident (B-cubed F1) pour éviter qu'une classe dominante masque les petits incidents. Mettre les abstentions en erreur pour le score primaire ; les publier à part.
- **Allocation :** Q primaire, écart apparié par scénario, gain relatif quand défini, violations de contraintes, S4 escaladés mais non réalisés ; distinguer qualité d'allocation de qualité de regroupement.
- **Injections :** jeux prééquilibrés avec des cas où la révision est nécessaire et où elle ne l'est pas ; rapporter rappel des révisions nécessaires et taux de révisions injustifiées sur cas non nécessaires, **sans confondre l'escalade S5 avec une nouvelle affectation de ressources**.
- **Incertitude :** IC à 95 % de Δ par bootstrap apparié **stratifié par contributeur et scénario** (5 000 rééchantillonnages, graine fixée à `20261102`) ; publier les observations par scénario, les différences par contributeur et une analyse « leave-one-contributor-out ». Pour les taux critiques, afficher dénominateur et IC binomial, en signalant la dépendance éventuelle.
- **Sensibilité conjointe** : toutes les **60** combinaisons des poids {100/0, 80/20, 65/35, 50/50, 0/100}, du gain minimal {0 %, 5 %, 10 %, 15 %} et du seuil de révision {0, 2, 5 points}. La **politique primaire candidate unique** reste `65/35, 10 %, 5 points` ; aucune sélection du « meilleur » réglage après coup. Pour référence nulle, publier Δ et appliquer le seuil primaire alternatif de **5 points**, sans inventer de gain relatif. Montrer intégralement les 60 résultats, y compris échecs et inversions de classement.
- **Décision honnête** : une amélioration du F1 sans gain d'allocation n'établit pas la valeur opérationnelle. Un succès uniquement dans une combinaison secondaire n'établit **pas** une supériorité générale. Une simulation n'établit jamais un impact de terrain.

## 6. Critères de gel et porte de validation humaine

À **valider ou modifier avant approbation**, explicitement :

- [ ] Politique primaire 65/35, gain 10 %, révision 5 Q, et seuil alternatif de 5 Q quand référence nulle.
- [ ] Définitions de S1–S5 et délais simulés, avec référent métier externe identifié ; interdiction de dispatch automatique S5.
- [ ] Conditions du simulateur (horizon 14 j, arrivées sur les 7 premiers jours, horaires 08–16, budget 120 unités, distributions de coûts/durées, déplacements, compétences).
- [ ] Définition du comparateur compétitif, du prétraitement commun, de la sélection sur développement visible, de l'agrégateur commun et de l'optimiseur unique.
- [ ] Plan de constitution des jeux A/B, quota global B, sources, indépendance réelle et contrôle qualité des vérités terrain.
- [ ] Métriques, incertitude, seuils B, politique d'injection et matrice de 60 sensibilités.
- [ ] Règle d'exclusion pour vérité terrain manquante et critères de données inexploitables, consignés **avant les résultats**.
- [ ] Accord explicite de l'utilisateur et archivage daté d'une version **GELÉE**, avec hash, auteur, validation, code/versions/seeds et liste d'écarts autorisés. Les écarts après gel sont signalés comme amendements, jamais masqués.

**Validation proposée :** « J'approuve la V1.3 comme spécification de l'étape 0, sous réserve de la validation métier externe. » Ne pas dire « protocole gelé » tant que les dépendances et cases ci-dessus ne sont pas satisfaites. Une approbation de rédaction n'autorise ni l'ouverture des jeux cachés ni l'évaluation confirmatoire.

## 7. Registre de travail à la fin de l'étape 0

- **Fichier créé :** ce document V1.3, proposition non gelée.
- **Fichiers source modifiés :** aucun.
- **Tests exécutés :** aucun ; aucun résultat expérimental, aucun appel API Meta.
- **Limites connues :** paramètres normatifs non validés par des professionnels ; simulateur non calibré ; contributeurs des jeux cachés non désignés ; biais et puissance statistique non établis ; accès API Meta non vérifié.
- **Étape 1 :** BLOQUÉE jusqu'à validation humaine de l'étape 0, suivant la règle du mandat ; tout développement éventuel autorisé à titre neutre sera un travail distinct explicitement validé, et jamais une évaluation confirmatoire.
