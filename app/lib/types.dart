// Shared types of the CityResolve sandbox (fictitious data).
import 'policy.dart';

/// A citizen report (input data, possibly noisy).
class Report {
  final String id;
  final String text;
  final String category;
  final double x; // km, grid 0..5
  final double y;
  final int t; // minutes since the start of the scenario
  final int? severityHint; // 1..5 or null = UNKNOWN (never inferred)
  final int? exposureHint; // band 0..4 or null = unknown
  final String? photo; // mediaId (24 hex, see lib/media.dart) if photo
  // uploaded, otherwise free historical label; never bytes here
  final String source; // scenario | manuel | injection (origin)
  final String? receivedAt; // ISO-8601 UTC of server receipt (tracking
  // public); null for scenario reports and history
  final double? gpsLat; // browser GPS reading (degrees), null if manual entry
  final double? gpsLon; // on the grid; x/y remain the reference
  final double? gpsAccuracy; // stated accuracy (metres), if provided
  final String? verificationNote; // municipal verification note (human),
  // null = not verified; never changes the computed status, only documented
  final String? verifiedAt; // ISO-8601 UTC of the verification, if done

  const Report({
    required this.id,
    required this.text,
    required this.category,
    required this.x,
    required this.y,
    required this.t,
    this.severityHint,
    this.exposureHint,
    this.photo,
    this.source = 'scenario',
    this.receivedAt,
    this.gpsLat,
    this.gpsLon,
    this.gpsAccuracy,
    this.verificationNote,
    this.verifiedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'category': category,
        'x': x,
        'y': y,
        't': t,
        'severityHint': severityHint,
        'exposureHint': exposureHint,
        'photo': photo,
        'source': source,
        'receivedAt': receivedAt,
        'gpsLat': gpsLat,
        'gpsLon': gpsLon,
        'gpsAccuracy': gpsAccuracy,
        'verificationNote': verificationNote,
        'verifiedAt': verifiedAt,
      };

  static Report fromJson(Map<String, dynamic> j) => Report(
        id: j['id'] as String,
        text: (j['text'] ?? '') as String,
        category: (j['category'] ?? 'autre') as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        t: (j['t'] as num).toInt(),
        severityHint: j['severityHint'] as int?,
        exposureHint: j['exposureHint'] as int?,
        photo: j['photo'] as String?,
        source: (j['source'] ?? 'scenario') as String,
        receivedAt: j['receivedAt'] as String?,
        gpsLat: (j['gpsLat'] as num?)?.toDouble(),
        gpsLon: (j['gpsLon'] as num?)?.toDouble(),
        gpsAccuracy: (j['gpsAccuracy'] as num?)?.toDouble(),
        verificationNote: j['verificationNote'] as String?,
        verifiedAt: j['verifiedAt'] as String?,
      );
}

/// Group of reports produced by grouping.
class Group {
  final String id;
  final List<String> reportIds;
  final double confidence; // 0..1 (min internal similarity; 0 if singleton)
  final bool singleton;
  final bool abstained;
  final String method; // classique | meta
  final bool uncertain; // merge/split to verify, never imposed silently
  final List<String> uncertaintyReasons;
  final String? justification; // Meta proposal (model text), otherwise null

