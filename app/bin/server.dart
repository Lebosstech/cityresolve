// Serveur CityResolve (bac à sable) : API JSON + interface statique.
// Données fictives uniquement. Protocole NON GELÉ. Port : --port (défaut 8080).
import 'dart:convert';
import 'dart:io';

import '../lib/audit.dart';
import '../lib/grouping.dart';
import '../lib/incidents.dart';
import '../lib/meta_connector.dart';
import '../lib/metrics.dart';
import '../lib/optimizer.dart';
import '../lib/oracle.dart';
import '../lib/policy.dart';
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
  Set<String> manualReports = {}; // hors vérité terrain
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
  int planSeq = 0; // monotone persisté : identifiants de plan jamais réattribués
  List<Map<String, dynamic>> planHistory = [];
  String scenarioKind = 'jouet-1';
  int scenarioSeed = 7;
  String groupMethod = 'classique'; // classique | meta
  List<Group> metaGroups = [];
  List<MetaCallRecord> metaCalls = [];
  Map<String, dynamic> extractions = {};
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
}

/// Audit PUIS persistance, ATTENDUE avant la réponse HTTP : quand le
/// client reçoit un succès, l'état est durable dans MongoDB (et le JSON).
/// Ordre explicite, toujours non atomique entre journal et état.
Future<void> auditPersist(AppState s, String event,
    [Map<String, dynamic>? details]) async {
  s.audit.append(event, details);
  persist(s);
  await s.mongoQueue;
  if (s.mongoError != null) {
    // Écriture Mongo échouée : le signaler dans le journal (JSON durable),
    // sans prétendre que la base principale est à jour.
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
  };

void persist(AppState s) {
  final doc = stateDoc(s);
  // Sauvegarde JSON locale conservée (secours + trace pré-migration).
  try {
    s.store.save(doc);
  } catch (_) {}
  // Base principale MongoDB : écritures sérialisées par une file,
  // collection par collection (aucune transaction multi-documents).
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

/// Connexion MongoDB (base principale). Repli JSON explicite si injoignable.
/// Migration : si Mongo est vide mais qu'un état JSON existe, il est
/// importé tel quel (identifiants, validations, historiques préservés),
/// sans supprimer le JSON.
Future<void> _initMongo(AppState s) async {
  final mongo = MongoStore(
      uri: Platform.environment['CITYRESOLVE_MONGO_URI'] ??
          'mongodb://127.0.0.1:27017/cityresolve_dev');
  s.mongo = mongo;
  final ok = await mongo.connect();
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
      s.mongoError = 'restauration Mongo impossible: $e';
    }
  } else {
    // Migration depuis l'état JSON restauré par _initState (le cas échéant).
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
    return {'available': false, 'reason': 'hors vérité terrain'};
  }
  final truthGroups = s.truth.map((t) => t.reportIds).toList();
  final trueOf = <String, int>{};
  for (var i = 0; i < s.truth.length; i++) {
    for (final id in s.truth[i].reportIds) {
      trueOf[id] = i;
    }
  }
  // Hors vérité (ex. manuels) : exclus du scoring, ni FP ni FN.
  // Groupes découpés : scorés sur leurs origines (E1:eclairage -> E1).
  // Limite assumée : une origine présente dans deux groupes découpés ne
  // compte que pour le dernier dans predOf ; le F1 d'un état découpé est
  // donc une approximation au niveau origine, pas une preuve au niveau
  // sous-signalement. La preuve première du découpage reste le nombre
  // d'incidents produits (2, pas 1), pas ce F1.
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
  // Les incidents changent d'identité : l'ancien plan ne doit pas être
  // appliqué silencieusement aux nouveaux groupes (sauf flux /api/inject
  // qui juge explicitement la révision avec keepPlan: true).
  if (!keepPlan) {
    s.plan = null;
    s.planValidation = null;
    s.sim = null;
  }
}

AppState _initState(String base, {bool restore = true}) {
  final s = AppState();
  Directory('$base/data').createSync(recursive: true);
  s.audit = AuditLog(path: '$base/data/journal.jsonl');
  s.meta = MetaConnector.fromEnvironment(Platform.environment);
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
        // Document illisible : repartir du scénario par défaut, le signaler.
        s.audit.append('store.restore_failed', {'error': '$e'});
      }
    } else if (load.corrupt) {
      s.audit.append('store.corrupt',
          {'note': 'state.json et .bak illisibles : état par défaut'});
    }
  }
  // Pas d'écriture journal de démarrage ici : un bind échoué ne pollue pas.
  return s;
}

