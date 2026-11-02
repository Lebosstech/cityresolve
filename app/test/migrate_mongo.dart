// Migration CityResolve : MongoDB local -> base distante (Atlas).
//
// Source : mongodb://127.0.0.1:27017/cityresolve_dev (figée, lecture seule).
// Destination : variable d'environnement CITYRESOLVE_MONGO_URI
//   (jamais affichée, jamais journalisée — définir hors chat, ex. :
//    [Environment]::SetEnvironmentVariable('CITYRESOLVE_MONGO_URI','...','User'))
// Copie les 8 collections en préservant les _id, puis recrée les index
// secondaires. La source locale n'est ni modifiée ni supprimée.
// Usage : dart run test/migrate_mongo.dart [--dry-run]
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
        'CITYRESOLVE_MONGO_URI absente : définir la variable (hors chat) puis relancer.');
    exit(2);
  }
  if (destUri.contains('127.0.0.1') || destUri.contains('localhost')) {
    stderr.writeln('La destination ressemble au local : migration annulée.');
    exit(2);
  }
  final src = await Db.create('mongodb://127.0.0.1:27017/cityresolve_dev');
  await src.open();
  final dst = await Db.create(destUri);
  await dst.open();
  final info = await dst.getBuildInfo();
  print('Destination connectée, MongoDB ${info['version']} (URI masquée).');

  for (final name in collections) {
    final srcCol = src.collection(name);
    final docs = await srcCol.find().toList();
    print('$name : ${docs.length} document(s) source');
    if (dryRun) continue;
    final dstCol = dst.collection(name);
    await dstCol.deleteMany({});
    if (docs.isNotEmpty) {
      await dstCol.insertMany(docs);
    }
    // Recréer les index secondaires (hors _id_).
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
      print('  index non recréés pour $name : $e');
    }
    final copied = await dstCol.count();
    print('  -> $copied document(s) destination');
  }
  await src.close();
  await dst.close();
  print(dryRun ? 'Dry-run terminé (aucune écriture).' : 'Migration terminée.');
}