  const Group({
    required this.id,
    required this.reportIds,
    required this.confidence,
    required this.singleton,
    this.abstained = false,
    this.method = 'classique',
    this.uncertain = false,
    this.uncertaintyReasons = const [],
    this.justification,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'reportIds': reportIds,
        'confidence': confidence,
        'singleton': singleton,
        'abstained': abstained,
        'method': method,
        'uncertain': uncertain,
        'uncertaintyReasons': uncertaintyReasons,
        'justification': justification,
      };

  static Group fromJson(Map<String, dynamic> j) => Group(
        id: j['id'] as String,
        reportIds: (j['reportIds'] as List).map((e) => '$e').toList(),
        confidence: (j['confidence'] as num).toDouble(),
        singleton: j['singleton'] as bool? ?? false,
        abstained: j['abstained'] as bool? ?? false,
        method: (j['method'] ?? 'classique') as String,
        uncertain: j['uncertain'] as bool? ?? false,
        uncertaintyReasons:
            (j['uncertaintyReasons'] as List? ?? []).map((e) => '$e').toList(),
        justification: j['justification'] as String?,
      );
}

/// Origin/verification statuses of an incident attribute.
/// declaree: a single declared value; estimee: close values
/// aggregated (max); contradictoire: incompatible values kept,
/// decided value = null; inconnue: no declared value.
const statusDeclaree = 'declaree';
const statusEstimee = 'estimee';
const statusContradictoire = 'contradictoire';
const statusInconnue = 'inconnue';

/// Reconstructed incident (proposal, estimated attributes).
class Incident {
  final String id;
  final List<String> reportIds;
  final int? severity; // 1..5 or null = unknown/conflicting (never fabricated)
  final String severityStatus;
  final List<int> severityValues; // declared values kept (provenance)
  final int? exposure; // proposed band or null = unknown/conflicting
  final String exposureStatus;
  final List<int> exposureValues;
  final String domain;
  final bool domainConflict; // declared categories tied across 2 domains
  final double x, y;
  final int firstSeen;
  final double confidence;

  const Incident({
    required this.id,
    required this.reportIds,
    required this.severity,
    required this.exposure,
    required this.domain,
    required this.x,
    required this.y,
    required this.firstSeen,
    required this.confidence,
    this.severityStatus = statusInconnue,
    this.severityValues = const [],
    this.exposureStatus = statusInconnue,
    this.exposureValues = const [],
    this.domainConflict = false,
  });

  bool get severityUnknown => severity == null;
  bool get exposureUnknown => exposure == null;
  int get severityForDecision => severity ?? unknownSeverityDecision;
  int get exposureForDecision => exposure ?? unknownExposureDecision;
  double get weight => incidentWeight(severityForDecision, exposureForDecision);
  // -1 = S5 (escalation), -2 = severity to verify (never a fabricated deadline).
  int get deadline =>
      severity == null ? -2 : deadlineAt(severity!, firstSeen);

  Map<String, dynamic> toJson() => {
        'id': id,
        'reportIds': reportIds,
        'severity': severity,
        'severityStatus': severityStatus,
        'severityValues': severityValues,
        'severityUnknown': severityUnknown,
        'severityForDecision': severityForDecision,
        'exposure': exposure,
        'exposureStatus': exposureStatus,
        'exposureValues': exposureValues,
        'exposureUnknown': exposureUnknown,
        'domain': domain,
        'domainConflict': domainConflict,
        'x': x,
        'y': y,
        'firstSeen': firstSeen,
        'deadline': deadline,
        'confidence': confidence,
        'weight': weight,
      };

  static Incident fromJson(Map<String, dynamic> j) => Incident(
        id: j['id'] as String,
        reportIds: (j['reportIds'] as List).map((e) => '$e').toList(),
        severity: j['severity'] as int?,
        exposure: j['exposure'] as int?,
        domain: (j['domain'] ?? 'voirie') as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        firstSeen: (j['firstSeen'] as num).toInt(),
        confidence: (j['confidence'] as num).toDouble(),
        severityStatus: (j['severityStatus'] ?? statusInconnue) as String,
        severityValues:
            (j['severityValues'] as List? ?? []).map((e) => (e as num).toInt()).toList(),
        exposureStatus: (j['exposureStatus'] ?? statusInconnue) as String,
        exposureValues:
            (j['exposureValues'] as List? ?? []).map((e) => (e as num).toInt()).toList(),
        domainConflict: j['domainConflict'] as bool? ?? false,
      );
}

/// Response team.
class Team {
  final String id;
  final Set<String> domains;
  const Team(this.id, this.domains);
  Map<String, dynamic> toJson() => {'id': id, 'domains': domains.toList()};
}

List<Team> defaultTeams() => teamDomains.entries
    .map((e) => Team(e.key, e.value.toSet()))
    .toList();

/// A planned task.
class Task {
  final String incidentId;
  final String teamId;
  final int order;
  final int startMin;
  final int endMin;
  final double travelKm;
  final double cost;
  const Task({
    required this.incidentId,
    required this.teamId,
    required this.order,
    required this.startMin,
    required this.endMin,
    required this.travelKm,
    required this.cost,
  });
  Map<String, dynamic> toJson() => {
        'incidentId': incidentId,
        'teamId': teamId,
        'order': order,
        'startMin': startMin,
        'endMin': endMin,
        'travelKm': travelKm,
        'cost': cost,
      };
  static Task fromJson(Map<String, dynamic> j) => Task(
        incidentId: j['incidentId'] as String,
        teamId: j['teamId'] as String,
        order: (j['order'] as num).toInt(),
        startMin: (j['startMin'] as num).toInt(),
        endMin: (j['endMin'] as num).toInt(),
        travelKm: (j['travelKm'] as num).toDouble(),
        cost: (j['cost'] as num).toDouble(),
      );
}

/// Assignment plan (computed proposal, not a real decision).
class Plan {
  final List<Task> tasks;
  final Map<String, String> unassigned; // incident -> reason
  final List<String> escalations; // S5
  final double totalCost;
  final double q; // planned Q (proposed attributes)
  final bool feasible;
  final List<String> violations;
  final Map<String, String> justifications;
  final String planId; // permanent identifier (e.g. PLAN-3), never reassigned
  final int version; // monotonic version number (persisted)
  const Plan({
    required this.tasks,
    required this.unassigned,
    required this.escalations,
    required this.totalCost,
    required this.q,
    required this.feasible,
    required this.violations,
    required this.justifications,
    this.planId = '',
    this.version = 0,
  });

