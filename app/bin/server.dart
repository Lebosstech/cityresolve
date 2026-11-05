// CityResolve server (sandbox): JSON API + static interface.
// Fictitious data only. Protocol NOT FROZEN. Port: --port, otherwise
// PORT environment variable, otherwise 8080. Listens on 0.0.0.0.
import 'dart:convert';
import 'dart:io';

import '../lib/audit.dart';
import '../lib/dashboard.dart';
import '../lib/grouping.dart';
import '../lib/incidents.dart';
import '../lib/media.dart';
import '../lib/meta_connector.dart';
import '../lib/metrics.dart';
import '../lib/optimizer.dart';
import '../lib/oracle.dart';
import '../lib/policy.dart';
import '../lib/security.dart';
import '../lib/mongo_store.dart';
import '../lib/scenarios.dart';
import '../lib/server_lock.dart';
import '../lib/simulator.dart';
import '../lib/store.dart';
import '../lib/types.dart';

const String appVersion = '0.2.0-dev';

class AppState {
  Scenario? scenario;
  List<Report> reports = [];
  List<TruthIncident> truth = [];
  Set<String> manualReports = {}; // outside ground truth
  Map<String, dynamic> groupParams = {
    'distMaxM': 250.0,
    'deltaTMaxH': 6.0,
    'simMin': 0.75
  };
  List<Group> groups = [];
  List<Incident> incidents = [];
  Plan? plan;
  String? planValidation; // null | 'valide' | 'rejete'
  SimResult? sim;
  List<RobustVariant> robust = [];
  Set<String> teamsDown = {};
  int reportSeq = 100;
  int planSeq = 0; // monotonic persisted: plan identifiers never reassigned
  List<Map<String, dynamic>> planHistory = [];
  String scenarioKind = 'jouet-1';
  int scenarioSeed = 7;
  String groupMethod = 'classique'; // classique | meta
  List<Group> metaGroups = [];
  List<MetaCallRecord> metaCalls = [];
  Map<String, dynamic> extractions = {};
  Map<String, dynamic> visualAnalyses = {}; // mediaId -> {reportId, model, at, analysis}
  bool restoredFromStore = false;
  bool storeRecovered = false;
  int? docAuditSeq;
  late AuditLog audit;
  late MetaConnector meta;
  late JsonStore store;
  MongoStore? mongo;
  bool mongoPrimary = false;
  String? mongoError;
  Future<void> mongoQueue = Future<void>.value();
  late MunicipalAuth municipal;
  final RateLimiter rateLimiter = RateLimiter();
}

/// Audit THEN persistence, EXPECTED before the HTTP response: when the
/// client receives a success, the state is durable in MongoDB (and JSON).
/// Explicit order, always non-atomic between journal and state.
Future<void> auditPersist(AppState s, String event,
    [Map<String, dynamic>? details]) async {
  s.audit.append(event, details);
  persist(s);
  await s.mongoQueue;
  if (s.mongoError != null) {
    // Mongo write failed: flag it in the journal (durable JSON),
    // without claiming the primary database is up to date.
    s.audit.append('mongo.write_error', {'error': s.mongoError});
    try {
      s.store.save(stateDoc(s));
    } catch (_) {}
  }
}

Map<String, dynamic> stateDoc(AppState s) => {
    'format': 1,
    'savedAt': DateTime.now().toUtc().toIso8601String(),
    'auditSeq': s.audit.entries.length,
    'scenarioKind': s.scenarioKind,
    'scenarioSeed': s.scenarioSeed,
    'scenarioId': s.scenario?.id,
    'reports': s.reports.map((r) => r.toJson()).toList(),
    'manual': s.manualReports.toList(),
    'groupParams': s.groupParams,
    'groupMethod': s.groupMethod,
    'groups': s.groups.map((g) => g.toJson()).toList(),
    'incidents': s.incidents.map((i) => i.toJson()).toList(),
    'plan': s.plan?.toJson(),
    'planHistory': s.planHistory,
    'planValidation': s.planValidation,
    'sim': s.sim?.toJson(),
    'robust': s.robust.map((r) => r.toJson()).toList(),
    'teamsDown': s.teamsDown.toList(),
    'reportSeq': s.reportSeq,
    'planSeq': s.planSeq,
    'metaGroups': s.metaGroups.map((g) => g.toJson()).toList(),
    'metaCalls': s.metaCalls.map((c) => c.toJson()).toList(),
    'extractions': s.extractions,
    'visualAnalyses': s.visualAnalyses,
  };

String _uploadsDir(String base) => '$base/data/uploads';

/// Bounded raw body (photo upload). Bytes are never JSON.
Future<List<int>> _rawBody(HttpRequest req, int maxBytes) async {
  if (req.contentLength > maxBytes) {
    throw const MediaValidationError('body too large');
  }
  final bytes = <int>[];
  await for (final chunk in req) {
    bytes.addAll(chunk);
    if (bytes.length > maxBytes) {
      throw const MediaValidationError('body too large');
    }
  }
  return bytes;
}

void persist(AppState s) {
  final doc = stateDoc(s);
  // Local JSON backup kept (fallback + pre-migration trace).
  try {
    s.store.save(doc);
  } catch (_) {}
  // Primary MongoDB database: writes serialized by a queue,
  // collection by collection (no multi-document transactions).
  final mongo = s.mongo;
  if (mongo != null && mongo.connected) {
    final entries = List<Map<String, dynamic>>.from(s.audit.entries);
    s.mongoQueue = s.mongoQueue.then((_) async {
      try {
        await mongo.saveSnapshot(doc, journalEntries: entries);
        s.mongoError = null;
      } catch (e) {
        s.mongoError = '$e';
      }
    });
  }
}

/// MongoDB connection (primary database). Explicit JSON fallback if unreachable.
/// Migration: if Mongo is empty but a JSON state exists, it is
/// imported as-is (identifiers, validations, histories preserved),
/// without deleting the JSON.
Future<void> _initMongo(AppState s) async {
  final mongo = MongoStore(
      uri: Platform.environment['CITYRESOLVE_MONGO_URI'] ??
          'mongodb://127.0.0.1:27017/cityresolve_dev');
  s.mongo = mongo;
  // Remote Atlas (TLS + SRV) often exceeds 5 s on first contact;
  // allow 25 s before switching to the JSON fallback (measured: handshake
  // ~6-10 s on this machine, direct connection OK in ~8 s).
  final ok = await mongo.connect(timeout: const Duration(seconds: 25));
  if (!ok) {
    s.mongoPrimary = false;
    s.mongoError = mongo.error;
    return;
  }
  await mongo.ensureIndexes();
  final mongoDoc = await mongo.loadState();
  if (mongoDoc != null) {
    try {
      _restore(s, mongoDoc.cast<String, dynamic>());
      s.restoredFromStore = true;
      s.docAuditSeq = mongoDoc['auditSeq'] as int?;
    } catch (e) {
      s.mongoError = 'Mongo restore impossible: $e';
    }
  } else {
    // Migration from the JSON state restored by _initState (if any).
    await mongo.saveSnapshot(stateDoc(s),
        journalEntries: List.from(s.audit.entries));
    if (s.restoredFromStore) {
      s.audit.append('mongo.migrated', {
        'from': 'state.json',
        'reports': s.reports.length,
        'plans': s.planHistory.length,
      });
    }
  }
  s.mongoPrimary = true;
}

Scenario scenarioForKind(String kind, int seed) => kind == 'jouet-s5'
    ? toyS5()
    : kind == 'dev'
        ? generateDev(seed: seed)
        : toyFixed1();

List<Team> activeTeams(AppState s) =>
    defaultTeams().where((t) => !s.teamsDown.contains(t.id)).toList();

Map<String, dynamic> metricsFor(AppState s) {
  if (s.truth.isEmpty) {
    return {'available': false, 'reason': 'no ground truth'};
  }
  final truthGroups = s.truth.map((t) => t.reportIds).toList();
  final trueOf = <String, int>{};
  for (var i = 0; i < s.truth.length; i++) {
    for (final id in s.truth[i].reportIds) {
      trueOf[id] = i;
    }
  }
  // Outside truth (e.g. manual ones): excluded from scoring, neither FP nor FN.
  // Split groups: scored on their origins (E1:eclairage -> E1).
  // Assumed limitation: an origin present in two split groups only
  // counts for the last one in predOf; the F1 of a split state is
  // therefore an approximation at origin level, not proof at
  // sub-report level. The primary proof of splitting remains the number
  // of incidents produced (2, not 1), not this F1.
  final scored = originMappedGroups(s.groups);
  final pred = scored
      .map((g) => g.reportIds.where(trueOf.containsKey).toList())
      .toList();
  final prf = pairwiseF1(truthGroups, pred);
  final predOf = <String, int>{};
  for (var i = 0; i < scored.length; i++) {
    for (final id in scored[i].reportIds) {
      if (trueOf.containsKey(id)) predOf[id] = i;
    }
  }
  return {
    'available': true,
    'pairwise': prf.toJson(),
    'bCubedF1': bCubedF1(trueOf, predOf),
    'splitMapped': groupsUseSplitIds(s.groups),
    'note': metricNote(),
  };
}

void regroup(AppState s, {bool keepPlan = false}) {
  final byId = {for (final r in s.reports) r.id: r};
  s.groups = groupReports(s.reports,
      distMaxM: (s.groupParams['distMaxM'] as num).toDouble(),
      deltaTMaxH: (s.groupParams['deltaTMaxH'] as num).toDouble(),
      simMin: (s.groupParams['simMin'] as num).toDouble());
  s.incidents = aggregate(s.groups, byId);
  // Incidents change identity: the old plan must not be
  // silently applied to the new groups (except the /api/inject flow
  // which explicitly judges the review with keepPlan: true).
  if (!keepPlan) {
    s.plan = null;
    s.planValidation = null;
    s.sim = null;
  }
}

AppState _initState(String base, {bool restore = true}) {
  final s = AppState();
  Directory('$base/data').createSync(recursive: true);
  Directory(_uploadsDir(base)).createSync(recursive: true);
  s.audit = AuditLog(path: '$base/data/journal.jsonl');
  s.meta = MetaConnector.fromEnvironment(Platform.environment);
  s.municipal = MunicipalAuth.fromEnvironment(Platform.environment);
  s.store = JsonStore('$base/data');
  final sc = toyFixed1();
  s.scenario = sc;
  s.reports = List<Report>.from(sc.reports);
  s.truth = sc.truth;
  regroup(s);
  if (restore) {
    final load = s.store.load();
    final doc = load.doc;
    if (doc != null) {
      try {
        _restore(s, doc);
        s.restoredFromStore = true;
        s.storeRecovered = load.recoveredFromBackup;
        s.docAuditSeq = doc['auditSeq'] as int?;
      } catch (e) {
        // Unreadable document: restart from the default scenario, flag it.
        s.audit.append('store.restore_failed', {'error': '$e'});
      }
    } else if (load.corrupt) {
      s.audit.append('store.corrupt',
          {'note': 'state.json and .bak unreadable: default state'});
    }
  }
  // No startup journal write here: a failed bind does not pollute it.
  return s;
}

