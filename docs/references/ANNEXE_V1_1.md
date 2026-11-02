# CityResolve — Annexe V1.1 : score et criticité

**Préenregistrement proposé — Niveau 1 (idée).** À figer et archiver **avant** de créer les scénarios cachés. Complète `PROTOCOLE_V1.md` ; aucun résultat mesuré.

## 1. Grille de criticité (définie avant les essais)

| Niveau | Définition opérationnelle | Délai simulé* |
|---|---|---|
| **S1 — Mineur** | Défaut esthétique sans interruption ni danger crédible | 7 j |
| **S2 — Gêne locale** | Service dégradé ou obstacle contournable, sans menace sérieuse | 72 h |
| **S3 — Important** | Interruption significative ou risque non immédiat documenté | 24 h |
| **S4 — Critique** | Service essentiel indisponible ou risque sérieux crédible, non vital et non imminent | 4 h |
| **S5 — Urgence vitale** | Danger crédible et imminent pour des vies ou de graves blessures | Hors plan : **orientation humaine immédiate** |

**Incidents critiques = S4 et S5.** Les S5 vont vers les services compétents, jamais en dispatch automatique aux deux équipes. Un S4 doit être planifié avant délai **si faisable**, sinon signalé comme non réalisable et escaladé ; l'alerte n'est pas une résolution. Les délais* servent exclusivement au banc d'essai et ne sont **pas des normes de sécurité**.

**Exposition `E` :** personnes **distinctes** touchées, et non nombre de messages : `0` (aucune), `1` (1–9), `2` (10–49), `3` (50–199), `4` (200+). Toute valeur inconnue est marquée **inconnue**, jamais `0`. La classification de vérité terrain est documentée par des évaluateurs indépendants, cachée aux deux systèmes.

## 2. Score d'allocation (0 à 100)

Pour chaque incident réel `i` classé S1–S4 :

`w_i = 0,65 × (S_i / 4) + 0,35 × (E_i / 4)`

`Q(P) = 100 × [Σ_i w_i × 1(incident i effectivement résolu avant d_i)] / Σ_i w_i`

La fonction `1(...)` vaut 1 si le fait est confirmé, 0 sinon : incident manqué, fusion erronée, action inefficace ou retard = **0**. Les S5 sont exclus de `Q` et évalués séparément sur la détection et l'escalade.

**Temps, trajets, budget, coût d'intervention, compétences et disponibilité des deux équipes sont des contraintes**, pas des points de bonus. Une violation réelle est un **échec de faisabilité** ; toute intervention est évaluée avec les durées, coûts et lieux de la vérité terrain. Les deux méthodes utilisent **le même optimiseur**. Les poids 65/35 sont une **hypothèse normative**, non une vérité scientifique ; une analyse de sensibilité est obligatoire.

## 3. Règles de comparaison et de révision

- **Référence :** méthode classique de regroupement géographique, temporel et textuel, avec le même optimiseur, les mêmes données accessibles et ressources. Évaluation sur **au moins 30 scénarios cachés**, préparés par **trois contributeurs indépendants ou plus**.
- **Gain visé :** `(moyenne Q_IA − moyenne Q_référence) / moyenne Q_référence ≥ 10 %` si référence positive ; publier aussi l'écart **en points**, les résultats appariés et l'incertitude statistique. Ce seuil de 10 % est provisoire et doit être justifié **avant** les tests.
- **Autres seuils prévus :** F1 de regroupement `≥ 0,90`, `0` violation de contrainte, `0` S4/S5 oublié ; publier également le taux de **fausses alertes critiques** (pour éviter « tout est critique »). Fixer à l’avance des quotas de S4/S5 et de cas non critiques ; sans eux, « zéro critique oublié » peut être trivial.
- **Information nouvelle :** mesurer **révisions correctes** et **révisions injustifiées** séparément. Changement requis si l'ancien plan devient infaisable, si une urgence critique apparaît, ou si le meilleur plan après injection dépasse l'ancien d'au moins **5 points de Q** ; sinon, une révision non motivée est pénalisée. Critère à figer avant les scénarios.

**Limite :** même des résultats positifs n'établiraient pas un impact dans une ville réelle. Un pilote indépendant serait encore nécessaire.
