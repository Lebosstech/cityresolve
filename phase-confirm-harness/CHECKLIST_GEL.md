# CityResolve — Checklist de gel, à figer AVANT toute évaluation confirmatoire

Statut : protocole TOUJOURS NON GELÉ. Ce document liste ce qui doit être
figé, il ne fige rien par lui-même. Aucun seuil, aucune formule, aucune
politique n'a été modifié dans cette mission. Cocher un item exige une
décision explicite de l'utilisateur, datée et archivée, jamais une
déduction après avoir vu des résultats.

## 1. Politique Q principale

- [ ] Fonction Q principale déclarée avant les essais, indépendamment
      des résultats : formule annexe V1.1 inchangée, w = 0,65 × (S/4) +
      0,35 × (E/4), Q = 100 × Σ w × résolu / Σ w, pour S1 à S4 seulement.
- [ ] Poids 65/35 validés ou remplacés après revue métier externe :
      ce sont une hypothèse normative, pas une vérité scientifique.
- [ ] Règle préenregistrée pour référence nulle : gain relatif non
      défini, seul le gain absolu compte, avec un seuil absolu figé
      avant les essais.
- [ ] Seuil de gain relatif justifié avant les essais (proposition
      actuelle : ≥ 10 %, justification toujours à écrire : pourquoi
      10 %, et pas 5 % ou 20 %).
- [ ] Seuil de révision du plan figé (proposition actuelle : 5 points
      de Q) : changement requis si l'ancien plan devient infaisable,
      si une urgence critique apparaît, ou si le meilleur plan après
      injection dépasse l'ancien d'au moins ce seuil ; sinon, toute
      révision non motivée est pénalisée.
- [ ] Simulateur figé et versionné avant l'évaluation : durées,
      coûts, lieux de la vérité terrain, règles de faisabilité.
      Les choix du simulateur influencent les résultats, donc le
      simulateur lui-même doit être figé, comme les règles.

## 2. Analyses secondaires (annexe V1.2, 60 configurations)

- [ ] Grille de sensibilité conjointe préenregistrée, 60 configurations :
      poids gravité/exposition 100/0, 80/20, 65/35, 50/50, 0/100 ;
      gain relatif minimal 0 %, 5 %, 10 %, 15 % ;
      seuil de révision 0, 2, 5 points de Q.
- [ ] Politique principale déclarée séparément des analyses de
      robustesse. Tous les résultats publiés, y compris les
      défavorables. Si la politique principale échoue mais qu'une
      configuration de robustesse réussit, la conclusion est
      « supériorité sous cette politique seulement », jamais
      « supériorité ».
- [ ] Gain absolu en points de Q et intervalle de confiance toujours
      publiés avec le gain relatif, qui est trompeur quand la
      référence approche zéro.
- [ ] Analyse de sensibilité du simulateur : durées et coûts +20 %
      et +50 %, vérification si le classement change et si les plans
      deviennent infaisables.
- [ ] Trois effets mesurés séparément : (1) amélioration de la
      reconstitution des incidents, (2) amélioration de la décision
      d'allocation à optimiseur identique, (3) amélioration effective
      du résultat simulé compte tenu des incertitudes sur durées
      et coûts. Un meilleur F1 ne prouve pas une meilleure allocation.
- [ ] Révision d'information nouvelle mesurée séparément : taux de
      révision correcte ET taux de révision injustifiée.

## 3. Seuils préliminaires existants (protocole V1, section 4)

- [ ] F1 de regroupement ≥ 0,90.
- [ ] Gain de qualité d'allocation vs référence ≥ 10 % (voir section 1
      pour la justification restant à figer).
- [ ] Violations des contraintes opérationnelles : 0.
- [ ] Incidents critiques oubliés : 0, avec la limite suivante, à
      rappeler dans toute conclusion : même zéro oubli sur 30
      incidents critiques laisse une borne supérieure approximative
      du taux d'omission proche de 10 % à 95 % de confiance
      (règle de trois : 3/30), calculée sur le nombre effectif de
      S4/S5 dans l'ensemble B, pas sur le nombre de scénarios.
- [ ] Résistance aux signalements contradictoires : mesurée séparément.
- [ ] Taux de fausses alertes critiques publié, pour éviter
      « tout est critique ».

## 4. Règles de comptage (à figer, jamais à ajuster après les sorties)

- [ ] Unité de vérité : sous-signalement ORIGINE:FAMILLE, un par
      famille explicite. Un signalement brut n'est jamais l'unité.
- [ ] Survie du secondaire : vrai si et seulement si une méthode
      produit un incident contenant le sous-signalement secondaire
      ET aucun sous-signalement d'une autre famille, quelle que soit
      l'origine ; un singleton secondaire compte comme survie.
- [ ] Couverture exacte : fraction des incidents vrais reproduits
      exactement (même ensemble de sous-signalements).
