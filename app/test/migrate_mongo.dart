// CityResolve migration: local MongoDB -> remote database (Atlas).
//
// Source: mongodb://127.0.0.1:27017/cityresolve_dev (frozen, read-only).
// Destination: CITYRESOLVE_MONGO_URI environment variable
//   (never displayed, never logged — set outside chat, e.g.:
//    [Environment]::SetEnvironmentVariable('CITYRESOLVE_MONGO_URI','...','User'))
// Copies the 8 collections preserving _ids, then recreates the secondary
// indexes. The local source is neither modified nor deleted.
// Usage: dart run test/migrate_mongo.dart [--dry-run]
import 'dart:io';

import 'package:mongo_dart/mongo_dart.dart';

const collections = [
  'state',
  'reports',
  'incidents',
  'plans',
  'teams',
  'simulations',
  'journals',
  'meta_calls',
];

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final destUri = Platform.environment['CITYRESOLVE_MONGO_URI'];
  if (destUri == null || destUri.isEmpty) {
    stderr.writeln(
        'CITYRESOLVE_MONGO_URI missing: set the variable (outside chat) then rerun.');
    exit(2);
  }
  if (destUri.contains('127.0.0.1') || destUri.contains('localhost')) {
    stderr.writeln('Destination looks local: migration cancelled.');
    exit(2);
  }
  final src = await Db.create('mongodb://127.0.0.1:27017/cityresolve_dev');
  await src.open();
  final dst = await Db.create(destUri);
  await dst.open();
  final info = await dst.getBuildInfo();
  print('Destination connected, MongoDB ${info['version']} (URI hidden).');

  for (final name in collections) {
    final srcCol = src.collection(name);
    final docs = await srcCol.find().toList();
    print('$name: ${docs.length} source document(s)');
    if (dryRun) continue;
    final dstCol = dst.collection(name);
    await dstCol.deleteMany({});
    if (docs.isNotEmpty) {
      await dstCol.insertMany(docs);
    }
    // Recreate the secondary indexes (except _id_).
    try {
      for (final idx in await srcCol.getIndexes()) {
        final idxName = idx['name']?.toString();
        if (idxName == null || idxName == '_id_') continue;
        await dstCol.createIndex(
          keys: (idx['key'] as Map).cast<String, dynamic>(),
          unique: idx['unique'] == true,
          name: idxName,
        );
      }
    } catch (e) {
      print('  indexes not recreated for $name: $e');
    }
    final copied = await dstCol.count();
    print('  -> $copied destination document(s)');
  }
  await src.close();
  await dst.close();
  print(dryRun ? 'Dry run finished (no writes).' : 'Migration finished.');
}
