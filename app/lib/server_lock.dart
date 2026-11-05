// DEV single-instance lock (patch pushed to main, see patch E4 + lock commit): one server
// per data/ directory. Exclusive creation of the server.lock file.
// If the file already exists, the second server must refuse, with the
// PID and start date of the first, instead of writing to the same state.
// Assumed limitation: after an abrupt stop, the file may remain
// (stale lock); it must then be deleted manually after
// checking that no server runs on this directory.
// This is not an OS lock, and it is not a production
// guarantee.
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
