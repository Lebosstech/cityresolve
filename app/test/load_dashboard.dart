// Load test of the dashboard access patterns (§12).
//
// DEDICATED local database only: cityresolve_loadtest (never the
// application database, never Atlas, never Render). Identified synthetic
// data (source: 'loadtest'). Usage:
//   dart run test/load_dashboard.dart --n=10000
// Measures: median/p95/max latencies over 20 runs + explain()
// (stages, documents examined). No claim beyond the volume
// actually executed.
import 'dart:io';
import 'dart:math';

import 'package:mongo_dart/mongo_dart.dart';

const cats = [
  'nid-de-poule',
  'eclairage',
  'fuite-eau',
  'coupure-electrique',
  'arbre',
  'autre'
];

Future<Map<String, dynamic>> timed(
    String name, Future<void> Function() fn, int runs) async {
  final lat = <int>[];
  var errors = 0;
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    try {
      await fn();
    } catch (_) {
      errors++;
    }
    sw.stop();
    lat.add(sw.elapsedMicroseconds);
  }
  lat.sort();
  final q = (double p) => lat[(lat.length * p).floor().clamp(0, lat.length - 1)];
  final res = {
    'query': name,
    'runs': runs,
    'errors': errors,
    'median_ms': (q(0.5) / 1000).toStringAsFixed(2),
    'p95_ms': (q(0.95) / 1000).toStringAsFixed(2),
    'max_ms': (q(1.0) / 1000).toStringAsFixed(2),
  };
  print(res);
  return res;
}

Future<String> explainStage(Db db, Map<String, Object> cmd) async {
  try {
    final r = await db
        .collection(r'$cmd')
        .findOne({'explain': cmd, 'verbosity': 'executionStats'});
    String stage(Map<String, dynamic>? node) {
      if (node == null) return '?';
      final s = node['stage']?.toString() ?? '?';
      if (s == 'FETCH' ||
          s == 'PROJECTION_DEFAULT' ||
          s == 'LIMIT' ||
          s == 'SKIP' ||
          s == 'SORT') {
        return '$s<${stage(node['inputStage'] as Map<String, dynamic>?)}';
      }
      return s;
    }

    final stats = r?['executionStats'] as Map<String, dynamic>?;
    return '${stage(stats?['executionStages'] as Map<String, dynamic>?)} '
        'examined=${stats?['totalDocsExamined']} '
        'returned=${stats?['nReturned']}';
  } catch (e) {
    return 'explain unavailable ($e)';
  }
}

Future<void> main(List<String> args) async {
  var n = 10000;
  for (final a in args) {
    if (a.startsWith('--n=')) n = int.parse(a.substring(4));
  }
  if (n < 100 || n > 2000000) {
    stderr.writeln('n out of bounds [100, 2000000]');
    exit(2);
  }
  final db = await Db.create('mongodb://127.0.0.1:27017/cityresolve_loadtest');
  await db.open();
  final info = await db.getBuildInfo();
  print('Local MongoDB ${info['version']} — cityresolve_loadtest database (dedicated)');
  final col = db.collection('reports');
  await col.deleteMany({});
  final rng = Random(20261104);
  final base = DateTime.utc(2026, 10, 1);
  print('Inserting $n synthetic documents…');
  const batch = 2000;
  final swAll = Stopwatch()..start();
  for (var off = 0; off < n; off += batch) {
    final docs = <Map<String, dynamic>>[];
    for (var i = off; i < off + batch && i < n; i++) {
      docs.add({
        '_id': 'LT$i',
        'text': 'synthetic report $i ${cats[i % cats.length]} test street',
        'category': cats[i % cats.length],
        'x': rng.nextDouble() * 5.0,
        'y': rng.nextDouble() * 5.0,
        'receivedAt': base
            .add(Duration(minutes: rng.nextInt(30 * 24 * 60)))
            .toIso8601String(),
        'source': 'loadtest',
      });
    }
    await col.insertMany(docs, ordered: false);
  }
  print('Insertion finished in ${swAll.elapsedMilliseconds} ms');
  for (final spec in [
    {'keys': {'receivedAt': -1}, 'name': 'lt_receivedAt'},
    {'keys': {'category': 1}, 'name': 'lt_category'},
    {'keys': {'x': 1, 'y': 1}, 'name': 'lt_xy'},
  ]) {
    try {
      await col.createIndex(
          keys: (spec['keys'] as Map).cast<String, dynamic>(),
          name: spec['name'] as String);
    } catch (_) {}
  }
  try {
    await col.createIndex(
        keys: {'text': 'text'}, name: 'lt_text');
    print('text index created');
  } catch (e) {
    print('text index not created ($e)');
  }
  print('--- measurements (20 runs each) ---');
  await timed('recents-p1', () async {
    await col
        .find(where.sortBy('receivedAt', descending: true).limit(20))
        .toList();
  }, 20);
  await timed('recents-p5', () async {
    await col
        .find(where.sortBy('receivedAt', descending: true).skip(80).limit(20))
        .toList();
  }, 20);
  await timed('bbox-2km', () async {
    await col
        .find(where
            .gte('x', 1.0)
            .lte('x', 3.0)
            .gte('y', 1.0)
            .lte('y', 3.0)
            .limit(200))
        .toList();
  }, 20);
  await timed('count-category', () async {
    await col.count(where.eq('category', 'fuite-eau'));
  }, 20);
  await timed('text-search', () async {
    await col.find(where.match('text', 'caniveau').limit(20)).toList();
  }, 20);
  print('--- execution plans ---');
  print('recents: ${await explainStage(db, {
        'find': 'reports',
        'sort': {'receivedAt': -1},
        'limit': 20
      })}');
  print('bbox: ${await explainStage(db, {
        'find': 'reports',
        'filter': {
          'x': {'\$gte': 1.0, '\$lte': 3.0},
          'y': {'\$gte': 1.0, '\$lte': 3.0}
        },
        'limit': 200
      })}');
  final st = await db.collection(r'$cmd').findOne({'dbStats': 1, 'scale': 1});
  print('test db size: dataSize=${st?['dataSize']} storageSize=${st?['storageSize']} objects=${st?['objects']}');
  await db.close();
  print('Done. cityresolve_loadtest database kept for inspection, '
      'safe to delete (synthetic data).');
}