/// --- Server wiring of multi-problem splitting ---
///
/// Golden rule: a group whose identifier contains `:` (sub-report
/// `ORIGIN:FAMILY`) is NEVER aggregated by classic `aggregate()`, which
/// would fail looking up `E1:eclairage` in the reports table.
/// `aggregateForGroups()` routes to `aggregateMixedGroups()` as soon as a
/// split group is present, otherwise to `aggregate()` (unchanged path).
/// Splitting is EXPLICIT, never silent: the server only splits
/// on request (`method: 'split'` or `split: true` on classic/meta),
/// the default classic path is strictly preserved.
bool groupsUseSplitIds(List<Group> groups) =>
    groups.any((g) => g.reportIds.any((id) => id.contains(':')));

List<Incident> aggregateForGroups(
        List<Group> groups, Map<String, Report> byId) =>
    groupsUseSplitIds(groups)
        ? aggregateMixedGroups(groups, byId)
        : aggregate(groups, byId);

/// Origins of a list of identifiers (full or split), without duplicates,
/// order preserved. `originIdOfSubunit` leaves a full identifier unchanged,
/// so this function is the identity on unsplit groups.
List<String> originIdsOfRefs(List<String> ids) {
  final out = <String>[];
  for (final id in ids) {
    final o = originIdOfSubunit(id);
    if (!out.contains(o)) out.add(o);
  }
  return out;
}

List<Group> originMappedGroups(List<Group> groups) => [
      for (final g in groups)
        Group(
          id: g.id,
          reportIds: originIdsOfRefs(g.reportIds),
          confidence: g.confidence,
          singleton: originIdsOfRefs(g.reportIds).length == 1,
          abstained: g.abstained,
          method: g.method,
          uncertain: g.uncertain,
          uncertaintyReasons: g.uncertaintyReasons,
          justification: g.justification,
        ),
    ];

/// Copy of an incident whose split identifiers are brought back to their
/// origins, for matching to ground truth during a simulation.
/// Planning fields (identifier, domain, position, severity,
/// deadline via firstSeen/severity) are kept: only the report
/// references change, so a full incident is unchanged.
Incident originMappedIncident(Incident i) => Incident(
      id: i.id,
      reportIds: originIdsOfRefs(i.reportIds),
      severity: i.severity,
      exposure: i.exposure,
      domain: i.domain,
      x: i.x,
      y: i.y,
      firstSeen: i.firstSeen,
      confidence: i.confidence,
      severityStatus: i.severityStatus,
      severityValues: i.severityValues,
      exposureStatus: i.exposureStatus,
      exposureValues: i.exposureValues,
      domainConflict: i.domainConflict,
    );

/// Global splitting grouping (groupSplitReports): each
/// report is expanded into sub-reports by DEV family, grouped
/// by family, then aggregated by aggregateMixedGroups. The origin stays
/// recoverable from each split incident (part before `:`).
void regroupSplit(AppState s, {bool keepPlan = false}) {
  final byId = {for (final r in s.reports) r.id: r};
  s.groups = groupSplitReports(s.reports,
      distMaxM: (s.groupParams['distMaxM'] as num).toDouble(),
      deltaTMaxH: (s.groupParams['deltaTMaxH'] as num).toDouble());
  s.incidents = aggregateForGroups(s.groups, byId);
  s.groupMethod = 'split';
  if (!keepPlan) {
    s.plan = null;
    s.planValidation = null;
    s.sim = null;
  }
}

/// Real Meta grouping (never simulated): matching by the model,
/// with optional splitting post-filter, then mixed aggregation
/// (never classic aggregate() on split identifiers).
/// Does not touch the plan: the caller handles invalidation
/// (/api/group invalidates; /api/inject keeps it to judge the review).
/// Throws MetaException on failure (real call refused or in error).
Future<({List<Group> groups, int splitGroups})> regroupMeta(AppState s,
    {bool split = false}) async {
  var groups = await proposeMatchingWithMeta(s.meta, s.reports,
      onRecord: (r) => s.metaCalls.add(r));
  var splitGroups = 0;
  if (split) {
    final sp = splitGroupsByFamily(s.reports, groups);
    groups = sp.groups;
    splitGroups = sp.splitGroups;
  }
  s.metaGroups = groups;
  s.groups = groups;
  s.groupMethod = 'meta';
  s.incidents =
      aggregateForGroups(groups, {for (final r in s.reports) r.id: r});
  return (groups: groups, splitGroups: splitGroups);
}

void _restore(AppState s, Map<String, dynamic> doc) {
  final kind = (doc['scenarioKind'] ?? 'jouet-1') as String;
  final seed = (doc['scenarioSeed'] ?? 7) as int;
  final sc = scenarioForKind(kind, seed);
  s.scenarioKind = kind;
  s.scenarioSeed = seed;
  s.scenario = sc;
  s.truth = sc.truth;
  s.reports = ((doc['reports'] as List?) ?? [])
      .map((e) => Report.fromJson(e as Map<String, dynamic>))
      .toList();
  s.manualReports =
      ((doc['manual'] as List?) ?? []).map((e) => '$e').toSet();
  if (doc['groupParams'] is Map) {
    s.groupParams = (doc['groupParams'] as Map).cast<String, dynamic>();
  }
  s.reportSeq = (doc['reportSeq'] ?? 100) as int;
  s.planSeq = (doc['planSeq'] ?? 0) as int;
  s.teamsDown = ((doc['teamsDown'] as List?) ?? []).map((e) => '$e').toSet();
  s.planHistory = ((doc['planHistory'] as List?) ?? [])
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList();
  s.groupMethod = (doc['groupMethod'] ?? 'classique') as String;
  s.metaGroups = ((doc['metaGroups'] as List?) ?? [])
      .map((e) => Group.fromJson(e as Map<String, dynamic>))
      .toList();
  s.metaCalls = ((doc['metaCalls'] as List?) ?? [])
      .map((e) => MetaCallRecord.fromJson(e as Map<String, dynamic>))
      .toList();
  s.extractions =
      ((doc['extractions'] as Map?) ?? {}).cast<String, dynamic>();
  s.visualAnalyses =
      ((doc['visualAnalyses'] as Map?) ?? {}).cast<String, dynamic>();
  // Persisted groups captured BEFORE regroup(): regroup() overwrites s.groups
  // with the classic one, and a split state ('split' method, ORIGIN:FAMILY
  // identifiers) would otherwise be lost on restart. Format 1 does not
  // change: split identifiers already survive in
  // Group.toJson/fromJson, and groupMethod='split' is persisted in
  // stateDoc. An old state without `:` restores exactly the old path.
  final persistedGroups = ((doc['groups'] as List?) ?? [])
      .map((e) => Group.fromJson(e as Map<String, dynamic>))
      .toList();
  final persistedMethod = (doc['groupMethod'] ?? 'classique') as String;
  regroup(s, keepPlan: true);
  if (persistedMethod == 'split' &&
      persistedGroups.any((g) => g.reportIds.any((id) => id.contains(':')))) {
    s.groups = persistedGroups;
    s.groupMethod = 'split';
    s.incidents =
        aggregateForGroups(s.groups, {for (final r in s.reports) r.id: r});
  } else if (s.groupMethod == 'meta' && s.metaGroups.isNotEmpty) {
    s.groups = s.metaGroups;
    s.incidents =
        aggregateForGroups(s.groups, {for (final r in s.reports) r.id: r});
  }
  if (doc['plan'] != null) {
    s.plan = Plan.fromJson(doc['plan'] as Map<String, dynamic>);
  }
  s.planValidation = doc['planValidation'] as String?;
  if (doc['sim'] != null) {
    s.sim = SimResult.fromJson(doc['sim'] as Map<String, dynamic>);
    s.robust = ((doc['robust'] as List?) ?? [])
        .map((e) => RobustVariant.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Self-check without sockets: full in-process chain.
void _check(AppState s) {
  // Team-down probe on toy-1 (known plan using both teams).
  final toyTeams = defaultTeams();
  final toyPlan = optimizeExact(incidents: s.incidents, teams: toyTeams);
  final necToyDown = judgeRevision(
      oldPlan: toyPlan,
      oldIncidents: List<Incident>.from(s.incidents),
      updated: s.incidents,
      teams: [toyTeams[1]]);
  final dev = generateDev(seed: 7);
  s.scenario = dev;
  s.reports = List<Report>.from(dev.reports);
  s.truth = dev.truth;
  regroup(s);
  final prf = pairwiseF1(dev.truth.map((t) => t.reportIds).toList(),
      s.groups.map((g) => g.reportIds).toList());
  final teams = defaultTeams();
  final plan = optimizeExact(incidents: s.incidents, teams: teams);
  final sim =
      simulate(plan: plan, proposed: s.incidents, truth: dev.truth, teams: teams);
  final oldPlan = plan;
  final oldIncidents = List<Incident>.from(s.incidents);
  final d1 = dev.reports.first;
  s.reports.add(Report(
      id: 'CHK1',
      text: d1.text,
      category: d1.category,
      x: d1.x,
      y: d1.y,
      t: d1.t + 30,
      severityHint: d1.severityHint,
      exposureHint: d1.exposureHint));
  regroup(s);
  final necU = judgeRevision(
      oldPlan: oldPlan,
      oldIncidents: oldIncidents,
      updated: s.incidents,
      teams: teams);
  final necN = judgeRevision(
      oldPlan: oldPlan,
      oldIncidents: oldIncidents,
      updated: s.incidents,
      teams: [teams[1]]);
  print(jsonEncode({
    'check': 'ok',
    'scenario': dev.id,
    'groups': s.groups.length,
    'f1': prf.f1,
    'planQ': plan.q,
    'planCost': plan.totalCost,
    'simQ': sim.q,
    'simFeasible': sim.feasible,
    'simViolations': sim.violations,
    'injectDuplicate': necU.code,
    'injectTeamDown': necN.code,
    'toyTeamDown': necToyDown.code,
    'meta': s.meta.state.name,
  }));
}

Future<void> main(List<String> args) async {
  // Port: --port wins, otherwise PORT variable (Render-type hosts),
  // otherwise 8080. Listening happens on 0.0.0.0 to be reachable behind
  // a router; locally, http://127.0.0.1:PORT keeps working.
  var port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--port') port = int.parse(args[i + 1]);
  }
  final base =
      File(Platform.script.toFilePath()).parent.parent.path;
  // Local patch: refuse a second server on the same data/ directory,
  // instead of letting two processes write the same state.
  // The lock is released on clean stop (SIGINT/SIGTERM); after an
  // abrupt stop, the file may survive (documented limitation).
  if (!args.contains('--check')) {
    final lock = tryAcquireServerLock('$base/data');
    if (!lock.acquired) {
      print('Refused: a CityResolve server is already running on this '
          'data/ directory (PID ${lock.holderPid}, started ${lock.holderStartedAt}). '
          'If no server is running, delete data/server.lock then restart.');
      exit(2);
    }
    // SIGTERM does not exist on Windows (the error is asynchronous, so
    // a plain try/catch is not enough): best-effort listening.
    final signals = Platform.isWindows
        ? [ProcessSignal.sigint]
        : [ProcessSignal.sigint, ProcessSignal.sigterm];
    for (final sig in signals) {
      try {
        sig.watch().listen((_) {
          releaseServerLock(lock.path);
          exit(0);
        }, onError: (_) {});
      } catch (_) {}
    }
  }
  final s = _initState(base, restore: !args.contains('--check'));
  if (!args.contains('--check')) {
    await _initMongo(s);
  }
  if (args.contains('--check')) {
    _check(s);
    return;
  }
  HttpServer server;
  try {
    server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  } catch (e) {
    print('Cannot listen on 0.0.0.0:$port: $e');
    print('(port busy or sockets forbidden by the sandbox)');
    return;
  }
  if (s.restoredFromStore) {
    // Journal/state consistency: a gap is possible if stopped between writing
    // the audit and the state (non-atomic, assumed and logged).
    if (s.docAuditSeq != null && s.docAuditSeq != s.audit.entries.length) {
      s.audit.append('store.reconciled', {
        'docAuditSeq': s.docAuditSeq,
        'journalSeq': s.audit.entries.length,
        'recoveredFromBackup': s.storeRecovered,
        'note': 'audit/state gap detected at restart',
      });
    }
    s.audit.append('server.resumed', {
      'scenario': s.scenario!.id,
      'reports': s.reports.length,
      'planId': s.plan?.planId,
      'planVersion': s.plan?.version,
    });
  } else {
    s.audit.append(
        'scenario.loaded', {'id': s.scenario!.id, 'label': s.scenario!.label});
  }
  persist(s);
  await s.mongoQueue;
  print('CityResolve DEV (fictitious data, protocol NOT FROZEN) at '
      'http://localhost:$port');
  await for (final req in server) {
    try {
      await _handle(req, s, base);
    } catch (e) {
      // Invalid client inputs => explicit 400, never a raw 500.
      var code = 500;
      var msg = e.toString();
      if (e is FormatException) {
        code = 400;
        msg = 'Invalid JSON body: ${e.message}';
      } else if (e is TypeError) {
        code = 400;
        msg = 'Incorrect field types in the JSON request.';
      }
      req.response.statusCode = code;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'error': msg}));
      await req.response.close();
    }
  }
}

