// Vérification directe de MongoDB local (hors serveur CityResolve).
// Usage : dart run test/mongo_check.dart
// Affiche version serveur, collections, compteurs, index et identifiants
// d'échantillon. Lecture seule.
import 'dart:convert';

import 'package:mongo_dart/mongo_dart.dart';

Future<void> main() async {
  final db = await Db.create('mongodb://127.0.0.1:27017/cityresolve_dev');
  await db.open();
  final info = await db.getBuildInfo();
  print('MongoDB server version: ${info['version']}');
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
    final col = db.collection(name);
    final count = await col.count();
    var indexes = <String>[];
    try {
      final idx = await col.getIndexes();
      indexes = idx.map((i) => i['name'].toString()).toList();
    } catch (_) {}
    print('$name: $count doc(s), index: $indexes');
    if (name == 'reports' && count > 0) {
      final sample = await col.find().take(3).toList();
      print('  ids: ${sample.map((d) => d['_id']).toList()}');
    }
    if (name == 'journals' && count > 0) {
      final last = await col
          .find(where.sortBy('seq', descending: true).limit(1))
          .toList();
      print('  dernier seq: ${last.isEmpty ? null : last.first['seq']}');
    }
  }
  final state = await db.collection('state').findOne({'_id': 'current'});
  if (state != null) {
    print(jsonEncode({
      'state.auditSeq': state['auditSeq'],
      'state.reportSeq': state['reportSeq'],
      'state.planSeq': state['planSeq'],
      'state.scenarioId': state['scenarioId'],
      'state.planId': (state['plan'] as Map?)?['planId'],
    }));
  }
  await db.close();
}
