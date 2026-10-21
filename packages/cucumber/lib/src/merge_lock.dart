import 'dart:async';
import 'dart:io';

/// An exclusive lock on a file, shared by every isolate and process that
/// merges reports into the same output directory (design §8.4).
///
/// `dart test` runs test files as isolates of one process, and
/// [RandomAccessFile.lock] alone does not exclude them from one another: on
/// Linux and macOS, file locks belong to the process, not the isolate. So the
/// lock has two layers:
///
/// 1. **Isolates of this process** take turns through a guard file next to
///    the lock file, `<path>.<pid>`, which is created exclusively and deleted
///    on [release]. A guard left behind by an isolate that died while holding
///    it is deleted once it is older than `staleAfter`.
/// 2. **Processes** take turns through an exclusive [RandomAccessFile.lock]
///    on [path], which the operating system releases if the process dies.
///
/// Only the holder of the guard opens [path], so no isolate of this process
/// can release another's process-level lock by closing the file.
final class MergeLock {
  MergeLock._(this.path, this._guard, this._file);

  /// The lock file.
  final String path;

  final File _guard;
  final RandomAccessFile _file;
  bool _released = false;

  /// Waits until the lock on [path] is free, takes it and returns it. The
  /// lock file and its directory are created if needed.
  ///
  /// The isolates of this process poll the guard file every [pollInterval].
  static Future<MergeLock> acquire(
    String path, {
    Duration staleAfter = const Duration(minutes: 2),
    Duration pollInterval = const Duration(milliseconds: 20),
  }) async {
    final lockFile = File(path);
    lockFile.parent.createSync(recursive: true);
    final guard = File('$path.$pid');
    var failures = 0;
    while (true) {
      try {
        guard.createSync(exclusive: true);
        break;
      } on FileSystemException {
        if (!guard.existsSync()) {
          // Released in the meantime, or a real error: retry a few times.
          if (++failures > 100) rethrow;
          continue;
        }
      }
      try {
        final age = DateTime.now().difference(guard.lastModifiedSync());
        if (age > staleAfter) guard.deleteSync();
      } on FileSystemException {
        // Released in the meantime.
      }
      await Future<void>.delayed(pollInterval);
    }

    RandomAccessFile? file;
    try {
      file = await lockFile.open(mode: FileMode.append);
      await file.lock(FileLock.blockingExclusive);
      return MergeLock._(path, guard, file);
    } on Object {
      await file?.close();
      _delete(guard);
      rethrow;
    }
  }

  /// Releases the lock. Releasing it again has no effect.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _file.unlock();
    } finally {
      await _file.close();
      _delete(_guard);
    }
  }

  static void _delete(File file) {
    try {
      file.deleteSync();
    } on FileSystemException {
      // Already gone.
    }
  }
}

/// Runs [action] while holding the [MergeLock] on [path], and releases it
/// afterwards, even if [action] throws.
Future<T> withMergeLock<T>(String path, FutureOr<T> Function() action) async {
  final lock = await MergeLock.acquire(path);
  try {
    return await action();
  } finally {
    await lock.release();
  }
}
