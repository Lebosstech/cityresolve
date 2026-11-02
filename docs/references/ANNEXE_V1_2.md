# CityResolve — Annexe V1.2 : sensibilité, ensembles critiques, et code autorisé

Document de prévalidation. Aucun résultat expérimental acquis.
Complète PROTOCOLE_V1.md et l'annexe V1.1, sans les modifier.
Statut actuel : Niveau 1 — Idée.

## 1. Analyse de sensibilité conjointe, préenregistrée

Les trois seuils ne sont pas indépendants : poids 65/35, gain relatif
10 %, seuil de révision 5 points de Q. Ils doivent être évalués ensemble.

Grille préenregistrée : 60 configurations.
- Gravité / exposition : 100/0, 80/20, 65/35, 50/50, 0/100
- Gain relatif minimal : 0 %, 5 %, 10 %, 15 %
- Seuil de révision du plan : 0, 2, 5 points de Q

Règles anti-sélection opportuniste :
- Une politique principale est déclarée avant les essais, indépendamment
  des résultats. Les autres configurations sont des analyses de robustesse.
- Tous les résultats sont publiés, y compris les défavorables.
- Si la politique principale échoue mais qu'une configuration de robustesse
  réussit, la conclusion n'est pas « supériorité », mais « supériorité
  sous cette politique seulement ».

Gain relatif : trompeur quand le score de référence approche zéro.
Publier toujours aussi le gain absolu en points de Q et son intervalle
de confiance, avec une règle explicite préenregistrée pour le cas
référence nulle : gain relatif non défini, seul le gain absolu compte,
avec un seuil absolu à figer avant les essais.

## 2. Deux ensembles distincts, pas de quota S5 par scénario

Refus d'un quota obligatoire de S5 dans chaque scénario : S5 est un
danger vital imminent. Forcer chaque simulation de huit incidents à
contenir un S5 fabriquerait une fréquence artificielle des urgences
vitales, et pourrait rendre le système excessivement alarmiste tout
en paraissant performant.

### Ensemble A — Performance opérationnelle
- Au moins 30 scénarios cachés, plusieurs profils d'incidents,
  préparés par trois contributeurs indépendants ou davantage.
- Les fréquences de gravité sont documentées et justifiées, non imposées
  par un quota par scénario.

### Ensemble B — Résistance aux situations critiques
- Ensemble supplémentaire, volontairement enrichi en S4 et S5,
  avec des cas ambigus, des urgences réelles simulées et des fausses
  alertes plausibles.
- Mesures séparées : rappel des S4/S5, faux positifs, rapidité d'escalade.
- Les résultats de B ne sont pas fusionnés avec A pour gonfler le rappel.
  La fréquence artificielle de B est déclarée comme telle.

Zéro incident critique oublié : ne permet pas d'affirmer la sécurité.
Même zéro oubli sur 30 incidents critiques laisse une borne supérieure
approximative du taux d'omission proche de 10 % à 95 % de confiance
dans un échantillon indépendant (règle de trois : 3/30).
La borne réelle se calcule sur le nombre effectif de S4/S5 dans B,
pas sur le nombre de scénarios. Un jeu simulé ne démontre pas
la fiabilité sur le terrain.

## 3. Renommage : « résolution effective » → « intervention simulée achevée dans les contraintes »

R_i ne signifie plus qu'un problème urbain a été résolu dans la réalité.
R_i = 1 signifie : une intervention est prédite comme réalisable et
terminée dans les délais selon le simulateur figé.

Conséquence : tester les erreurs du simulateur lui-même.
Si les temps d'intervention sont trop optimistes, les deux systèmes
peuvent produire des plans irréalisables dans la réalité.
Analyse de sensibilité sur les durées et les coûts, par exemple
+20 % et +50 %, pour vérifier si le classement change et si les plans
deviennent infaisables.

## 4. Trois effets distincts à mesurer

CityResolve pourrait améliorer le regroupement sans améliorer l'allocation.
Exemple : le modèle identifie parfaitement les huit incidents, mais les
deux équipes ne peuvent en traiter que deux, et la solution classique
identifie déjà correctement les deux incidents prioritaires. L'amélioration
du F1 ne changerait alors aucune décision opérationnelle.

Mesurer séparément :
1. Amélioration de la reconstitution des incidents.
2. Amélioration de la décision d'allocation, à optimiseur identique.
3. Amélioration effective du résultat simulé, compte tenu des incertitudes
   sur les durées et les coûts.

Comparateur : une méthode classique compétitive, pas un système naïf
de mots-clés. Sinon, le concurrent est artificiellement faible.
Les capacités exactes du comparateur doivent être définies avant
les essais : règles géographiques, temporelles et textuelles, avec
quelles ressources, quelles limites.

## 5. Ce qui est verrouillé avant les premiers essais confirmatoires

- Fonction principale Q : à valider avec des critères métier externes.
- Grille de sensibilité : 60 configurations préenregistrées.
- Politique principale : à figer indépendamment des résultats.
- Incidents critiques : évaluation opérationnelle et test de résistance
  séparés.
- Révision de plan : taux de révision correcte ET injustifiée.
- Comparateur : méthode classique compétitive, même optimiseur.
- Vérité terrain : préparée indépendamment et tenue cachée.
- Impact : aucune revendication d'impact réel à partir d'une simulation.

## 6. Code : distinction autorisé / interdit

Objectif réel : empêcher les résultats expérimentaux d'influencer
les règles d'évaluation, pas interdire toute activité technique préparatoire.

Autorisé avant le verrouillage intégral :
- Développer un simulateur neutre.
- Infrastructure de journalisation.
- Outil de calcul des métriques.

Interdit avant le préenregistrement :
- Toute évaluation confirmatoire.
- Toute adaptation des modèles aux scénarios cachés.

Attention : les choix du simulateur lui-même (durées, coûts) influencent
les résultats. Le simulateur doit donc aussi être figé et versionné
avant l'évaluation confirmatoire, et la journalisation doit être immuable.

## 7. Risque stratégique, et décision

Rendre CityResolve scientifiquement plus rigoureux est nécessaire,
mais ne constitue pas une raison de le sélectionner.
Un protocole excellent peut parfaitement démontrer que l'IA n'apporte
presque aucune valeur.

Risque : investir tellement de temps à perfectionner la méthodologie
de CityResolve que WaterLens, LearningProbe ou un autre projet
ne bénéficient jamais d'une comparaison équivalente.

Décision de l'utilisateur, 2026-11-02 :
terminer le préenregistrement de CityResolve, puis établir un protocole
de preuve de profondeur comparable pour WaterLens, avant d'attribuer
la moindre préférence définitive.
