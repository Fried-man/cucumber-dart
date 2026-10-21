import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cucumber/src/merge_lock.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/dart_test_runner.dart' show cucumberPackageDirectory;

/// Takes the lock [rounds] times, logging `in <name>` and `out <name>` to
/// [log] around a short critical section.
Future<void> _contend(String lockPath, String log, String name, int rounds) =>
    Isolate.run(() async {
      for (var i = 0; i < rounds; i++) {
        await withMergeLock(lockPath, () async {
          File(log).writeAsStringSync('in $name\n', mode: FileMode.append);
          await Future<void>.delayed(const Duration(milliseconds: 15));
          File(log).writeAsStringSync('out $name\n', mode: FileMode.append);
        });
      }
    });

void main() {
  late Directory root;
  late String lockPath;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cucumber_merge_lock_');
    lockPath = p.join(root.path, '.cucumber', 'merge.lock');
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('creates the lock file and releases its guard', () async {
    final lock = await MergeLock.acquire(lockPath);
    expect(File(lockPath).existsSync(), isTrue);
    expect(File('$lockPath.$pid').existsSync(), isTrue);
    await lock.release();
    await lock.release();
    expect(File('$lockPath.$pid').existsSync(), isFalse);
  });

  test('excludes the isolates of this process from one another', () async {
    final log = p.join(root.path, 'log.txt');
    await Future.wait([
      for (final name in ['a', 'b', 'c', 'd']) _contend(lockPath, log, name, 3),
    ]);
    final lines = File(log).readAsLinesSync();
    expect(lines, hasLength(24));
    for (var i = 0; i < lines.length; i += 2) {
      expect(lines[i], startsWith('in '), reason: lines.join('\n'));
      expect(
        lines[i + 1],
        'out ${lines[i].substring(3)}',
        reason: 'critical sections overlap:\n${lines.join('\n')}',
      );
    }
  });

  test('excludes other processes', () async {
    final lock = await MergeLock.acquire(lockPath);
    final child = await Process.start(Platform.resolvedExecutable, [
      p.join('test', 'support', 'merge_lock_child.dart'),
      lockPath,
    ], workingDirectory: cucumberPackageDirectory);
    final lines = <String>[];
    final waiting = Completer<void>();
    final acquired = Completer<void>();
    child.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        lines.add(line);
        if (line == 'waiting') waiting.complete();
        if (line == 'acquired') acquired.complete();
      },
    );
    final stderr = child.stderr.transform(utf8.decoder).join();
    try {
      await waiting.future.timeout(const Duration(minutes: 1));
      // The child cannot take the lock while this process holds it.
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(lines, ['waiting'], reason: 'the child took a held lock');
    } finally {
      await lock.release();
    }
    await acquired.future.timeout(const Duration(minutes: 1));
    expect(lines, ['waiting', 'acquired']);
    expect(await child.exitCode, 0, reason: await stderr);
  });

  test('waits for a guard held by another isolate of this process', () async {
    final guard = File('$lockPath.$pid')..createSync(recursive: true);
    var acquired = false;
    final waiting = MergeLock.acquire(lockPath).then((lock) {
      acquired = true;
      return lock;
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(acquired, isFalse);
    guard.deleteSync();
    final lock = await waiting.timeout(const Duration(seconds: 10));
    expect(acquired, isTrue);
    await lock.release();
  });

  test('takes over a stale guard', () async {
    File('$lockPath.$pid')
      ..createSync(recursive: true)
      ..setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
    final lock = await MergeLock.acquire(
      lockPath,
      staleAfter: const Duration(minutes: 1),
    ).timeout(const Duration(seconds: 10));
    await lock.release();
    expect(File('$lockPath.$pid').existsSync(), isFalse);
  });

  test('withMergeLock releases the lock when the action throws', () async {
    await expectLater(
      withMergeLock(lockPath, () => throw StateError('boom')),
      throwsStateError,
    );
    expect(File('$lockPath.$pid').existsSync(), isFalse);
    expect(await withMergeLock(lockPath, () => 42), 42);
  });
}
