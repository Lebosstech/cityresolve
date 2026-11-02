# CityResolve — Protocole expérimental V1

Document de prévalidation. Aucun résultat expérimental acquis.
Statut actuel : Niveau 1 — Idée. Mécanisme décrit, ni construit, ni validé.

## 1. Hypothèse à tester

CityResolve améliore la reconstitution d'incidents urbains à partir de signalements multimodaux et permet une meilleure allocation des ressources qu'une chaîne classique de traitement des signalements.

## 2. Configuration expérimentale

- Signalements par scénario : 20
- Incidents distincts par scénario : 8, cachés aux systèmes
- Équipes disponibles : 2
- Contraintes : compétences, temps, budget, déplacements
- Vérité terrain : établie avant les tests
- Scénarios supplémentaires : au moins 30 jeux tenus à l'écart du développement

## 3. Règles anti-biais, intégrées après corrections du 2026-11-02

1. Vérité terrain indépendante : nécessaire, mais insuffisante seule.
   Un test construit par l'équipe peut involontairement favoriser son IA.
2. Scénarios préparés indépendamment, données jamais utilisées pendant
   le développement, plusieurs essais. Un seul scénario avec 20 signalements
   peut montrer le fonctionnement d'un prototype, pas établir sa supériorité.
3. Règles de priorité et budget figés avant l'expérience.
   Les systèmes n'accèdent pas aux véritables identifiants des huit incidents.
4. Évaluateur indépendant : il prépare les incidents, leurs caractéristiques,
   les signalements associés et les contraintes opérationnelles.
5. Comparaison isolée : une solution classique regroupe les signalements par
   règles géographiques, temporelles et textuelles. CityResolve utilise les
   modèles IA pour réconcilier les informations. Les deux solutions utilisent
   ensuite le même algorithme d'optimisation pour proposer les interventions.
   Cela isole la contribution réelle de l'IA, et non celle de l'optimiseur.
6. Information nouvelle injectée : les systèmes doivent réévaluer le plan,
   mais ne le modifier que si les nouvelles données justifient réellement
   ce changement. Mesurer séparément : taux de révision correcte et taux
   de révision injustifiée.

## 4. Métriques et seuils de réussite proposés

Seuils préliminaires à enregistrer avant les essais. Ce ne sont pas
des résultats obtenus.

- F1 de regroupement des incidents : ≥ 0,90
- Gain de qualité d'allocation vs référence : ≥ 10 %
- Violations des contraintes opérationnelles : 0
- Incidents critiques oubliés : 0
- Résistance aux signalements contradictoires : à mesurer séparément

## 5. Points restant à définir avant tout essai

- Définition précise du score d'allocation : quelles unités, quels poids
  pour gravité, personnes touchées, temps, coût ?
- Catégories d'incidents critiques : qui les définit, selon quels critères ?
- Justification du seuil de 10 % : pourquoi 10 %, et pas 5 % ou 20 % ?
- Source des 30 jeux tenus à l'écart : un seul évaluateur pour tous
  les jeux reste un risque de biais, même indépendant du développement.
- Seuil de révision justifiée pour l'information nouvelle : à quel
  changement de priorité un plan doit-il, ou ne doit-il pas, changer ?

## 6. Règle d'évaluation en quatre niveaux, posée par l'utilisateur

- Niveau 1 — Idée : le mécanisme est décrit.
- Niveau 2 — Prototype : le mécanisme fonctionne sur un cas.
- Niveau 3 — Preuve : une expérience indépendante démontre une amélioration.
- Niveau 4 — Impact : la solution améliore réellement une situation dans
  son environnement d'utilisation.

À ce jour, CityResolve et WaterLens sont au Niveau 1 dans ce travail.
Hypothèses formulées, systèmes ni construits, ni validés.

## 7. Questions ouvertes, même en cas de succès au Niveau 3

Un succès expérimental ne prouverait pas encore une transformation des villes.
Il resterait à répondre à :

1. Une collectivité utilisera-t-elle réellement les plans proposés ?
2. Ces plans entraîneront-ils de meilleures interventions ?
3. Les gains seront-ils supérieurs aux coûts d'exploitation du système ?
4. Notre contribution est-elle meilleure que la recherche et les plateformes
   déjà existantes, notamment Ushahidi pour la collecte et la gestion
   d'informations de crise ?

## 8. Règle de décision

Le choix de CityResolve comme premier candidat à tester n'est pas définitif.
Si une solution existante réalise déjà le mécanisme central aussi bien,
ou si WaterLens présente une meilleure possibilité d'innovation mesurable,
la recommandation changera.

Objectif : découvrir, preuves à l'appui, quel projet mérite réellement
d'être choisi. Pas défendre le projet choisi.

## 9. Corrections méthodologiques associées, 2026-11-02

- WaterLens : ne pas maximiser seulement le taux de refus correct.
  Une IA qui refuse systématiquement obtient un bon score de sécurité
  et ne sert à rien. Mesurer simultanément : précision sur les mesures
  acceptées, proportion de mesures acceptées, taux d'erreurs dangereuses.
  Compromis fiabilité / utilité.
- LearningProbe : ne pas comparer deux tuteurs sur les mêmes élèves
  et les mêmes exercices. Les élèves progressent parce qu'ils ont déjà
  rencontré la question. Répartir les participants entre deux groupes
  comparables, utiliser des exercices inédits, mesurer les apprentissages
  transférables, pas seulement la réussite immédiate.