Future<Map<String, dynamic>> _body(HttpRequest req) async {
  final text = await utf8.decoder.bind(req).join();
  if (text.trim().isEmpty) return {};
  return jsonDecode(text) as Map<String, dynamic>;
}

void _json(HttpRequest req, Object o, [int code = 200]) async {
  req.response.statusCode = code;
  req.response.headers.contentType = ContentType.json;
  req.response.write(jsonEncode(o));
  await req.response.close();
}

// --- Public exposure security (§6) ---
String _clientIp(HttpRequest req) {
  final xff = req.headers.value('x-forwarded-for');
  if (xff != null && xff.trim().isNotEmpty) {
    return xff.split(',').first.trim();
  }
  return req.connectionInfo?.remoteAddress.address ?? 'unknown';
}

String? _sessionCookie(HttpRequest req) {
  for (final c in req.cookies) {
    if (c.name == 'municipal_session') return c.value;
  }
  return null;
}

String? _bearer(HttpRequest req) {
  final h = req.headers.value('authorization');
  if (h != null && h.startsWith('Bearer ')) return h.substring(7).trim();
  return null;
}

/// Effective MongoDB host (no credentials): environment variable
/// if present, otherwise local loopback. Used for display only.
String _mongoHost() {
  final uri = Platform.environment['CITYRESOLVE_MONGO_URI'] ?? '';
  final m = RegExp(r'@([^/?#]+)').firstMatch(uri);
  if (m != null) return '${m.group(1)} (remote, see Atlas dashboard)';
  return '127.0.0.1:27017 (local only)';
}

bool _municipalOk(HttpRequest req, AppState s) => s.municipal.isAuthorized(
    sessionId: _sessionCookie(req), bearerToken: _bearer(req));

void _denyMunicipal(HttpRequest req) {
  _json(req, {
    'error': 'municipal area: authentication required',
    'loginRequired': true,
  }, 401);
}

/// Rate limit per IP. Returns false + answers 429 if exceeded.
Future<bool> _rateLimit(HttpRequest req, AppState s, String bucket,
    {required int max, required Duration window}) async {
  final ok = s.rateLimiter
      .allow('$bucket:${_clientIp(req)}', max: max, window: window);
  if (!ok) {
    req.response.statusCode = 429;
    req.response.headers.contentType = ContentType.json;
    req.response.headers.set('Retry-After', window.inSeconds.toString());
    req.response.write(jsonEncode({
      'error': 'too many requests, retry in ${window.inMinutes} minute(s)',
      'retryAfterSec': window.inSeconds,
    }));
    await req.response.close();
  }
  return ok;
}

