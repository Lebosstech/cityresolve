// Local MongoDB persistence (primary database since 0.2.1).
//
// Connection: mongodb://127.0.0.1:27017/cityresolve_dev (local only,
// no public access). Driver: mongo_dart.
//
// Write model (assumed, no transactional promise):
// - one complete state document in `state` (_id=current) is authoritative;
// - mirror collections (reports, incidents, plans, simulations,
//   journals, meta_calls, teams) are rebuilt/upserted from that
//   document, written collection by collection, serialized by the server
//   queue. No multi-document transaction is used or
//   claimed (no replica set configured).
// - the local JSON (store.dart) is still written in parallel as a backup
//   and explicit fallback if MongoDB is unreachable at startup.
import 'package:mongo_dart/mongo_dart.dart';

class MongoStore {
  final String uri;
  Db? _db;
  bool connected = false;
  String? error;
  String? serverVersion;

  MongoStore({this.uri = 'mongodb://127.0.0.1:27017/cityresolve_dev'});

  DbCollection _col(String name) => _db!.collection(name);

  Future<bool> connect({Duration timeout = const Duration(seconds: 5)}) async {
    try {
      _db = await Db.create(uri);
      await _db!.open().timeout(timeout);
      final info = await _db!.getBuildInfo();
      serverVersion = info['version']?.toString();
      connected = true;
      return true;
    } catch (e) {
      error = '$e';
      connected = false;
      return false;
    }
  }

  Future<void> ensureIndexes() async {
    if (!connected) return;
    Future<void> idx(String col, Map<String, dynamic> keys,
        {bool unique = false, String? name}) async {
      try {
        await _col(col).createIndex(keys: keys, unique: unique, name: name);
      } catch (_) {
        // Index already present or incompatible: does not block startup.
      }
    }

    await idx('reports', {'t': 1}, name: 'reports_t');
    await idx('reports', {'x': 1, 'y': 1}, name: 'reports_xy');
    await idx('reports', {'source': 1}, name: 'reports_source');
    // Public access: recent receipts, categories, raw GPS positions.
    await idx('reports', {'receivedAt': -1}, name: 'reports_receivedAt');
    await idx('reports', {'category': 1}, name: 'reports_category');
    // Future full-text search at large volume (dashboard queries).
    // A single text index per collection; creation is a no-op if present.
    await idx('reports', {'text': 'text'}, name: 'reports_text');
    await idx('incidents', {'id': 1}, name: 'incidents_id');
    await idx('plans', {'version': 1}, name: 'plans_version');
    await idx('journals', {'seq': 1}, unique: true, name: 'journals_seq');
    await idx('journals', {'event': 1}, name: 'journals_event');
    await idx('simulations', {'planId': 1}, name: 'simulations_plan');
    await idx('meta_calls', {'kind': 1}, name: 'meta_calls_kind');
  }

  Future<Map<String, dynamic>?> loadState() async {
    if (!connected) return null;
    final doc = await _col('state').findOne({'_id': 'current'});
    if (doc == null) return null;
    final out = doc.cast<String, dynamic>();
    out.remove('_id');
    return out;
  }

  Future<void> _replaceById(
      String col, String id, Map<String, dynamic> doc) async {
    await _col(col).deleteOne({'_id': id});
    await _col(col).insertOne({...doc, '_id': id});
  }

  /// Complete backup: state document + mirror collections.
  /// [journalEntries]: complete audit entries (increasing seq).
  Future<void> saveSnapshot(
    Map<String, dynamic> doc, {
    required List<Map<String, dynamic>> journalEntries,
  }) async {
    if (!connected) return;
    await _replaceById('state', 'current', doc);

    // reports: upsert by permanent identifier + purge of missing ones.
    final reports = ((doc['reports'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    final reportIds = <String>{};
    for (final r in reports) {
      final id = r['id'].toString();
      reportIds.add(id);
      await _replaceById('reports', id, r);
    }
    final existingReports = await _col('reports').find().toList();
    for (final e in existingReports) {
      if (!reportIds.contains(e['_id'].toString())) {
        await _col('reports').deleteOne({'_id': e['_id']});
      }
    }

    // incidents: rebuilt snapshot (collection by collection).
    await _col('incidents').deleteMany({});
    final incidents = ((doc['incidents'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    if (incidents.isNotEmpty) {
      await _col('incidents').insertMany([
        for (final i in incidents) {...i, '_id': i['id'].toString()}
      ]);
    }

    // plans: versioned history, upsert by permanent planId.
    for (final h in ((doc['planHistory'] as List?) ?? [])) {
      final hm = (h as Map).cast<String, dynamic>();
      final pid = hm['planId'].toString();
      if (pid.isNotEmpty && pid != 'null') {
        await _replaceById('plans', pid, hm);
      }
    }

    // simulations: latest result per plan.
    if (doc['sim'] != null) {
      final sim = (doc['sim'] as Map).cast<String, dynamic>();
      final pid = doc['plan'] is Map
          ? (doc['plan'] as Map)['planId']?.toString() ?? 'sans-plan'
          : 'sans-plan';
      await _replaceById('simulations', pid, {
        'planId': pid,
        'result': sim,
        'robust': doc['robust'],
        'savedAt': doc['savedAt'],
      });
    }

    // journals: insert only new entries (seq = _id).
    final existingJournals = await _col('journals').find().toList();
    final knownSeq = existingJournals.map((e) => e['_id']).toSet();
    for (final e in journalEntries) {
      final seq = e['seq'];
      if (seq != null && !knownSeq.contains(seq)) {
        await _col('journals').insertOne({...e, '_id': seq});
      }
    }

    // meta_calls: upsert by call id.
    for (final c in ((doc['metaCalls'] as List?) ?? [])) {
      final cm = (c as Map).cast<String, dynamic>();
      await _replaceById('meta_calls', cm['id'].toString(), cm);
    }

    // teams: reference data (seeded once, never overwritten afterwards).
    if (await _col('teams').count() == 0) {
      await _col('teams').insertMany([
        {
          '_id': 'equipe-1',
          'id': 'equipe-1',
          'domains': ['voirie', 'espaces-verts']
        },
        {
          '_id': 'equipe-2',
          'id': 'equipe-2',
          'domains': ['voirie', 'reseaux']
        },
      ]);
    }
  }

  Future<Map<String, int>> counts() async {
    if (!connected) return {};
    final out = <String, int>{};
    for (final name in [
      'state',
      'reports',
      'incidents',
      'plans',
      'teams',
      'simulations',
      'journals',
      'meta_calls'
    ]) {
      out[name] = await _col(name).count();
    }
    return out;
  }

  Future<void> close() async {
    try {
      await _db?.close();
    } catch (_) {}
    connected = false;
  }
}
