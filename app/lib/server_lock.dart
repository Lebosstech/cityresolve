// Verrou mono-instance DEV (patch poussé sur main, voir commit patch E4 + verrou) : un seul serveur
// par répertoire data/. Création exclusive du fichier server.lock.
// Si le fichier existe déjà, le second serveur doit refuser, avec le
// PID et la date du premier, au lieu d'écrire dans le même état.
// Limite assumée : après un arrêt brutal, le fichier peut rester
// (verrou périmé) ; il faut alors le supprimer manuellement après
// avoir vérifié qu'aucun serveur ne tourne sur ce répertoire.
// Ce n'est pas un verrou d'OS, et ce n'est pas une garantie de
// production.
import 'dart:io';

class ServerLockResult {
  final bool acquired;
  final int? holderPid;
  final String? holderStartedAt;
  final String path;
  const ServerLockResult(this.acquired, this.path,
      {this.holderPid, this.holderStartedAt});
}

ServerLockResult tryAcquireServerLock(String dataDir) {
  final dir = Directory(dataDir)..createSync(recursive: true);
  final path = '${dir.path}/server.lock';
  final file = File(path);
  try {
    file.createSync(exclusive: true);
    file.writeAsStringSync(
        'pid=${pid}\nstartedAt=${DateTime.now().toUtc().toIso8601String()}\n');
    return ServerLockResult(true, path);
  } on FileSystemException {
    var holderPid;
    String? startedAt;
    try {
      for (final line in file.readAsLinesSync()) {
        if (line.startsWith('pid=')) {
          holderPid = int.tryParse(line.substring(4));
        }
        if (line.startsWith('startedAt=')) {
          startedAt = line.substring(10);
        }
      }
    } catch (_) {}
    return ServerLockResult(false, path,
        holderPid: holderPid, holderStartedAt: startedAt);
  }
}

void releaseServerLock(String path) {
  try {
    File(path).deleteSync();
  } catch (_) {}
}