  Plan withIdentity(String id, int v) => Plan(
      tasks: tasks,
      unassigned: unassigned,
      escalations: escalations,
      totalCost: totalCost,
      q: q,
      feasible: feasible,
      violations: violations,
      justifications: justifications,
      planId: id,
      version: v);

  Map<String, dynamic> toJson() => {
        'planId': planId,
        'version': version,
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'unassigned': unassigned,
        'escalations': escalations,
        'totalCost': totalCost,
        'q': q,
        'feasible': feasible,
        'violations': violations,
        'justifications': justifications,
      };

  static Plan fromJson(Map<String, dynamic> j) => Plan(
        tasks: (j['tasks'] as List)
            .map((e) => Task.fromJson(e as Map<String, dynamic>))
            .toList(),
        unassigned: (j['unassigned'] as Map? ?? {})
            .map((k, v) => MapEntry('$k', '$v')),
        escalations:
            (j['escalations'] as List? ?? []).map((e) => '$e').toList(),
        totalCost: (j['totalCost'] as num).toDouble(),
        q: (j['q'] as num).toDouble(),
        feasible: j['feasible'] as bool? ?? true,
        violations:
            (j['violations'] as List? ?? []).map((e) => '$e').toList(),
        justifications: (j['justifications'] as Map? ?? {})
            .map((k, v) => MapEntry('$k', '$v')),
        planId: (j['planId'] ?? '') as String,
        version: (j['version'] as num? ?? 0).toInt(),
      );
}

/// Ground-truth incident (visible DEV scenarios only).
class TruthIncident {
  final String id;
  final Set<String> reportIds;
  final int severity;
  final int exposure; // band 0..4 (always known in DEV)
  final String domain;
  final double x, y;
  final int firstArrival;
  final double durationMult;
  const TruthIncident({
    required this.id,
    required this.reportIds,
    required this.severity,
    required this.exposure,
    required this.domain,
    required this.x,
    required this.y,
    required this.firstArrival,
    required this.durationMult,
  });
  int get deadline => deadlineAt(severity, firstArrival);
  double get weight => incidentWeight(severity, exposure);
  Map<String, dynamic> toJson() => {
        'id': id,
        'reportIds': reportIds.toList(),
        'severity': severity,
        'exposure': exposure,
        'domain': domain,
        'x': x,
        'y': y,
        'firstArrival': firstArrival,
        'durationMult': durationMult,
      };
}

/// Visible DEV scenario: reports + truth (fictitious).
class Scenario {
  final String id;
  final String label;
  final List<Report> reports;
  final List<TruthIncident> truth;
  final int? seed;
  const Scenario({
    required this.id,
    required this.label,
    required this.reports,
    required this.truth,
    this.seed,
  });
}
