// Persistance locale CityResolve (équivalent SQLite adapté à Dart
// hors-ligne, zéro dépendance) : document JSON versionné dans data/.
//
// Écriture quasi-atomique : state.json.tmp -> rotation .bak -> rename.
// Une coupure peut laisser .tmp (ignoré) ou l'ancien .bak : la reprise
// essaie state.json puis state.json.bak. Ce n'est PAS une transaction
// atomique avec le journal d'audit : le serveur écrit l'audit PUIS l'état
// (champ auditSeq), et réconcilie tout écart au démarrage en le journalisant.
import 'dart:convert';
import 'dart:io';

class StoreLoad {
  final Map<String, dynamic>? doc;
  final bool recoveredFromBackup;
  final bool corrupt;
  const StoreLoad(this.doc, {this.recoveredFromBackup = false, this.corrupt = false});
}

class JsonStore {
  final String dirPath;
  const JsonStore(this.dirPath);

  File get _main => File('$dirPath/state.json');
  File get _bak => File('$dirPath/state.json.bak');
  File get _tmp => File('$dirPath/state.json.tmp');

  StoreLoad load() {
    Map<String, dynamic>? tryRead(File f) {
      try {
        if (!f.existsSync()) return null;
        final v = jsonDecode(f.readAsStringSync());
        return v is Map<String, dynamic> ? v : null;
      } catch (_) {
        return null;
      }
    }

    final main = tryRead(_main);
    if (main != null) return StoreLoad(main);
    final bak = tryRead(_bak);
    if (bak != null) {
      return StoreLoad(bak, recoveredFromBackup: true, corrupt: _main.existsSync());
    }
    return StoreLoad(null,
        corrupt: _main.existsSync() || _bak.existsSync());
  }

  void save(Map<String, dynamic> doc) {
    Directory(dirPath).createSync(recursive: true);
    _tmp.writeAsStringSync(jsonEncode(doc), flush: true);
    if (_bak.existsSync()) _bak.deleteSync();
    if (_main.existsSync()) _main.renameSync(_bak.path);
    _tmp.renameSync(_main.path);
  }
}
