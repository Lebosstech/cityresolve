# Dossiers de test DEV du harnais — JAMAIS des jeux tenus à l'écart

- multi_split_dev : copie des 5 cas multi-split déjà utilisés en
  développement, groupes classiques et classiques-split déjà publiés
  dans phase4-multi-split. L'horodatage truth_created_utc de cette
  copie (2026-11-02T00:00:00Z) est un horodatage de test du harnais,
  pas une preuve de la chronologie d'origine. La référence de
  contrôle est phase4-multi-split/data/final_f1.json, publié avant
  cette mission. Aucune équipe, aucun budget, aucune échéance
  d'allocation n'est défini dans ces scénarios : Q est donc null,
  par construction, et ce n'est pas un échec du harnais.
- q_synthetic : 2 scénarios synthétiques écrits pour tester le
  calcul Q, le gain apparié et l'intervalle de confiance. Valeurs
  attendues vérifiées à la main (voir RAPPORT_HARNAIS.md).
- critical_synthetic : 1 scénario synthétique avec un S5 et un S4,
  pour tester la violation automatique « S5 dispatché » et la
  distinction entre Q (qui exclut S5) et escalade.

Aucun de ces dossiers ne doit être réutilisé comme jeu tenu à
l'écart, ni présenté comme évaluation confirmatoire.
