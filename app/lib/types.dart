// Types partagés du bac à sable CityResolve (données fictives).
import 'policy.dart';

/// Un signalement citoyen (donnée d'entrée, possibly bruitée).
class Report {
  final String id;
  final String text;
  final String category;
  final double x; // km, grille 0..5
  final double y;
  final int t; // minutes depuis début du scénario
  final int? severityHint; // 1..5 ou null = INCONNUE (jamais déduite)
  final int? exposureHint; // bande 0..4 ou null = inconnue
  final String? photo; // mediaId (24 hex, voir lib/media.dart) si photo
  // téléversée, sinon étiquette libre historique ; jamais d'octets ici
  final String source; // scenario | manuel | injection (provenance)
  final String? receivedAt; // ISO-8601 UTC de réception serveur (suivi
  // public) ; null pour les signalements de scénario et l'historique
  final double? gpsLat; // relevé GPS navigateur (degrés), null si saisie
  final double? gpsLon; // manuelle sur la grille ; x/y restent la référence
  final double? gpsAccuracy; // précision annoncée (mètres), si fournie

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
      );
}

/// Groupe de signalements produit par le regroupement.
class Group {
  final String id;
  final List<String> reportIds;
  final double confidence; // 0..1 (min similarité interne ; 0 si singleton)
  final bool singleton;
  final bool abstained;
  final String method; // classique | meta
  final bool uncertain; // fusion/séparation à vérifier, jamais imposée en silence
  final List<String> uncertaintyReasons;
  final String? justification; // proposition Meta (texte du modèle), sinon null

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

/// Statuts de provenance/vérification d'un attribut d'incident.
/// declaree : une seule valeur déclarée ; estimee : valeurs proches
/// agrégées (max) ; contradictoire : valeurs incompatibles conservées,
/// valeur tranchée = null ; inconnue : aucune valeur déclarée.
const statusDeclaree = 'declaree';
const statusEstimee = 'estimee';
const statusContradictoire = 'contradictoire';
const statusInconnue = 'inconnue';

/// Incident reconstitué (proposition, attributs estimés).
class Incident {
  final String id;
  final List<String> reportIds;
  final int? severity; // 1..5 ou null = inconnue/contradictoire (jamais fabriquée)
  final String severityStatus;
  final List<int> severityValues; // valeurs déclarées conservées (provenance)
  final int? exposure; // bande proposée ou null = inconnue/contradictoire
  final String exposureStatus;
  final List<int> exposureValues;
  final String domain;
  final bool domainConflict; // catégories déclarées à égalité sur 2 domaines
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
  // -1 = S5 (escalade), -2 = gravité à vérifier (jamais d'échéance fabriquée).
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

/// Équipe d'intervention.
class Team {
  final String id;
  final Set<String> domains;
  const Team(this.id, this.domains);
  Map<String, dynamic> toJson() => {'id': id, 'domains': domains.toList()};
}

List<Team> defaultTeams() => teamDomains.entries
    .map((e) => Team(e.key, e.value.toSet()))
    .toList();

/// Une tâche planifiée.
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

/// Plan d'affectation (proposition calculée, pas une décision réelle).
class Plan {
  final List<Task> tasks;
  final Map<String, String> unassigned; // incident -> motif
  final List<String> escalations; // S5
  final double totalCost;
  final double q; // Q planifié (attributs proposés)
  final bool feasible;
  final List<String> violations;
  final Map<String, String> justifications;
  final String planId; // identifiant permanent (ex. PLAN-3), jamais réattribué
  final int version; // numéro de version monotone (persisté)
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

/// Incident de vérité terrain (scénarios DEV visibles uniquement).
class TruthIncident {
  final String id;
  final Set<String> reportIds;
  final int severity;
  final int exposure; // bande 0..4 (toujours connue en DEV)
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

/// Scénario DEV visible : signalements + vérité (fictifs).
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
