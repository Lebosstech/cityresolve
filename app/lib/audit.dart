// Audit journal: memory + append-only JSONL file.
import 'dart:convert';
import 'dart:io';

class AuditLog {
  final List<Map<String, dynamic>> entries = [];
  final String? path;
  AuditLog({this.path}) {
    // Resume the existing journal: the file survives restarts,
    // the sequence continues instead of restarting at 1.
    if (path != null) {
      final f = File(path!);
      if (f.existsSync()) {
        for (final line in f.readAsLinesSync()) {
          if (line.trim().isEmpty) continue;
          try {
            entries.add(jsonDecode(line) as Map<String, dynamic>);
          } catch (_) {
            // Corrupt line ignored, never blocking.
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
