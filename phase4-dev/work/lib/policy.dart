// Politique expérimentale CityResolve.
//
// ATTENTION : toutes les valeurs ci-dessous sont des HYPOTHÈSES DE
// LABORATOIRE ([H]) ou des CONVENTIONS NORMATIVES ([N]), reprises de
// SPECIFICATION_D_SIMU.md. Aucune n'est une mesure réelle ([E] = 0).
// Le protocole scientifique reste NON GELÉ.

/// Poids du score Q : 65 % gravité, 35 % exposition (proposition V1.5, non validée).
const double qWeightSeverity = 0.65;
const double qWeightExposure = 0.35;

/// Échéances en minutes calendaires depuis l'apparition réelle (S1..S4).
/// S5 : pas d'échéance, escalade humaine immédiate, jamais planifié.
const Map<int, int> deadlinesMin = {
  1: 7 * 24 * 60,
  2: 72 * 60,
  3: 24 * 60,
  4: 4 * 60,
};

/// Bandes d'exposition E (personnes distinctes). Inconnue = null, jamais 0.
int exposureBand(int persons) {
  if (persons <= 0) return 0;
  if (persons <= 9) return 1;
  if (persons <= 49) return 2;
  if (persons <= 199) return 3;
  return 4;
}

/// Valeur E de décision quand l'exposition est inconnue (conservateur, symétrique).
const int unknownExposureDecision = 4;

/// Valeur S de décision pour le seul calcul de priorité quand la gravité
/// est inconnue/contradictoire. N'autorise AUCUN dispatch automatique :
/// ces incidents exigent une vérification (voir optimizer.dart).
const int unknownSeverityDecision = 4;

/// Poids w_i d'un incident S1..S4 pour le score Q.
double incidentWeight(int severity, int exposureBandValue) {
  return qWeightSeverity * (severity / 4.0) +
      qWeightExposure * (exposureBandValue / 4.0);
}

/// Durées d'intervention sur site en minutes par gravité [H].
const Map<int, int> siteDurationsMin = {1: 60, 2: 120, 3: 240, 4: 180};

/// Multiplicateurs cachés possibles (vérité terrain, invisibles) [H].
const List<double> hiddenMultipliers = [0.8, 1.0, 1.25];

/// Déplacements : grille 5x5 km, Manhattan, 20 km/h => 3 min/km [H].
const double gridSizeKm = 5.0;
const double travelMinPerKm = 3.0;

/// Coûts et budget (unités fictives) [N].
const double siteRatePerHour = 10.0;
const double travelRatePerKm = 2.0;
const double budgetUnits = 120.0;

/// Disponibilités : 08:00-16:00 chaque jour calendaire, horizon 14 jours [N].
const int dayStartMin = 8 * 60;
const int dayEndMin = 16 * 60;
const int horizonDays = 14;
const int arrivalDays = 7;

/// Compétences des deux équipes [N].
const Map<String, List<String>> teamDomains = {
  'equipe-1': ['voirie', 'espaces-verts'],
  'equipe-2': ['voirie', 'reseaux'],
};

/// Catégorie DÉCLARÉE du signalement -> domaine métier.
/// Aucune gravité n'est déduite de la catégorie (supprimé : l'ancienne
/// table categoryDefaultSeverity fabriquait une gravité silencieuse).
const Map<String, String> categoryDomain = {
  'nid-de-poule': 'voirie',
  'chaussée': 'voirie',
  'eclairage': 'voirie',
  'fuite-eau': 'reseaux',
  'coupure-electrique': 'reseaux',
  'arbre': 'espaces-verts',
  'autre': 'voirie',
};
String categoryDomainOf(String category) =>
    categoryDomain[category] ?? 'voirie';

/// Grille de développement du comparateur classique (DEV visible).
const List<double> devDistMaxM = [100.0, 250.0, 500.0];
const List<double> devDeltaTMaxH = [1.0, 6.0, 24.0];
const List<double> devSimMin = [0.65, 0.75, 0.85];

/// Seuils candidats (provisoires, non validés) : révision +5 Q, cosmétique 30 min.
const double revisionThresholdQ = 5.0;
const int cosmeticShiftMin = 30;

/// Échéance absolue (minutes) depuis l'apparition réelle. -1 pour S5 (escalade).
int deadlineAt(int severity, int firstArrivalMin) {
  final d = deadlinesMin[severity];
  if (d == null) return -1;
  return firstArrivalMin + d;
}
