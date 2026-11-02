// Journal d'audit : mémoire + fichier JSONL ajout seul.
import 'dart:convert';
import 'dart:io';

class AuditLog {
  final List<Map<String, dynamic>> entries = [];
  final String? path;
  AuditLog({this.path}) {
    // Reprise du journal existant : le fichier survit au redémarrage,
    // la séquence continue au lieu de repartir à 1.
    if (path != null) {
      final f = File(path!);
      if (f.existsSync()) {
        for (final line in f.readAsLinesSync()) {
          if (line.trim().isEmpty) continue;
          try {
            entries.add(jsonDecode(line) as Map<String, dynamic>);
          } catch (_) {
            // Ligne corrompue ignorée, jamais bloquante.
          }
        }
      }
    }
  }

  void append(String event, [Map<String, dynamic>? details]) {
    final e = {
      'seq': entries.length + 1,
      'at': DateTime.now().toUtc().toIso8601String(),
      'event': event,
      if (details != null) 'details': details,
    };
    entries.add(e);
    if (path != null) {
      File(path!).writeAsStringSync(jsonEncode(e) + '\n',
          mode: FileMode.append);
    }
  }

  List<Map<String, dynamic>> toJson() => entries;
}