/// --- Branchement serveur du découpage multi-problème ---
///
/// Règle d'or : un groupe dont un identifiant contient `:` (sous-signalement
/// `ORIGINE:FAMILLE`) n'est JAMAIS agrégé par `aggregate()` classique, qui
/// échouerait en cherchant `E1:eclairage` dans la table des signalements.
/// `aggregateForGroups()` route vers `aggregateMixedGroups()` dès qu'un
/// groupe découpé est présent, sinon vers `aggregate()` (chemin inchangé).
/// Le découpage est EXPLICITE, jamais silencieux : le serveur ne découpe
/// que sur demande (`method: 'split'` ou `split: true` sur classique/meta),
/// le chemin classique par défaut est strictement conservé.
bool groupsUseSplitIds(List<Group> groups) =>
    groups.any((g) => g.reportIds.any((id) => id.contains(':')));

List<Incident> aggregateForGroups(
        List<Group> groups, Map<String, Report> byId) =>
    groupsUseSplitIds(groups)
        ? aggregateMixedGroups(groups, byId)
        : aggregate(groups, byId);

/// Origines d'une liste d'identifiants (pleins ou découpés), sans doublon,
/// ordre préservé. `originIdOfSubunit` laisse un identifiant plein inchangé,
/// donc cette fonction est l'identité sur des groupes non découpés.
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

/// Copie d'un incident dont les identifiants découpés sont ramenés à leurs
/// origines, pour l'appariement à la vérité terrain lors d'une simulation.
/// Les champs de planification (identifiant, domaine, position, gravité,
/// échéance via firstSeen/severity) sont conservés : seules les références
/// de signalements changent, donc un incident plein est inchangé.
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

/// Regroupement par découpage global (groupSplitReports) : chaque
/// signalement est expansé en sous-signalements par famille DEV, groupés
/// par famille, puis agrégés par aggregateMixedGroups. L'origine reste
/// récupérable depuis chaque incident découpé (partie avant `:`).
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
  // Groupes persistés capturés AVANT regroup() : regroup() écrase s.groups
  // par le classique, et un état découpé (méthode 'split', identifiants
  // ORIGINE:FAMILLE) serait sinon perdu au redémarrage. Le format 1 ne
  // change pas : les identifiants découpés survivent déjà dans
  // Group.toJson/fromJson, et groupMethod='split' est persisté dans
  // stateDoc. Un ancien état sans `:` restaure exactement l'ancien chemin.
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

