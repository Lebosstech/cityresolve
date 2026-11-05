// Local CityResolve persistence (offline Dart-adapted SQLite equivalent,
// zero dependency): versioned JSON document in data/.
//
// Near-atomic write: state.json.tmp -> .bak rotation -> rename.
// An interruption may leave .tmp (ignored) or the old .bak: recovery
// tries state.json then state.json.bak. This is NOT an atomic
// transaction with the audit journal: the server writes the audit THEN the state
// (auditSeq field), and reconciles any gap at startup by logging it.
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