Future<void> _handle(HttpRequest req, AppState s, String base) async {
  final p = req.uri.path;
  final m = req.method;
  // --- Static: open public page, protected municipal area ---
  if (m == 'GET' && p == '/') {
    return _static(req, '$base/web/public.html', ContentType.html);
  }
  if (m == 'GET' && p == '/public.js') {
    return _static(req, '$base/web/public.js',
        ContentType('application', 'javascript', charset: 'utf-8'));
  }
  if (m == 'GET' && p == '/public.css') {
    return _static(req, '$base/web/public.css',
        ContentType('text', 'css', charset: 'utf-8'));
  }
  // SINGLE municipal area: the dashboard. The old DEV interface
  // (municipal.html/app.js/styles.css) is removed: /municipal and
  // /index.html redirect to /municipal/dashboard (single path).
  if (m == 'GET' && (p == '/municipal' || p == '/index.html')) {
    req.response.statusCode = 302;
    req.response.headers.set('Location', '/municipal/dashboard');
    await req.response.close();
    return;
  }
  // --- Municipal authentication ---
  if (m == 'GET' && p == '/api/municipal/status') {
    return _json(req, {
      'enforced': s.municipal.enforced,
      'authenticated': _municipalOk(req, s),
    });
  }
  if (m == 'POST' && p == '/api/municipal/login') {
    if (!await _rateLimit(req, s, 'login',
        max: 10, window: const Duration(minutes: 10))) {
      return;
    }
    if (!s.municipal.enforced) {
      return _json(req, {'authenticated': true, 'open': true});
    }
    final b = await _body(req);
    final token = (b['token'] ?? '') as String;
    if (!s.municipal.checkToken(token)) {
      return _json(req, {'error': 'invalid token'}, 401);
    }
    final sid = s.municipal.createSession();
    req.response.cookies.add(Cookie('municipal_session', sid)
      ..httpOnly = true
      ..sameSite = SameSite.lax
      ..path = '/'
      ..maxAge = 12 * 3600);
    return _json(req, {'authenticated': true});
  }
  if (m == 'POST' && p == '/api/municipal/logout') {
    s.municipal.revoke(_sessionCookie(req));
    req.response.cookies.add(Cookie('municipal_session', '')
      ..httpOnly = true
      ..path = '/'
      ..maxAge = 0);
    return _json(req, {'authenticated': false});
  }
  // --- API ---
  if (m == 'GET' && p == '/api/health') {
    return _json(req, {
      'ok': true,
      'version': appVersion,
      'protocol': 'NOT FROZEN (draft)',
      'data': 'fictitious (sandbox)',
      'persistence':
          'persistent state data/state.json (local JSON, tmp+rename+.bak, not atomic with the JSONL journal, gap reconciled at startup)',
      'groupMethod': s.groupMethod,
      'planId': s.plan?.planId,
      'planVersion': s.plan?.version,
    });
  }
  if (m == 'GET' && p == '/api/policy') {
    return _json(req, {
      'qWeights': [qWeightSeverity, qWeightExposure],
      'deadlines': deadlinesMin.map((k, v) => MapEntry('$k', v)),
      'exposureBands': '0/1-9/10-49/50-199/200+, unknown≠0, decision E=4',
      'teams': teamDomains,
      'budget': budgetUnits,
      'grid': '${gridSizeKm}x${gridSizeKm} km, 20 km/h',
      'availability': '08:00-16:00, 14 days',
      'note': 'Provisional experimental policy, NOT business-validated.',
    });
  }
  if (m == 'GET' && p == '/api/meta') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    return _json(req, s.meta.toJson());
  }
  if (m == 'GET' && p == '/api/meta/calls') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    return _json(req, {
      'calls': s.metaCalls.map((c) => c.toJson()).toList(),
      'note': 'Real calls or explicit refusals. No simulated result.',
    });
  }
  if (m == 'GET' && p == '/api/db') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    final mongo = s.mongo;
    return _json(req, {
      'backend': s.mongoPrimary ? 'mongodb (primary) + json (backup)' : 'json (fallback, MongoDB unreachable)',
      'mongoConnected': mongo?.connected ?? false,
      'mongoServerVersion': mongo?.serverVersion,
      'database': 'cityresolve_dev',
      // Host only, NEVER credentials in the response.
      'host': _mongoHost(),
      'uri': 'mongodb://127.0.0.1:27017 (local only)',
      'counts': mongo != null && mongo.connected ? await mongo.counts() : {},
      'lastError': s.mongoError,
      'transactions':
          'no multi-document transactions (no replica set): state document + mirrors collection by collection, journal/state gap reconciled at startup',
    });
  }
  if (m == 'GET' && p == '/api/state') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    return _json(req, {
      'scenario': s.scenario?.id,
      'scenarioKind': s.scenarioKind,
      'reports': s.reports.length,
      'manual': s.manualReports.toList(),
      'incidents': s.incidents.length,
      'groupMethod': s.groupMethod,
      'planId': s.plan?.planId,
      'planVersion': s.plan?.version,
      'planValidation': s.planValidation,
      'simQ': s.sim?.q,
      'auditEntries': s.audit.entries.length,
      'metaState': s.meta.state.name,
    });
  }
  if (m == 'GET' && p == '/api/plans') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    return _json(req, {'plans': s.planHistory});
  }
  if (m == 'POST' && p == '/api/meta/verify') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    final connector = MetaConnector.fromEnvironment(Platform.environment);
    final (verified, record) = await connector.verify();
    s.meta = verified;
    s.metaCalls.add(record);
    await auditPersist(s, 'meta.verify',
        {'state': s.meta.state.name, 'latencyMs': record.latencyMs});
    return _json(req, {'meta': s.meta.toJson(), 'call': record.toJson()});
  }
  if (m == 'POST' && p == '/api/meta/extract') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    final b = await _body(req);
    final rid = (b['reportId'] ?? '') as String;
    Report? rep;
    for (final r in s.reports) {
      if (r.id == rid) rep = r;
    }
    if (rep == null) {
      return _json(req, {'error': 'unknown report: $rid'}, 404);
    }
    try {
      final out = await extractStructuredWithMeta(s.meta, rep,
          onRecord: (r) => s.metaCalls.add(r));
      s.extractions[rid] = out;
      await auditPersist(s, 'meta.extract', {'reportId': rid});
      return _json(req, {'extraction': out, 'reportId': rid});
    } on MetaException catch (e) {
      await auditPersist(s, 'meta.extract.error', {'reportId': rid, 'error': e.message});
      return _json(req, {'error': e.message, 'call': e.record.toJson()}, 502);
    }
  }
  // --- Photos (P1): bytes on disk, never in the state or database ---
  if (m == 'POST' && p == '/api/photos') {
    if (!await _rateLimit(req, s, 'photo-upload',
        max: 10, window: const Duration(minutes: 10))) {
      return;
    }
    final ct = req.headers.contentType?.mimeType ?? '';
    if (!ct.startsWith('image/')) {
      return _json(req, {
        'error':
            'Content-Type image/* required (jpeg/png/gif/webp), received: ${ct.isEmpty ? 'missing' : ct}'
      }, 400);
    }
    List<int> bytes;
    try {
      bytes = await _rawBody(req, maxPhotoBytes + 1024);
    } on MediaValidationError catch (e) {
      return _json(req, {'error': e.message}, 413);
    }
    String ext;
    try {
      ext = validateImageBytes(bytes);
    } on MediaValidationError catch (e) {
      return _json(req, {'error': e.message}, 400);
    }
    final id = newMediaId();
    final dir = _uploadsDir(base);
    await mediaFile(dir, id, ext).writeAsBytes(bytes, flush: true);
    final meta = {
      'mediaId': id,
      'ext': ext,
      'mime': mimeForExt(ext),
      'size': bytes.length,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    await mediaMetaFile(dir, id).writeAsString(jsonEncode(meta));
    await auditPersist(
        s, 'photo.uploaded', {'mediaId': id, 'mime': meta['mime'], 'size': bytes.length});
    return _json(req, meta);
  }
  if (m == 'GET' && p.startsWith('/api/photos/')) {
    if (!await _rateLimit(req, s, 'public-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    final id = p.substring('/api/photos/'.length);
    if (!isMediaId(id)) {
      return _json(req, {'error': 'invalid media identifier'}, 400);
    }
    final dir = _uploadsDir(base);
    for (final ext in ['jpg', 'png', 'gif', 'webp']) {
      final f = File('$dir/$id.$ext');
      if (f.existsSync()) {
        req.response.statusCode = 200;
        req.response.headers.contentType =
            ContentType.parse(mimeForExt(ext));
        req.response.headers
            .set('Cache-Control', 'private, max-age=3600');
        await req.response.addStream(f.openRead());
        await req.response.close();
        return;
      }
    }
    return _json(req, {'error': 'media not found'}, 404);
  }
  if (m == 'POST' && p == '/api/meta/analyze-image') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    final b = await _body(req);
    final rid = (b['reportId'] ?? '') as String;
    var mid = (b['mediaId'] ?? '') as String;
    Report? rep;
    for (final r in s.reports) {
      if (r.id == rid) rep = r;
    }
    if (mid.isEmpty && rep != null && rep.photo != null && isMediaId(rep.photo!)) {
      mid = rep.photo!;
    }
    if (mid.isEmpty || !isMediaId(mid)) {
      return _json(req, {
        'error':
            'mediaId required (or reportId whose photo is an uploaded media)'
      }, 400);
    }
    final dir = _uploadsDir(base);
    final metaFile = mediaMetaFile(dir, mid);
    if (!metaFile.existsSync()) {
      return _json(req, {'error': 'media not found: upload first'}, 404);
    }
    final meta =
        jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
    String? foundExt;
    for (final ext in ['jpg', 'png', 'gif', 'webp']) {
      if (File('$dir/$mid.$ext').existsSync()) foundExt = ext;
    }
    if (foundExt == null) {
      return _json(req, {'error': 'media file missing'}, 404);
    }
    final bytes = await File('$dir/$mid.$foundExt').readAsBytes();
    try {
      // Vision on pixels alone: the declared text is NOT sent (measured
      // Nov 2026: the model projected the declared text — street lamps —
      // into the "visible observations" of a diagram that contained none).
      // Text/image matching happens downstream, not in the eye.
      final out = await analyzeImageWithMeta(s.meta, bytes,
          mime: (meta['mime'] ?? mimeForExt(foundExt)) as String,
          reportId: rep?.id,
          descriptionDeclaree: null,
          onRecord: (r) => s.metaCalls.add(r));
      s.visualAnalyses[mid] = {
        'reportId': rep?.id,
        'model': s.meta.model,
        'at': DateTime.now().toUtc().toIso8601String(),
        'analysis': out,
      };
      await auditPersist(
          s, 'meta.analyze-image', {'mediaId': mid, 'reportId': rep?.id});
      return _json(req, {
        'mediaId': mid,
        'reportId': rep?.id,
        'model': s.meta.model,
        'analysis': out,
      });
    } on MetaException catch (e) {
      await auditPersist(s, 'meta.analyze-image.error',
          {'mediaId': mid, 'reportId': rep?.id, 'error': e.message});
      return _json(req, {'error': e.message, 'call': e.record.toJson()}, 502);
    }
  }
  if (m == 'GET' && p == '/api/scenarios') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    return _json(req, {
      'scenarios': [
        {'kind': 'jouet-1', 'label': 'Fixed toy no. 1 (6 reports, 3 inc.)'},
        {'kind': 'jouet-s5', 'label': 'Toy S5 (escalation)'},
        {'kind': 'dev', 'label': 'Generated DEV (20 reports, 8 inc., seed)'},
      ]
    });
  }
  if (m == 'POST' && p == '/api/scenario/load') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    final b = await _body(req);
    final kind = (b['kind'] ?? 'jouet-1') as String;
    final seed = (b['seed'] ?? 7) as int;
    final sc = scenarioForKind(kind, seed);
    s.scenarioKind = kind;
    s.scenarioSeed = seed;
    s.scenario = sc;
    s.reports = List<Report>.from(sc.reports);
    s.truth = sc.truth;
    s.manualReports = {};
    s.groupParams = {'distMaxM': 250.0, 'deltaTMaxH': 6.0, 'simMin': 0.75};
    s.groups = [];
    s.incidents = [];
    s.plan = null;
    s.planValidation = null;
    s.planHistory = [];
    s.sim = null;
    s.robust = [];
    s.teamsDown = {};
    s.groupMethod = 'classique';
    s.metaGroups = [];
    s.extractions = {};
    s.visualAnalyses = {};
    regroup(s);
    await auditPersist(s, 'scenario.loaded', {'id': sc.id, 'label': sc.label});
    return _json(req, {'scenario': sc.id, 'label': sc.label});
  }
  if (m == 'GET' && p == '/api/reports') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    return _json(req, {
      'reports': s.reports.map((r) => r.toJson()).toList(),
      'manual': s.manualReports.toList(),
      'truthKnown': s.truth.map((t) => t.toJson()).toList(),
    });
  }
  // --- Public API: filtered data only, never the truth ---
  if (m == 'GET' && p == '/api/public/reports') {
    if (!await _rateLimit(req, s, 'public-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    final limit = ((int.tryParse(req.uri.queryParameters['limit'] ?? '') ?? 20)
        .clamp(1, 50));
    final sorted = List<Report>.from(s.reports)
      ..sort((a, b) => (b.receivedAt ?? '').compareTo(a.receivedAt ?? ''));
    return _json(req, {
      'fictive': true,
      'reports': sorted
          .take(limit)
          .map((r) => publicReportJson(r,
              status: trackingStatus(r, s.groups, s.incidents, s.plan)))
          .toList(),
    });
  }
  // Note: '/api/public/reports/recent' (cursor pagination, defined
  // below) is excluded here so it is not read as an identifier.
  if (m == 'GET' &&
      p.startsWith('/api/public/reports/') &&
      p != '/api/public/reports/recent') {
    if (!await _rateLimit(req, s, 'public-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    final rid = p.substring('/api/public/reports/'.length);
    Report? rep;
    for (final r in s.reports) {
      if (r.id == rid) rep = r;
    }
    if (rep == null) {
      return _json(req, {'error': 'report not found'}, 404);
    }
    final status = trackingStatus(rep, s.groups, s.incidents, s.plan);
    Incident? inc;
    for (final g in s.groups) {
      if (!g.reportIds.contains(rep.id)) continue;
      for (final ii in s.incidents) {
        if (ii.reportIds.toSet().intersection(g.reportIds.toSet()).isNotEmpty) {
          inc = ii;
          break;
        }
      }
    }
    return _json(req, {
      'fictive': true,
      'report': publicReportJson(rep, status: status, includeGps: true),
      'incident': inc == null ? null : publicIncidentJson(inc),
    });
  }
  if (m == 'GET' && p == '/api/public/incidents') {
    if (!await _rateLimit(req, s, 'public-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    return _json(req, {
      'fictive': true,
      'grid': '5x5 km fictitious (not a real map)',
      'incidents': s.incidents.map(publicIncidentJson).toList(),
    });
  }
  // Public creation: validated + rate-limited. Does NOT group:
  // a visitor must neither invalidate the municipal plan nor trigger a
  // computation (the municipal interface groups explicitly). The status
  // becomes "grouped" at the next municipal grouping.
  // Shared creation (local function): the canonical public alias
  // POST /api/public/report and the historical path POST /api/reports
  // apply exactly the same validation, limits and persistence.
  Future<void> _createPublicReport(
      HttpRequest req, AppState s, String base) async {
    if (!await _rateLimit(req, s, 'report-create',
        max: 20, window: const Duration(minutes: 10))) {
      return;
    }
    if (s.reports.length >= maxReportsTotal) {
      return _json(req, {
        'error':
            'maximum report capacity reached ($maxReportsTotal)'
      }, 429);
    }
    final b = await _body(req);
    final textErr = publicTextError(b['text'] as String?);
    if (textErr != null) return _json(req, {'error': textErr}, 400);
    final sevH = b['severityHint'] as int?;
    final expH = b['exposureHint'] as int?;
    if (sevH != null && (sevH < 1 || sevH > 5)) {
      return _json(req, {'error': 'severityHint outside 1..5 (or null = unknown)'}, 400);
    }
    if (expH != null && (expH < 0 || expH > 4)) {
      return _json(req, {'error': 'exposureHint outside 0..4 (or null = unknown)'}, 400);
    }
    final category = (b['category'] ?? 'autre') as String;
    if (!isPublicCategory(category)) {
      return _json(req, {'error': 'unknown category: $category'}, 400);
    }
    // Photo: either an uploaded mediaId (verified), or the historical free label.
    String? photoRef = b['photo'] as String?;
    final mediaId = b['photoMediaId'] as String?;
    if (mediaId != null && mediaId.isNotEmpty) {
      if (!isMediaId(mediaId) ||
          !mediaMetaFile(_uploadsDir(base), mediaId).existsSync()) {
        return _json(req, {
          'error': 'invalid photoMediaId or media not found: upload first via POST /api/photos'
        }, 400);
      }
      photoRef = mediaId;
    }
    final gpsLat = (b['gpsLat'] as num?)?.toDouble();
    final gpsLon = (b['gpsLon'] as num?)?.toDouble();
    final gpsAcc = (b['gpsAccuracy'] as num?)?.toDouble();
    final gpsErr = publicGpsError(gpsLat, gpsLon, gpsAcc);
    if (gpsErr != null) return _json(req, {'error': gpsErr}, 400);
    s.reportSeq++;
    final receivedAt = DateTime.now().toUtc().toIso8601String();
    final r = Report(
      id: 'M${s.reportSeq}',
      text: (b['text'] as String).trim(),
      category: category,
      x: ((b['x'] ?? 2.5) as num).toDouble().clamp(0.0, 5.0),
      y: ((b['y'] ?? 2.5) as num).toDouble().clamp(0.0, 5.0),
      t: ((b['t'] ?? 500) as num).toInt().clamp(0, 20160),
      severityHint: sevH,
      exposureHint: expH,
      photo: photoRef,
      source: 'manuel',
      receivedAt: receivedAt,
      gpsLat: gpsLat,
      gpsLon: gpsLon,
      gpsAccuracy: gpsAcc,
    );
    s.reports.add(r);
    s.manualReports.add(r.id);
    await auditPersist(s, 'report.created', {'id': r.id, 'manual': true});
    return _json(req, {
      'id': r.id,
      'receivedAt': receivedAt,
      'status': 'enregistre',
      'statusLabel': trackingLabels['enregistre'],
      'fictive': true,
      'note':
          'Report registered. Demonstration: data can be reset at any time.',
    });
  }

  if (m == 'POST' && p == '/api/reports') {
    return _createPublicReport(req, s, base);
  }
  if (m == 'POST' && p == '/api/public/report') {
    return _createPublicReport(req, s, base);
  }
  if (m == 'GET' && p == '/api/public/reports/recent') {
    if (!await _rateLimit(req, s, 'public-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    final limit = ((int.tryParse(req.uri.queryParameters['limit'] ?? '') ?? 5)
        .clamp(1, 50));
    final page = paginatePublicReports(sortPublicReports(s.reports), limit,
        req.uri.queryParameters['cursor']);
    return _json(req, {
      'fictive': true,
      'reports': page.items
          .map((r) => publicReportJson(r,
              status: trackingStatus(r, s.groups, s.incidents, s.plan)))
          .toList(),
      'nextCursor': page.nextCursor,
    });
  }
  if (m == 'GET' && p == '/api/public/incidents/map') {
    if (!await _rateLimit(req, s, 'public-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    double num(String k, double d) =>
        double.tryParse(req.uri.queryParameters[k] ?? '') ?? d;
    final minx = num('minx', 0.0), miny = num('miny', 0.0);
    final maxx = num('maxx', 5.0), maxy = num('maxy', 5.0);
    final limit = ((int.tryParse(req.uri.queryParameters['limit'] ?? '') ?? 100)
        .clamp(1, 200));
    if (minx > maxx || miny > maxy) {
      return _json(req, {'error': 'invalid bbox'}, 400);
    }
    return _json(req, {
      'fictive': true,
      'grid': '5x5 km fictitious (not a real map)',
      'incidents': filterIncidentsBbox(
              s.incidents, minx, miny, maxx, maxy, limit)
          .map(publicIncidentJson)
          .toList(),
    });
  }
  if (m == 'GET' && p.startsWith('/api/public/report/')) {
    // Canonical tracking by identifier (never a massive list).
    if (!await _rateLimit(req, s, 'public-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    final rid = p.substring('/api/public/report/'.length);
    Report? rep;
    for (final r in s.reports) {
      if (r.id == rid) rep = r;
    }
    if (rep == null) {
      return _json(req, {'error': 'report not found'}, 404);
    }
    final status = trackingStatus(rep, s.groups, s.incidents, s.plan);
    return _json(req, {
      'fictive': true,
      'report': publicReportJson(rep, status: status, includeGps: true),
    });
  }
  if (m == 'GET' && p == '/api/public/stats/summary') {
    if (!await _rateLimit(req, s, 'public-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    return _json(req, publicStatsSummary(s.reports, s.groups, s.incidents));
  }
  if (m == 'POST' && p == '/api/group') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    final b = await _body(req);
    for (final k in ['distMaxM', 'deltaTMaxH', 'simMin']) {
      if (b[k] != null) s.groupParams[k] = (b[k] as num).toDouble();
    }
    final method = (b['method'] ?? 'classique') as String;
    final split = b['split'] == true;
    if (method == 'split') {
      // Global split grouping, explicit: never classic aggregate()
      // on ORIGIN:FAMILY identifiers.
      regroupSplit(s);
      await auditPersist(s, 'group.done', {
        'method': 'split',
        'groups': s.groups.length,
        'incidents': s.incidents.length
      });
      return _json(req, {
        'method': 'split',
        'groups': s.groups.map((g) => g.toJson()).toList(),
        'incidents': s.incidents.map((i) => i.toJson()).toList(),
        'params': s.groupParams,
        'metrics': metricsFor(s),
        'ambiguousPairs': ambiguousPairs(s.reports,
            originMappedGroups(s.groups),
            distMaxM: (s.groupParams['distMaxM'] as num).toDouble(),
            deltaTMaxH: (s.groupParams['deltaTMaxH'] as num).toDouble(),
            simMin: (s.groupParams['simMin'] as num).toDouble()),
      });
    }
    if (method == 'meta') {
      if (s.meta.state != MetaState.verified) {
        return _json(req, {
          'error':
              'META method unavailable (connector ${s.meta.state.name}): no simulated grouping, classic still available.',
          'meta': s.meta.toJson(),
        }, 400);
      }
      try {
        final res = await regroupMeta(s, split: split);
        final splitGroups = res.splitGroups;
        s.plan = null;
        s.planValidation = null;
        s.sim = null;
        await auditPersist(s, 'group.done', {
          'method': 'meta',
          'model': s.meta.model,
          'split': split,
          'splitGroups': splitGroups
        });
        return _json(req, {
          'method': 'meta',
          'model': s.meta.model,
          'groups': s.groups.map((g) => g.toJson()).toList(),
          'incidents': s.incidents.map((i) => i.toJson()).toList(),
          'params': s.groupParams,
          'metrics': metricsFor(s),
          'ambiguousPairs': [],
        });
      } on MetaException catch (e) {
        await auditPersist(s, 'group.meta.error', {'error': e.message});
        return _json(
            req, {'error': e.message, 'call': e.record.toJson()}, 502);
      }
    }
    if (method != 'classique') {
      return _json(req, {'error': 'method = classique|meta|split'}, 400);
    }
    regroup(s);
    var splitGroups = 0;
    if (split) {
      // Splitting post-filter on classic grouping: same rule
      // as for Meta, mixed aggregation, never classic aggregate()
      // on split identifiers.
      final sp = splitGroupsByFamily(s.reports, s.groups);
      s.groups = sp.groups;
      splitGroups = sp.splitGroups;
      s.incidents =
          aggregateForGroups(s.groups, {for (final r in s.reports) r.id: r});
    }
    await auditPersist(s, 'group.done', {
      'params': s.groupParams,
      'method': 'classique',
      'split': split,
      'splitGroups': splitGroups
    });
    return _json(req, {
      'method': 'classique',
      'split': split,
      'splitGroups': splitGroups,
      'groups': s.groups.map((g) => g.toJson()).toList(),
      'incidents': s.incidents.map((i) => i.toJson()).toList(),
      'params': s.groupParams,
      'metrics': metricsFor(s),
      'ambiguousPairs': ambiguousPairs(
          s.reports,
          split ? originMappedGroups(s.groups) : s.groups,
          distMaxM: (s.groupParams['distMaxM'] as num).toDouble(),
          deltaTMaxH: (s.groupParams['deltaTMaxH'] as num).toDouble(),
          simMin: (s.groupParams['simMin'] as num).toDouble()),
    });
  }
  if (m == 'GET' && p == '/api/incidents') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    return _json(req, {
      'incidents': s.incidents.map((i) => i.toJson()).toList(),
    });
  }
  if (m == 'POST' && p == '/api/plan') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    final teams = activeTeams(s);
    if (teams.isEmpty) {
      return _json(req, {
        'error': 'No active team (down: ${s.teamsDown.join(',')}).'
      }, 400);
    }
    try {
      final raw = optimizeExact(incidents: s.incidents, teams: teams);
      s.planSeq++;
      s.plan = raw.withIdentity('PLAN-${s.planSeq}', s.planSeq);
    } catch (e) {
      return _json(req, {'error': e.toString()}, 400);
    }
    s.planValidation = null;
    s.planHistory.add({
      'planId': s.plan!.planId,
      'version': s.plan!.version,
      'at': DateTime.now().toUtc().toIso8601String(),
      'method': s.groupMethod,
      'validation': null,
      'plan': s.plan!.toJson(),
    });
    await auditPersist(s, 'plan.proposed', {
      'planId': s.plan!.planId,
      'version': s.plan!.version,
      'q': s.plan!.q,
      'cost': s.plan!.totalCost,
      'tasks': s.plan!.tasks.length
    });
    return _json(req, s.plan!.toJson());
  }
  if (m == 'POST' && p == '/api/plan/validate') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    if (s.plan == null) {
      return _json(req, {'error': 'no plan to validate'}, 400);
    }
    if (planIsStale(s.plan, s.planHistory, s.audit.entries)) {
      return _json(req, {
        'error':
            'stale plan (later grouping): replan before validating'
      }, 400);
    }
    final b = await _body(req);
    final d = (b['decision'] ?? '') as String;
    if (d != 'valide' && d != 'rejete') {
      return _json(req, {'error': 'decision = valide|rejete'}, 400);
    }
    s.planValidation = d;
    for (final h in s.planHistory) {
      if (h['planId'] == s.plan!.planId) h['validation'] = d;
    }
    await auditPersist(s, 'plan.validated',
        {'decision': d, 'note': b['note'] ?? '', 'by': 'humain', 'planId': s.plan!.planId});
    return _json(req, {'validation': d, 'planId': s.plan!.planId});
  }
  if (m == 'POST' && p == '/api/simulate') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    if (s.plan == null) return _json(req, {'error': 'no plan'}, 400);
    final knownIds = s.incidents.map((i) => i.id).toSet();
    if (s.plan!.tasks.any((t) => !knownIds.contains(t.incidentId))) {
      return _json(req, {
        'error': 'stale plan (incidents regrouped since): restart planning'
      }, 400);
    }
    if (s.truth.isEmpty) {
      return _json(req, {'error': 'ground truth unavailable'}, 400);
    }
    // Truth matching on origins: without this projection, a
    // split incident [E1:eclairage] would never intersect the truth
    // [E1] and would be counted 'outside truth', with the truth missed, even
    // though splitting produced the right task. Planning
    // fields are kept (see originMappedIncident); a
    // full incident is unchanged by the projection.
    final simProposed =
        s.incidents.map(originMappedIncident).toList();
    s.sim = simulate(
        plan: s.plan!,
        proposed: simProposed,
        truth: s.truth,
        teams: defaultTeams());
    s.robust = robustness(
        plan: s.plan!,
        proposed: simProposed,
        truth: s.truth,
        teams: defaultTeams());
    await auditPersist(s, 'simulate.done', {
      'planId': s.plan!.planId,
      'q': s.sim!.q,
      'feasible': s.sim!.feasible,
      'violations': s.sim!.violations
    });
    return _json(req, {
      'result': s.sim!.toJson(),
      'robustness': s.robust.map((r) => r.toJson()).toList(),
      'splitOriginMapped': groupsUseSplitIds(s.groups),
      'note': 'SIMULATED interventions, not real urban interventions.',
    });
  }
  if (m == 'POST' && p == '/api/inject') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    final b = await _body(req);
    final type = (b['type'] ?? 'reports') as String;
    if (s.plan == null) return _json(req, {'error': 'no plan'}, 400);
    final oldPlan = s.plan!;
    final oldIncidents = List<Incident>.from(s.incidents);
    if (type == 'team_down') {
      final tid = (b['teamId'] ?? '') as String;
      s.teamsDown.add(tid);
    } else {
      final reps = (b['reports'] as List? ?? []);
      for (final rj in reps) {
        s.reportSeq++;
        final r = Report(
          id: 'M${s.reportSeq}',
          text: ((rj as Map)['text'] ?? '') as String,
          category: (rj['category'] ?? 'autre') as String,
          x: ((rj['x'] ?? 2.5) as num).toDouble().clamp(0.0, 5.0),
          y: ((rj['y'] ?? 2.5) as num).toDouble().clamp(0.0, 5.0),
          t: ((rj['t'] ?? 1500) as num).toInt(),
          severityHint: rj['severityHint'] as int?,
          exposureHint: rj['exposureHint'] as int?,
          source: 'injection',
        );
        s.reports.add(r);
        s.manualReports.add(r.id);
      }
      // Regroup with the active method: a classic grouping on
      // a split state would change identifiers (ORIGIN:FAMILY ->
      // full) and fabricate false S5 escalations (false N3-S5).
      if (s.groupMethod == 'split') {
        regroupSplit(s, keepPlan: true);
      } else if (s.groupMethod == 'meta') {
        try {
          await regroupMeta(s);
        } on MetaException catch (e) {
          await auditPersist(s, 'inject.meta.error',
              {'error': e.message, 'note': 'reports added but grouping not rerun'});
          return _json(req, {
            'error': e.message,
            'call': e.record.toJson(),
            'note':
                'reports added, META grouping not rerun: rerun an explicit grouping',
          }, 502);
        }
      } else {
        regroup(s, keepPlan: true);
      }
      await auditPersist(s, 'group.done', {
        'method': s.groupMethod,
        'cause': 'inject',
        'groups': s.groups.length,
        'incidents': s.incidents.length,
      });
    }
    final newS5 = s.incidents
        .where((i) => i.severity != null && i.severity! >= 5)
        .map((i) => i.id)
        .toSet();
    final oldS5keys = oldIncidents
        .where((i) => i.severity != null && i.severity! >= 5)
        .map((i) => i.reportIds.join(','))
        .toSet();
    final fresh5 = newS5.where((id) {
      final inc = s.incidents.firstWhere((i) => i.id == id);
      return !oldS5keys.contains(inc.reportIds.join(','));
    }).toSet();
    final teams = defaultTeams()
        .where((t) => !s.teamsDown.contains(t.id))
        .toList();
    final nec = judgeRevision(
        oldPlan: oldPlan,
        oldIncidents: oldIncidents,
        updated: s.incidents,
        teams: teams.isEmpty ? defaultTeams() : teams,
        newS5: fresh5);
    Plan? newPlan;
    Map<String, dynamic>? diff;
    if (nec.necessary && nec.code != 'N3-S5' && teams.isNotEmpty) {
      s.planSeq++;
      newPlan = optimizeExact(incidents: s.incidents, teams: teams)
          .withIdentity('PLAN-${s.planSeq}', s.planSeq);
      s.planHistory.add({
        'planId': newPlan.planId,
        'version': newPlan.version,
        'at': DateTime.now().toUtc().toIso8601String(),
        'method': s.groupMethod,
        'validation': null,
        'plan': newPlan.toJson(),
      });
      final d = comparePlans(oldPlan, newPlan,
          oldReports: {
            for (final i in oldIncidents) i.id: i.reportIds.toSet()
          },
          newReports: {
            for (final i in s.incidents) i.id: i.reportIds.toSet()
          });
      diff = {'material': d.material, 'detail': d.detail};
      s.plan = newPlan;
      s.planValidation = null;
    }
    await auditPersist(s, 'inject.received',
        {'type': type, 'necessity': nec.code, 'revised': newPlan != null});
    return _json(req, {
      'necessity': nec.toJson(),
      'diff': diff,
      'plan': newPlan?.toJson(),
      'incidents': s.incidents.map((i) => i.toJson()).toList(),
      'groups': s.groups.map((g) => g.toJson()).toList(),
    });
  }
  if (m == 'POST' && p == '/api/compare') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    final b = await _body(req);
    final configs = (b['configs'] as List? ?? []).take(5).toList();
    if (configs.isEmpty || s.truth.isEmpty) {
      return _json(req, {'error': 'configs required + ground truth'}, 400);
    }
    final rows = [];
    final byId = {for (final r in s.reports) r.id: r};
    for (final cj in configs) {
      final c = cj as Map<String, dynamic>;
      final g = groupReports(s.reports,
          distMaxM: (c['distMaxM'] as num).toDouble(),
          deltaTMaxH: (c['deltaTMaxH'] as num).toDouble(),
          simMin: (c['simMin'] as num).toDouble());
      final incs = aggregateForGroups(g, byId);
      final knownIds = {for (final t in s.truth) ...t.reportIds};
      final prf = pairwiseF1(
          s.truth.map((t) => t.reportIds).toList(),
          g
              .map((x) =>
                  x.reportIds.where(knownIds.contains).toList())
              .toList());
      Plan? pl;
      SimResult? sm;
      try {
        pl = optimizeExact(incidents: incs, teams: defaultTeams());
        sm = simulate(
            plan: pl, proposed: incs, truth: s.truth, teams: defaultTeams());
      } catch (_) {}
      rows.add({
        'config': c,
        'groups': g.length,
        'f1': prf.f1,
        'planQ': pl?.q,
        'simQ': sm?.q,
        'feasible': sm?.feasible,
      });
    }
    await auditPersist(s, 'compare.done', {'rows': rows.length});
    return _json(req, {'rows': rows, 'meta': s.meta.toJson()});
  }
  if (m == 'GET' && p == '/api/compare-methods') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    // Visible DEV comparison: CLASSIC (reference) vs META (if available).
    final byId = {for (final r in s.reports) r.id: r};
    final classicGroups = groupReports(s.reports,
        distMaxM: (s.groupParams['distMaxM'] as num).toDouble(),
        deltaTMaxH: (s.groupParams['deltaTMaxH'] as num).toDouble(),
        simMin: (s.groupParams['simMin'] as num).toDouble());
    Map<String, dynamic> side(List<Group> gs, String method) {
      // Mixed aggregation: if metaGroups was split (split: true),
      // classic aggregate() would fail on split identifiers.
      // F1 scored on origins, with the same documented limitation as
      // metricsFor (an origin in two split groups only counts for
      // the last one); the proof of splitting remains the number
      // of incidents, not this F1.
      final incs = aggregateForGroups(gs, byId);
      Map<String, dynamic>? metrics;
      if (s.truth.isNotEmpty) {
        final known = {for (final t in s.truth) ...t.reportIds};
        final prf = pairwiseF1(
            s.truth.map((t) => t.reportIds).toList(),
            originMappedGroups(gs)
                .map((g) => g.reportIds.where(known.contains).toList())
                .toList());
        metrics = prf.toJson();
      }
      double? planQ, simQ;
      bool? feasible;
      try {
        final pl = optimizeExact(incidents: incs, teams: defaultTeams());
        planQ = pl.q;
        if (s.truth.isNotEmpty) {
          final sm = simulate(
              plan: pl, proposed: incs, truth: s.truth, teams: defaultTeams());
          simQ = sm.q;
          feasible = sm.feasible;
        }
      } catch (_) {}
      return {
        'method': method,
        'groups': gs.map((g) => g.toJson()).toList(),
        'incidents': incs.map((i) => i.toJson()).toList(),
        'f1': metrics,
        'planQ': planQ,
        'simQ': simQ,
        'feasible': feasible,
      };
    }

    final cSide = side(classicGroups, 'classique');
    Map<String, dynamic>? mSide;
    final disagreements = <Map<String, dynamic>>[];
    if (s.metaGroups.isNotEmpty) {
      mSide = side(s.metaGroups, 'meta');
      // Disagreements at origin level: a split group [E1:eclairage]
      // and a full group [E1] designate the same report E1. Without
      // this projection, each split pair would be counted as an
      // artificial disagreement. Limitation: an origin in two split
      // groups only keeps the last one in these maps.
      final cg = <String, String>{};
      for (final g in originMappedGroups(classicGroups)) {
        for (final id in g.reportIds) {
          cg[id] = g.id;
        }
      }
      final mg = <String, String>{};
      for (final g in originMappedGroups(s.metaGroups)) {
        for (final id in g.reportIds) {
          mg[id] = g.id;
        }
      }
      final ids = s.reports.map((r) => r.id).toList()..sort();
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final togetherC = cg[ids[i]] != null && cg[ids[i]] == cg[ids[j]];
          final togetherM = mg[ids[i]] != null && mg[ids[i]] == mg[ids[j]];
          if (togetherC != togetherM) {
            disagreements.add({
              'a': ids[i],
              'b': ids[j],
              'classique': togetherC ? 'merged' : 'separated',
              'meta': togetherM ? 'merged' : 'separated',
            });
          }
        }
      }
    }
    final metaErrors =
        s.metaCalls.where((c) => c.status != 'ok').length;
    final metaLatency =
        s.metaCalls.fold<int>(0, (a, c) => a + c.latencyMs);
    return _json(req, {
      'devOnly': true,
      'classique': cSide,
      'meta': mSide,
      'metaAvailable': mSide != null,
      'metaState': s.meta.state.name,
      'disagreements': disagreements,
      'metaCalls': {
        'count': s.metaCalls.length,
        'errors': metaErrors,
        'totalLatencyMs': metaLatency,
        'calls': s.metaCalls.map((c) => c.toJson()).toList(),
      },
      'truthNote': s.truth.isEmpty
          ? 'No ground truth: F1 not computed (explicit).'
          : 'F1 computed only on reports with a DEV ground truth; manual reports excluded, absence flagged.',
      'note':
          'Exploratory DEV only. A better F1 is not presented as a better allocation: Q scores shown separately, no superiority claimed.',
    });
  }
  if (m == 'GET' && p == '/api/journal') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    // Optional bounded limit (default: all — the interface uses the
    // /api/municipal/dashboard/activity cursor for large volumes).
    final lim = int.tryParse(req.uri.queryParameters['limit'] ?? '');
    final entries = s.audit.toJson();
    if (lim != null) {
      final n = lim.clamp(1, 500);
      return _json(req, {
        'entries': entries.length <= n
            ? entries
            : entries.sublist(entries.length - n),
        'truncated': entries.length > n,
      });
    }
    return _json(req, {'entries': entries});
  }
  // --- Municipal dashboard: dedicated aggregate endpoints ---
  // All protected (municipal area), limited and paginated. Computed on
  // the bounded working state; see docs/PERSISTANCE_EVOLUTION.md for
  // the path towards indexed MongoDB reads at large volume.
  if (m == 'GET' && p == '/municipal/dashboard') {
    return _static(req, '$base/web/dashboard.html', ContentType.html);
  }
  if (m == 'GET' && (p == '/dashboard.js' || p == '/dashboard.css')) {
    return _static(
        req,
        '$base/web${p == '/dashboard.js' ? '/dashboard.js' : '/dashboard.css'}',
        p == '/dashboard.js'
            ? ContentType('application', 'javascript', charset: 'utf-8')
            : ContentType('text', 'css', charset: 'utf-8'));
  }
  // Dedicated municipal pages (same protected area, same design system).
  // The HTML is public by construction (no data inside); all
  // data and actions remain protected on the API side, without exception.
  const municipalPages = {
    '/municipal/decoupage': 'decoupage.html',
    '/municipal/planification': 'planification.html',
    '/municipal/revision': 'revision.html',
  };
  if (m == 'GET' && municipalPages.containsKey(p)) {
    return _static(
        req, '$base/web/${municipalPages[p]}', ContentType.html);
  }
  if (m == 'GET' && p.startsWith('/municipal/signalements/')) {
    return _static(req, '$base/web/fiche-signalement.html', ContentType.html);
  }
  const municipalScripts = {
    '/decoupage.js': 'decoupage.js',
    '/planification.js': 'planification.js',
    '/revision.js': 'revision.js',
    '/fiche-signalement.js': 'fiche-signalement.js',
  };
  if (m == 'GET' && municipalScripts.containsKey(p)) {
    return _static(
        req,
        '$base/web/${municipalScripts[p]}',
        ContentType('application', 'javascript', charset: 'utf-8'));
  }
  if (m == 'GET' && p == '/api/municipal/dashboard/summary') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    if (!await _rateLimit(req, s, 'dash-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    Period period;
    try {
      period = parsePeriod(req.uri.queryParameters['period'],
          req.uri.queryParameters['from'], req.uri.queryParameters['to']);
    } on FormatException catch (e) {
      return _json(req, {'error': e.message}, 400);
    }
    final now = DateTime.now().toUtc();
    final b = periodBounds(period, now);
    final rep = reportsKpi(s.reports, b.start, b.end, b.prevStart, b.prevEnd);
    final teams = defaultTeams();
    final down = s.teamsDown.intersection(teams.map((t) => t.id).toSet());
    final committed = s.plan?.totalCost ?? 0.0;
    return _json(req, {
      'fictive': true,
      'period': period.kind,
      'reports': rep,
      'reportsNote': period.kind == 'all'
          ? 'all reports in the current state'
          : 'timestamped received reports only (DEV scenarios without a date excluded)',
      'incidents': {
        'count': s.incidents.length,
        'note':
            'current reconstruction (one incident = one group; a multi-problem report can contribute to several incidents)',
      },
      'teams': {
        'available': teams.length - down.length,
        'total': teams.length,
        'down': down.toList(),
        'fictive': true,
        'note': 'simulated sandbox teams',
      },
      'budget': {
        'total': budgetUnits,
        'committed': committed,
        'remaining': budgetUnits - committed,
        'pctUsed': budgetUnits == 0 ? 0.0 : 100.0 * committed / budgetUnits,
        'unit': 'fictitious units (neither FCFA, euros, nor dollars)',
        'source': s.plan == null ? 'no plan' : 'plan ${s.plan!.planId}',
      },
      'generatedAt': now.toIso8601String(),
    });
  }
  if (m == 'GET' && p == '/api/municipal/dashboard/latest-report') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    if (!await _rateLimit(req, s, 'dash-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    Report? latest;
    for (final r in s.reports) {
      if (r.receivedAt == null) continue;
      if (latest == null || r.receivedAt!.compareTo(latest.receivedAt!) > 0) {
        latest = r;
      }
    }
    latest ??= s.reports.isEmpty ? null : s.reports.last;
    if (latest == null) return _json(req, {'fictive': true, 'report': null});
    return _json(req, {
      'fictive': true,
      'report': {
        ...publicReportJson(latest,
            status: trackingStatus(latest, s.groups, s.incidents, s.plan)),
        'families': reportProblemFamilies(latest).toList(),
      },
    });
  }
  if (m == 'GET' && p == '/api/municipal/dashboard/incident-status') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    if (!await _rateLimit(req, s, 'dash-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    return _json(req, {
      'fictive': true,
      ...incidentStatusBuckets(s.incidents, s.plan),
      'note':
          'exclusive statuses derived from the real state (definitions: see lib/dashboard.dart)',
    });
  }
  if (m == 'GET' && p == '/api/municipal/dashboard/map') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    if (!await _rateLimit(req, s, 'dash-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    double num(String k, double d) =>
        double.tryParse(req.uri.queryParameters[k] ?? '') ?? d;
    final minx = num('minx', 0.0), miny = num('miny', 0.0);
    final maxx = num('maxx', 5.0), maxy = num('maxy', 5.0);
    final limit = ((int.tryParse(req.uri.queryParameters['limit'] ?? '') ?? 200)
        .clamp(1, 500));
    if (minx > maxx || miny > maxy) {
      return _json(req, {'error': 'invalid bbox'}, 400);
    }
    return _json(req, {
      'fictive': true,
      'grid': '5x5 km fictitious projected (not GPS readings)',
      'incidents': filterIncidentsBbox(s.incidents, minx, miny, maxx, maxy, limit)
          .map(publicIncidentJson)
          .toList(),
    });
  }
  if (m == 'GET' && p == '/api/municipal/dashboard/activity') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    if (!await _rateLimit(req, s, 'dash-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    final limit = ((int.tryParse(req.uri.queryParameters['limit'] ?? '') ?? 10)
        .clamp(1, 50));
    final cursor = int.tryParse(req.uri.queryParameters['cursor'] ?? '');
    final desc = List<Map<String, dynamic>>.from(s.audit.entries.reversed);
    final items = <Map<String, dynamic>>[];
    for (final e in desc) {
      final seq = (e['seq'] as num?)?.toInt() ?? 0;
      if (cursor != null && seq >= cursor) continue;
      items.add(activityItem(e));
      if (items.length >= limit) break;
    }
    return _json(req, {
      'fictive': true,
      'items': items,
      'nextCursor': items.length < limit
          ? null
          : (items.last['seq'] as num?)?.toInt(),
    });
  }
  if (m == 'GET' && p == '/api/municipal/dashboard/priority-plan') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    if (!await _rateLimit(req, s, 'dash-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    if (s.plan == null) {
      return _json(req, {
        'fictive': true,
        'plan': null,
        'stalePlan': false,
        'staleNote': null,
        'note': 'no plan generated (run Optimize plan)',
      });
    }
    final limit = ((int.tryParse(req.uri.queryParameters['limit'] ?? '') ?? 50)
        .clamp(1, 100)
        .toInt());
    final cursor = int.tryParse(req.uri.queryParameters['cursor'] ?? '');
    final byId = {for (final r in s.reports) r.id: r};
    final incById = {for (final i in s.incidents) i.id: i};
    final tasks = s.plan!.tasks.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final rows = <Map<String, dynamic>>[];
    for (var idx = 0; idx < tasks.length; idx++) {
      if (cursor != null && idx <= cursor) continue;
      final t = tasks[idx];
      final inc = incById[t.incidentId];
      if (inc == null) continue;
      rows.add({
        'rank': idx + 1,
        ...planRow(t, inc, byId, s.planValidation),
        'cursor': idx,
      });
      if (rows.length >= limit) break;
    }
    final lastCursor =
        rows.isEmpty ? null : rows.last['cursor'] as int?;
    final hasMore = lastCursor != null && lastCursor < tasks.length - 1;
    final stale = planIsStale(s.plan, s.planHistory, s.audit.entries);
    if (stale) {
      s.audit.append('plan.stale', {'planId': s.plan!.planId});
      persist(s);
      await s.mongoQueue;
    }
    return _json(req, {
      'fictive': true,
      'stalePlan': stale,
      'staleNote': stale
          ? 'grouping after the plan: incident identifiers possibly renumbered, replan before any validation'
          : null,
      'plan': {
        'planId': s.plan!.planId,
        'version': s.plan!.version,
        'q': s.plan!.q,
        'totalCost': s.plan!.totalCost,
        'feasible': s.plan!.feasible,
        'violations': s.plan!.violations,
        'validation': s.planValidation,
        'escalations': s.plan!.escalations,
      },
      'rows': rows,
      'nextCursor': hasMore ? lastCursor : null,
      'unassigned': [
        for (final e in s.plan!.unassigned.entries)
          {'incidentId': e.key, 'motif': e.value},
      ],
      'note':
          'computed proposal (exact optimizer, bounded scope), not a completed intervention; S5 never dispatched (see escalations)',
    });
  }
  if (m == 'GET' && p == '/api/municipal/split/overview') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    if (!await _rateLimit(req, s, 'dash-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    return _json(req, {
      'fictive': true,
      ...splitOverviewData(s.reports, s.groups, s.incidents, s.groupMethod,
          plan: s.plan),
      'groupParams': s.groupParams,
    });
  }
  if (m == 'GET' && p == '/api/municipal/split/report') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    if (!await _rateLimit(req, s, 'dash-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    final rid = (req.uri.queryParameters['reportId'] ?? '').trim();
    if (rid.isEmpty) {
      return _json(req, {'error': 'reportId required'}, 400);
    }
    final det = splitReportDetail(s.reports, s.groups, s.incidents, rid);
    if (det == null) {
      return _json(req, {'error': 'report not found'}, 404);
    }
    return _json(req, {'fictive': true, ...det});
  }
  if (m == 'GET' && p == '/api/municipal/plan/overview') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    if (!await _rateLimit(req, s, 'dash-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    final stale = planIsStale(s.plan, s.planHistory, s.audit.entries);
    return _json(req, {
      'fictive': true,
      'stalePlan': stale,
      'staleNote': stale
          ? 'grouping after the plan: incident identifiers possibly renumbered, replan before any validation'
          : null,
      ...planOverviewData(
        reports: s.reports,
        incidents: s.incidents,
        plan: s.plan,
        planValidation: s.planValidation,
        allTeams: defaultTeams(),
        teamsDown: s.teamsDown,
        simQ: s.sim?.q,
        simFeasible: s.sim?.feasible
      ),
      'simDetail': s.sim == null
          ? null
          : {
              'q': s.sim!.q,
              'feasible': s.sim!.feasible,
              'violations': s.sim!.violations,
              'totalCost': s.sim!.totalCost
            }
    });
  }
  if (m == 'GET' && p == '/api/municipal/revision/history') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    if (!await _rateLimit(req, s, 'dash-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    final limit = ((int.tryParse(req.uri.queryParameters['limit'] ?? '') ?? 20)
        .clamp(1, 50));
    return _json(req, {
      'fictive': true,
      ...revisionHistoryData(s.planHistory, s.audit.entries, limit)
    });
  }
  if (m == 'GET' && p.startsWith('/api/municipal/report/')) {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    if (!await _rateLimit(req, s, 'dash-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    final rid = p.substring('/api/municipal/report/'.length).trim();
    Report? rep;
    for (final r in s.reports) {
      if (r.id == rid) rep = r;
    }
    if (rep == null) {
      return _json(req, {'error': 'report not found'}, 404);
    }
    Map<String, dynamic>? photoMeta;
    if (rep.photo != null && isMediaId(rep.photo!)) {
      final mf = mediaMetaFile(_uploadsDir(base), rep.photo!);
      if (mf.existsSync()) {
        try {
          photoMeta = jsonDecode(await mf.readAsString())
              as Map<String, dynamic>;
        } catch (_) {
          photoMeta = null;
        }
      }
    }
    final mid = (rep.photo != null && isMediaId(rep.photo!)) ? rep.photo : null;
    return _json(req, {
      'fictive': true,
      ...ficheData(
        report: rep,
        groups: s.groups,
        incidents: s.incidents,
        photoMeta: photoMeta,
        visualAnalysis: mid == null
            ? null
            : (s.visualAnalyses[mid] as Map<String, dynamic>?),
        extraction: s.extractions[rep.id] as Map<String, dynamic>?,
        auditEntries: s.audit.entries
      )
    });
  }
  if (m == 'PATCH' && p.startsWith('/api/municipal/report/')) {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    if (!await _rateLimit(req, s, 'report-create',
        max: 20, window: const Duration(minutes: 10))) {
      return;
    }
    final rid = p.substring('/api/municipal/report/'.length).trim();
    final idx = s.reports.indexWhere((r) => r.id == rid);
    if (idx < 0) {
      return _json(req, {'error': 'report not found'}, 404);
    }
    final b = await _body(req);
    final err = validateReportPatch(b);
    if (err != null) return _json(req, {'error': err}, 400);
    final old = s.reports[idx];
    final changed = <String, dynamic>{};
    var updated = old;
    Report copyWith({
      String? text,
      String? category,
      int? Function()? severityHint,
      int? Function()? exposureHint,
      String? Function()? verificationNote,
      String? Function()? verifiedAt
    }) =>
        Report(
          id: updated.id,
          text: text ?? updated.text,
          category: category ?? updated.category,
          x: updated.x,
          y: updated.y,
          t: updated.t,
          severityHint:
              severityHint == null ? updated.severityHint : severityHint(),
          exposureHint:
              exposureHint == null ? updated.exposureHint : exposureHint(),
          photo: updated.photo,
          source: updated.source,
          receivedAt: updated.receivedAt,
          gpsLat: updated.gpsLat,
          gpsLon: updated.gpsLon,
          gpsAccuracy: updated.gpsAccuracy,
          verificationNote: verificationNote == null
              ? updated.verificationNote
              : verificationNote(),
          verifiedAt: verifiedAt == null ? updated.verifiedAt : verifiedAt()
        );
    if (b.containsKey('text')) {
      final v = (b['text'] as String).trim();
      if (v != old.text) {
        changed['text'] = {'from': old.text, 'to': v};
        updated = copyWith(text: v);
      }
    }
    if (b.containsKey('category')) {
      final v = (b['category'] ?? 'autre') as String;
      if (v != old.category) {
        changed['category'] = {'from': old.category, 'to': v};
        updated = copyWith(category: v);
      }
    }
    if (b.containsKey('severityHint')) {
      final v = b['severityHint'] as int?;
      if (v != old.severityHint) {
        changed['severityHint'] = {'from': old.severityHint, 'to': v};
        updated = copyWith(severityHint: () => v);
      }
    }
    if (b.containsKey('exposureHint')) {
      final v = b['exposureHint'] as int?;
      if (v != old.exposureHint) {
        changed['exposureHint'] = {'from': old.exposureHint, 'to': v};
        updated = copyWith(exposureHint: () => v);
      }
    }
    if (b.containsKey('verificationNote')) {
      final raw = b['verificationNote'];
      final v = raw == null ? null : (raw as String);
      if (v != old.verificationNote) {
        changed['verificationNote'] = {'from': old.verificationNote, 'to': v};
        updated = copyWith(
            verificationNote: () => v,
            verifiedAt: () => v == null
                ? null
                : DateTime.now().toUtc().toIso8601String());
      }
    }
    if (changed.isEmpty) {
      return _json(req, {'id': rid, 'changed': false, 'report': updated.toJson()});
    }
    s.reports[idx] = updated;
    s.manualReports.add(rid);
    await auditPersist(s, 'report.updated',
        {'id': rid, 'changed': changed.keys.toList(), 'fields': changed});
    return _json(req, {
      'id': rid,
      'changed': true,
      'report': updated.toJson(),
      'staleGrouping': true,
      'note':
          'Grouping not rerun: rerun a municipal grouping to propagate.'
    });
  }
  if (m == 'GET' && p == '/api/municipal/dashboard/search') {
    if (!_municipalOk(req, s)) return _denyMunicipal(req);
    if (!await _rateLimit(req, s, 'dash-read',
        max: 600, window: const Duration(minutes: 10))) {
      return;
    }
    final q = (req.uri.queryParameters['q'] ?? '').trim();
    if (q.isEmpty) return _json(req, {'fictive': true, 'results': []});
    final limit = ((int.tryParse(req.uri.queryParameters['limit'] ?? '') ?? 20)
        .clamp(1, 50));
    final cursor = int.tryParse(req.uri.queryParameters['cursor'] ?? '');
    final all = searchAll(q, s.reports, s.groups, s.incidents, s.plan);
    final start = (cursor ?? -1) + 1;
    final page = all.skip(start).take(limit).toList();
    return _json(req, {
      'fictive': true,
      'results': page,
      'nextCursor':
          start + page.length < all.length ? start + page.length - 1 : null,
      'note':
          'bounded full-state search; at large volume: MongoDB text index (see docs/PERSISTANCE_EVOLUTION.md)',
    });
  }
  req.response.statusCode = 404;
  req.response.headers.contentType = ContentType.json;
  req.response.write(jsonEncode({'error': 'unknown route'}));
  await req.response.close();
}

Future<void> _static(HttpRequest req, String path, ContentType ct) async {
  final f = File(path);
  if (!await f.exists()) {
    req.response.statusCode = 404;
    req.response.write('not found');
    await req.response.close();
    return;
  }
  req.response.headers.contentType = ct;
  await req.response.addStream(f.openRead());
  await req.response.close();
}