/// Autocontrôle sans sockets : chaîne complète en processus.
void _check(AppState s) {
  // Sonde panne d'équipe sur jouet-1 (plan connu utilisant les 2 équipes).
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
  var port = 8080;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--port') port = int.parse(args[i + 1]);
  }
  final base =
      File(Platform.script.toFilePath()).parent.parent.path;
  // Patch local : refuser un second serveur sur le même répertoire data/,
  // au lieu de laisser deux processus écrire le même état.
  if (!args.contains('--check')) {
    final lock = tryAcquireServerLock('$base/data');
    if (!lock.acquired) {
      print('Refus : un serveur CityResolve tourne déjà sur ce répertoire '
          'data/ (PID ${lock.holderPid}, démarré ${lock.holderStartedAt}). '
          'Si aucun serveur ne tourne, supprimer data/server.lock puis relancer.');
      exit(2);
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
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  } catch (e) {
    print('Impossible d\u2019écouter sur 127.0.0.1:$port : $e');
    print('(port occupé ou sockets interdits par le bac à sable)');
    return;
  }
  if (s.restoredFromStore) {
    // Cohérence journal/état : écart possible si arrêt entre l'écriture
    // de l'audit et celle de l'état (non atomique, assumé et journalisé).
    if (s.docAuditSeq != null && s.docAuditSeq != s.audit.entries.length) {
      s.audit.append('store.reconciled', {
        'docAuditSeq': s.docAuditSeq,
        'journalSeq': s.audit.entries.length,
        'recoveredFromBackup': s.storeRecovered,
        'note': 'écart audit/état détecté au redémarrage',
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
  print('CityResolve DEV (données fictives, protocole NON GELÉ) sur '
      'http://localhost:$port');
  await for (final req in server) {
    try {
      await _handle(req, s, base);
    } catch (e) {
      // Entrées client invalides => 400 explicite, jamais 500 brut.
      var code = 500;
      var msg = e.toString();
      if (e is FormatException) {
        code = 400;
        msg = 'Corps JSON invalide : ${e.message}';
      } else if (e is TypeError) {
        code = 400;
        msg = 'Types de champs incorrects dans la requête JSON.';
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

Future<void> _handle(HttpRequest req, AppState s, String base) async {
  final p = req.uri.path;
  final m = req.method;
  // --- Statique ---
  if (m == 'GET' && (p == '/' || p == '/index.html')) {
    return _static(req, '$base/web/index.html', ContentType.html);
  }
  if (m == 'GET' && p == '/app.js') {
    return _static(req, '$base/web/app.js',
        ContentType('application', 'javascript', charset: 'utf-8'));
  }
  if (m == 'GET' && p == '/styles.css') {
    return _static(req, '$base/web/styles.css',
        ContentType('text', 'css', charset: 'utf-8'));
  }
  // --- API ---
  if (m == 'GET' && p == '/api/health') {
    return _json(req, {
      'ok': true,
      'version': appVersion,
      'protocol': 'NON GELÉ (brouillon)',
      'data': 'fictive (bac à sable)',
      'persistence':
          'état persistant data/state.json (JSON local, tmp+rename+.bak, non atomique avec le journal JSONL, écart réconcilié au démarrage)',
      'groupMethod': s.groupMethod,
      'planId': s.plan?.planId,
      'planVersion': s.plan?.version,
    });
  }
  if (m == 'GET' && p == '/api/policy') {
    return _json(req, {
      'qWeights': [qWeightSeverity, qWeightExposure],
      'deadlines': deadlinesMin.map((k, v) => MapEntry('$k', v)),
      'exposureBands': '0/1-9/10-49/50-199/200+, inconnue≠0, décision E=4',
      'teams': teamDomains,
      'budget': budgetUnits,
      'grid': '${gridSizeKm}x${gridSizeKm} km, 20 km/h',
      'availability': '08:00-16:00, 14 jours',
      'note': 'Politique expérimentale provisoire, NON validée métier.',
    });
  }
  if (m == 'GET' && p == '/api/meta') return _json(req, s.meta.toJson());
  if (m == 'GET' && p == '/api/meta/calls') {
    return _json(req, {
      'calls': s.metaCalls.map((c) => c.toJson()).toList(),
      'note': 'Appels réels ou refus explicites. Aucun résultat simulé.',
    });
  }
  if (m == 'GET' && p == '/api/db') {
    final mongo = s.mongo;
    return _json(req, {
      'backend': s.mongoPrimary ? 'mongodb (principal) + json (sauvegarde)' : 'json (repli, MongoDB injoignable)',
      'mongoConnected': mongo?.connected ?? false,
      'mongoServerVersion': mongo?.serverVersion,
      'database': 'cityresolve_dev',
      'uri': 'mongodb://127.0.0.1:27017 (local uniquement)',
      'counts': mongo != null && mongo.connected ? await mongo.counts() : {},
      'lastError': s.mongoError,
      'transactions':
          'aucune transaction multi-documents (pas de replica set) : document d\'état + miroirs collection par collection, écart journal/état réconcilié au démarrage',
    });
  }
  if (m == 'GET' && p == '/api/state') {
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
    return _json(req, {'plans': s.planHistory});
  }
  if (m == 'POST' && p == '/api/meta/verify') {
    final connector = MetaConnector.fromEnvironment(Platform.environment);
    final (verified, record) = await connector.verify();
    s.meta = verified;
    s.metaCalls.add(record);
    await auditPersist(s, 'meta.verify',
        {'state': s.meta.state.name, 'latencyMs': record.latencyMs});
    return _json(req, {'meta': s.meta.toJson(), 'call': record.toJson()});
  }
  if (m == 'POST' && p == '/api/meta/extract') {
    final b = await _body(req);
    final rid = (b['reportId'] ?? '') as String;
    Report? rep;
    for (final r in s.reports) {
      if (r.id == rid) rep = r;
    }
    if (rep == null) {
      return _json(req, {'error': 'signalement inconnu: $rid'}, 404);
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
  if (m == 'GET' && p == '/api/scenarios') {
    return _json(req, {
      'scenarios': [
        {'kind': 'jouet-1', 'label': 'Jouet fixe nº1 (6 sign., 3 inc.)'},
        {'kind': 'jouet-s5', 'label': 'Jouet S5 (escalade)'},
        {'kind': 'dev', 'label': 'DEV généré (20 sign., 8 inc., graine)'},
      ]
    });
  }
  if (m == 'POST' && p == '/api/scenario/load') {
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
    regroup(s);
    await auditPersist(s, 'scenario.loaded', {'id': sc.id, 'label': sc.label});
    return _json(req, {'scenario': sc.id, 'label': sc.label});
  }
  if (m == 'GET' && p == '/api/reports') {
    return _json(req, {
      'reports': s.reports.map((r) => r.toJson()).toList(),
      'manual': s.manualReports.toList(),
      'truthKnown': s.truth.map((t) => t.toJson()).toList(),
    });
  }
  if (m == 'POST' && p == '/api/reports') {
    final b = await _body(req);
    final sevH = b['severityHint'] as int?;
    final expH = b['exposureHint'] as int?;
    if (sevH != null && (sevH < 1 || sevH > 5)) {
      return _json(req, {'error': 'severityHint hors 1..5 (ou null = inconnue)'}, 400);
    }
    if (expH != null && (expH < 0 || expH > 4)) {
      return _json(req, {'error': 'exposureHint hors 0..4 (ou null = inconnue)'}, 400);
    }
    s.reportSeq++;
    final r = Report(
      id: 'M${s.reportSeq}',
      text: (b['text'] ?? '') as String,
      category: (b['category'] ?? 'autre') as String,
      x: ((b['x'] ?? 2.5) as num).toDouble().clamp(0.0, 5.0),
      y: ((b['y'] ?? 2.5) as num).toDouble().clamp(0.0, 5.0),
      t: ((b['t'] ?? 500) as num).toInt(),
      severityHint: sevH,
      exposureHint: expH,
      photo: b['photo'] as String?,
      source: 'manuel',
    );
    s.reports.add(r);
    s.manualReports.add(r.id);
    regroup(s);
    await auditPersist(s, 'report.created', {'id': r.id, 'manual': true});
    return _json(req, {'id': r.id});
  }
  if (m == 'POST' && p == '/api/group') {
    final b = await _body(req);
    for (final k in ['distMaxM', 'deltaTMaxH', 'simMin']) {
      if (b[k] != null) s.groupParams[k] = (b[k] as num).toDouble();
    }
    final method = (b['method'] ?? 'classique') as String;
    final split = b['split'] == true;
    if (method == 'split') {
      // Regroupement découpé global, explicite : jamais de aggregate()
      // classique sur des identifiants ORIGINE:FAMILLE.
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
              'Méthode META indisponible (connecteur ${s.meta.state.name}) : aucun regroupement simulé, classique toujours disponible.',
          'meta': s.meta.toJson(),
        }, 400);
      }
      try {
        var groups = await proposeMatchingWithMeta(s.meta, s.reports,
            onRecord: (r) => s.metaCalls.add(r));
        var splitGroups = 0;
        if (split) {
          // Post-filtre découpage sur le regroupement Meta : un groupe
          // contenant un signalement multi-problème est découpé par
          // famille, puis agrégé par aggregateMixedGroups, jamais par
          // aggregate() classique. Le nombre de groupes découpés est
          // journalisé, et les groupes découpés restent dans metaGroups
          // (persistés tels quels, identifiants ORIGINE:FAMILLE inclus).
          final sp = splitGroupsByFamily(s.reports, groups);
          groups = sp.groups;
          splitGroups = sp.splitGroups;
        }
        s.metaGroups = groups;
        s.groups = groups;
        s.groupMethod = 'meta';
        s.incidents =
            aggregateForGroups(groups, {for (final r in s.reports) r.id: r});
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
      // Post-filtre découpage sur le regroupement classique : même règle
      // que pour Meta, agrégation mixte, jamais aggregate() classique
      // sur des identifiants découpés.
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
    return _json(req, {
      'incidents': s.incidents.map((i) => i.toJson()).toList(),
    });
  }
  if (m == 'POST' && p == '/api/plan') {
    final teams = activeTeams(s);
    if (teams.isEmpty) {
      return _json(req, {
        'error': 'Aucune équipe active (down : ${s.teamsDown.join(',')}).'
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
    if (s.plan == null) {
      return _json(req, {'error': 'aucun plan à valider'}, 400);
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
    if (s.plan == null) return _json(req, {'error': 'aucun plan'}, 400);
    final knownIds = s.incidents.map((i) => i.id).toSet();
    if (s.plan!.tasks.any((t) => !knownIds.contains(t.incidentId))) {
      return _json(req, {
        'error': 'plan périmé (incidents regroupés depuis) : relancer la planification'
      }, 400);
    }
    if (s.truth.isEmpty) {
      return _json(req, {'error': 'vérité terrain indisponible'}, 400);
    }
    // Appariement vérité sur les origines : sans cette projection, un
    // incident découpé [E1:eclairage] n'intersecterait jamais la vérité
    // [E1] et serait compté 'hors vérité', avec la vérité manquée, alors
    // même que le découpage a produit la bonne tâche. Les champs de
    // planification sont conservés (voir originMappedIncident) ; un
    // incident plein est inchangé par la projection.
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
      'note': 'Interventions SIMULÉES, pas des interventions urbaines réelles.',
    });
  }
  if (m == 'POST' && p == '/api/inject') {
    final b = await _body(req);
    final type = (b['type'] ?? 'reports') as String;
    if (s.plan == null) return _json(req, {'error': 'aucun plan'}, 400);
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
      regroup(s, keepPlan: true);
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
    final b = await _body(req);
    final configs = (b['configs'] as List? ?? []).take(5).toList();
    if (configs.isEmpty || s.truth.isEmpty) {
      return _json(req, {'error': 'configs requises + vérité terrain'}, 400);
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
    // Comparaison visible DEV : CLASSIQUE (référence) vs META (si disponible).
    final byId = {for (final r in s.reports) r.id: r};
    final classicGroups = groupReports(s.reports,
        distMaxM: (s.groupParams['distMaxM'] as num).toDouble(),
        deltaTMaxH: (s.groupParams['deltaTMaxH'] as num).toDouble(),
        simMin: (s.groupParams['simMin'] as num).toDouble());
    Map<String, dynamic> side(List<Group> gs, String method) {
      // Agrégation mixte : si metaGroups a été découpé (split: true),
      // aggregate() classique échouerait sur les identifiants découpés.
      // F1 scoré sur les origines, avec la même limite documentée que
      // metricsFor (une origine dans deux groupes découpés ne compte que
      // pour le dernier) ; la preuve du découpage reste le nombre
      // d'incidents, pas ce F1.
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
      // Désaccords au niveau origine : un groupe découpé [E1:eclairage]
      // et un groupe plein [E1] désignent le même signalement E1. Sans
      // cette projection, chaque paire découpée serait comptée comme
      // désaccord artificiel. Limite : une origine dans deux groupes
      // découpés ne garde que le dernier dans ces cartes.
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
              'classique': togetherC ? 'fusionnés' : 'séparés',
              'meta': togetherM ? 'fusionnés' : 'séparés',
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
          ? 'Aucune vérité terrain : F1 non calculé (explicite).'
          : 'F1 calculé uniquement sur les signalements disposant d\'une vérité DEV ; manuels exclus, absence signalée.',
      'note':
          'DEV exploratoire uniquement. Un meilleur F1 n\'est pas présenté comme une meilleure allocation : Q affichés séparément, aucune supériorité déclarée.',
    });
  }
  if (m == 'GET' && p == '/api/journal') {
    return _json(req, {'entries': s.audit.toJson()});
  }
  req.response.statusCode = 404;
  req.response.headers.contentType = ContentType.json;
  req.response.write(jsonEncode({'error': 'route inconnue'}));
  await req.response.close();
}

Future<void> _static(HttpRequest req, String path, ContentType ct) async {
  final f = File(path);
  if (!await f.exists()) {
    req.response.statusCode = 404;
    req.response.write('introuvable');
    await req.response.close();
    return;
  }
  req.response.headers.contentType = ct;
  await req.response.addStream(f.openRead());
  await req.response.close();
}