- [ ] Nombre d'incidents produits : toujours publié, à côté du F1.
- [ ] F1 adapté : paires de sous-signalements de MÊME famille
      uniquement. Limite démontrée par le multi-split et à rappeler
      dans chaque rapport : le classique affiche F1 1,0 dans les
      5 cas multi-split tout en perdant le secondaire dans les
      3 cas multi-problèmes, couverture exacte 0,0. Le F1 adapté
      seul est donc trompeur et ne doit jamais être lu sans survie,
      nombre d'incidents et couverture exacte.
- [ ] Cas dégénéré documenté : quand aucun incident vrai ni produit
      ne contient de paire de même famille, le F1 est conventionnellement
      1,0 avec zéro paire ; le harnais le signale par
      degenerate_no_pairs = true. Ce 1,0 ne signifie rien seul.
- [ ] Comparateur : méthode classique compétitive, définie avant les
      essais (règles géographiques, temporelles et textuelles, avec
      quelles ressources, quelles limites), même optimiseur, mêmes
      données accessibles. Pas un système naïf de mots-clés, sinon
      le concurrent est artificiellement faible.
- [ ] Référence sémantique vraiment indépendante : le dictionnaire
      de synonymes actuel a été écrit en connaissant les cas testés,
      il ne compte PAS comme indépendant. Une référence indépendante
      doit être préparée sans voir les jeux tenus à l'écart, par une
      personne ou une source distincte du développement.

## 5. Gestion des cas particuliers

- [ ] S5 : danger vital imminent, hors plan, orientation humaine
      immédiate, jamais dispatché automatiquement aux deux équipes.
      S5 exclu de Q, évalué séparément sur détection et escalade.
      Un S5 dans un plan d'équipe = violation automatique.
- [ ] S4 : planifié avant délai si faisable, sinon signalé comme non
      réalisable et escaladé ; l'alerte n'est pas une résolution.
- [ ] Critiques = S4 et S5. Gravité inconnue explicite, jamais déduite
      d'une catégorie. Exposition inconnue marquée inconnue, jamais 0.
      Si gravité ou exposition d'un incident S1-S4 est inconnue, Q est
      indéfini pour ce scénario, jamais calculé avec 0.
- [ ] Cas vague : aucune famille explicite secondaire, vérité = 1
      incident, pas de découpage automatique, revue humaine requise.
      Un découpage automatique sur une mention vague est une faute.
- [ ] Cas faux : même problème dit deux fois, vérité = 1 incident,
      pas de découpage à l'aveugle.
- [ ] Cas multi-problème : chaque problème explicite distinct doit
      survivre comme incident propre, sinon le plan perd une tâche.
- [ ] Signalements manuels : opérationnels, mais exclus du F1
      (règle Phase 2, à confirmer au gel si elle s'applique aux jeux
      tenus à l'écart).

## 6. Jeux tenus à l'écart

- [ ] Au moins 30 jeux tenus à l'écart du développement (ensemble A,
      performance opérationnelle), jamais utilisés pendant le
      développement, préparés indépendamment.
- [ ] Au moins trois contributeurs indépendants pour l'ensemble A,
      fréquences de gravité documentées et justifiées, non imposées
      par un quota par scénario.
- [ ] Ensemble B séparé, résistance aux situations critiques,
      volontairement enrichi en S4 et S5, avec cas ambigus, urgences
      réelles simulées et fausses alertes plausibles. Mesures
      séparées : rappel des S4/S5, faux positifs, rapidité d'escalade.
      Les résultats de B ne sont JAMAIS fusionnés avec A pour gonfler
      le rappel. La fréquence artificielle de B est déclarée.
- [ ] Aucun quota obligatoire de S5 par scénario : forcer un S5 dans
      chaque scénario fabriquerait une fréquence artificielle des
      urgences vitales.
- [ ] Provenance indépendante de chaque jeu : auteur, date de
      création, hash du fichier de vérité, statut
      jamais-utilisé-en-développement, enregistrés avant toute sortie.
- [ ] Répétitions pour la variabilité : nombre de répétitions par
      scénario et par méthode figé avant les essais, avec règle de
      rapport des échecs (toute inférence en échec compte, jamais
      relancée silencieusement jusqu'à succès).
- [ ] Vérité horodatée avant les sorties à évaluer : le harnais
      refuse toute évaluation dont la vérité n'est pas strictement
      antérieure aux sorties. Aucune modification de vérité après
      avoir vu une sortie.

## 7. Ce que le gel ne change pas

- [ ] Un succès en simulation ne prouve pas un impact réel dans une
      ville. Aucune revendication d'impact réel à partir d'une
      simulation. Un pilote indépendant resterait nécessaire.
- [ ] Un protocole excellent peut démontrer que l'IA n'apporte
      presque aucune valeur. Le résultat négatif, s'il est conforme
      au protocole gelé, est un résultat valide.
- [ ] Après le gel, toute modification de seuil, de formule ou de
      règle de comptage invalide l'évaluation en cours et exige un
      nouveau gel, daté, avec la raison écrite.
