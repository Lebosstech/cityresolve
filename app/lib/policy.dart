// CityResolve experimental policy.
//
// WARNING: all values below are LABORATORY
// HYPOTHESES ([H]) or NORMATIVE CONVENTIONS ([N]), taken from
// SPECIFICATION_D_SIMU.md. None is a real measurement ([E] = 0).
// The scientific protocol remains NOT FROZEN.

/// Q score weights: 65% severity, 35% exposure (V1.5 proposal, not validated).
const double qWeightSeverity = 0.65;
const double qWeightExposure = 0.35;

/// Deadlines in calendar minutes since the real appearance (S1..S4).
/// S5: no deadline, immediate human escalation, never planned.
const Map<int, int> deadlinesMin = {
  1: 7 * 24 * 60,
  2: 72 * 60,
  3: 24 * 60,
  4: 4 * 60,
};

/// Exposure bands E (distinct people). Unknown = null, never 0.
int exposureBand(int persons) {
  if (persons <= 0) return 0;
  if (persons <= 9) return 1;
  if (persons <= 49) return 2;
  if (persons <= 199) return 3;
  return 4;
}

/// Decision E value when exposure is unknown (conservative, symmetric).
const int unknownExposureDecision = 4;

/// Decision S value for priority computation only when severity
/// is unknown/conflicting. Allows NO automatic dispatch:
/// these incidents require verification (see optimizer.dart).
const int unknownSeverityDecision = 4;

/// Weight w_i of an S1..S4 incident for the Q score.
double incidentWeight(int severity, int exposureBandValue) {
  return qWeightSeverity * (severity / 4.0) +
      qWeightExposure * (exposureBandValue / 4.0);
}

/// On-site intervention durations in minutes by severity [H].
const Map<int, int> siteDurationsMin = {1: 60, 2: 120, 3: 240, 4: 180};

/// Possible hidden multipliers (ground truth, invisible) [H].
const List<double> hiddenMultipliers = [0.8, 1.0, 1.25];

/// Travel: 5x5 km grid, Manhattan, 20 km/h => 3 min/km [H].
const double gridSizeKm = 5.0;
const double travelMinPerKm = 3.0;

/// Costs and budget (fictitious units) [N].
const double siteRatePerHour = 10.0;
const double travelRatePerKm = 2.0;
const double budgetUnits = 120.0;

/// Availability: 08:00-16:00 every calendar day, 14-day horizon [N].
const int dayStartMin = 8 * 60;
const int dayEndMin = 16 * 60;
const int horizonDays = 14;
const int arrivalDays = 7;

/// Skills of the two teams [N].
const Map<String, List<String>> teamDomains = {
  'equipe-1': ['voirie', 'espaces-verts'],
  'equipe-2': ['voirie', 'reseaux'],
};

/// DECLARED category of the report -> business domain.
/// No severity is inferred from the category (removed: the old
/// categoryDefaultSeverity table fabricated a silent severity).
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

/// Development grid of the classic comparator (visible DEV).
const List<double> devDistMaxM = [100.0, 250.0, 500.0];
const List<double> devDeltaTMaxH = [1.0, 6.0, 24.0];
const List<double> devSimMin = [0.65, 0.75, 0.85];

/// Candidate thresholds (provisional, not validated): review +5 Q, cosmetic 30 min.
const double revisionThresholdQ = 5.0;
const int cosmeticShiftMin = 30;

/// Absolute deadline (minutes) since the real appearance. -1 for S5 (escalation).
int deadlineAt(int severity, int firstArrivalMin) {
  final d = deadlinesMin[severity];
  if (d == null) return -1;
  return firstArrivalMin + d;
}
