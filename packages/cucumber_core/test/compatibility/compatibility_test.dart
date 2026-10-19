// Runs every Cucumber Compatibility Kit sample through the core SerialHost and
// compares the emitted messages with the expected ones (design §10).
import 'package:test/test.dart';

import 'cck.dart';
import 'samples.dart';

void main() {
  final directories = sampleDirectories();

  test('every sample has Dart glue or is skipped', () {
    final names = directories.map(sampleName).toSet();
    expect(names, hasLength(49));
    expect(
      names.difference({...sampleGlue.keys, ...skippedSamples.keys}),
      isEmpty,
    );
  });

  group('the harness', () {
    final minimal = directories.firstWhere((d) => sampleName(d) == 'minimal');

    test('accepts the expected messages themselves', () {
      final expected = expectedMessages(minimal);
      expect(compareMessages(expected, expected), isEmpty);
      expect(partialOrderProblems(expected), isEmpty);
    });

    test('detects a different status', () async {
      final actual = toJson(await runSample(minimal));
      final mutated = [
        for (final e in actual)
          if (e['testStepFinished'] != null)
            {
              'testStepFinished': {
                ...e['testStepFinished']! as Map<String, Object?>,
                'testStepResult': {
                  'status': 'FAILED',
                  'duration': {'seconds': 0, 'nanos': 0},
                },
              },
            }
          else
            e,
      ];
      expect(compareMessages(expectedMessages(minimal), mutated), isNotEmpty);
    });

    test('detects a wrong reference', () async {
      final actual = toJson(await runSample(minimal));
      final mutated = [
        for (final e in actual)
          if (e['testCase'] != null)
            {
              'testCase': {
                ...e['testCase']! as Map<String, Object?>,
                'pickleId': 'nope',
              },
            }
          else
            e,
      ];
      expect(compareMessages(expectedMessages(minimal), mutated), isNotEmpty);
      expect(partialOrderProblems(mutated), isNotEmpty);
    });

    test('detects wrong group offsets', () async {
      final actual = toJson(await runSample(minimal));
      final text = actual.map((e) => e.toString()).join();
      expect(text, contains('start: 7'));
      final mutated = [
        for (final e in actual)
          if (e['testCase'] != null) _replaceStart(e, 7, 8) else e,
      ];
      expect(compareMessages(expectedMessages(minimal), mutated), isNotEmpty);
    });

    test('detects messages out of order', () async {
      final actual = toJson(await runSample(minimal));
      final finished = actual.indexWhere((e) => e['testCaseFinished'] != null);
      final reordered = [...actual]..insert(0, actual[finished]);
      reordered.removeAt(finished + 1);
      expect(partialOrderProblems(reordered), isNotEmpty);
    });
  });

  for (final dir in directories) {
    final name = sampleName(dir);
    test(name, skip: skippedSamples[name], () async {
      final actual = toJson(await runSample(dir));
      final problems = [
        ...compareMessages(expectedMessages(dir), actual),
        ...partialOrderProblems(actual),
      ];
      if (problems.isNotEmpty) {
        fail('${problems.length} problem(s):\n\n${problems.join('\n\n')}');
      }
    });
  }
}

/// Replaces every `"start": from` with `to` in [json].
Map<String, Object?> _replaceStart(
  Map<String, Object?> json,
  int from,
  int to,
) {
  Object? walk(Object? value) => switch (value) {
    final Map<String, Object?> map => {
      for (final entry in map.entries)
        entry.key: entry.key == 'start' && entry.value == from
            ? to
            : walk(entry.value),
    },
    final List<Object?> list => [for (final item in list) walk(item)],
    _ => value,
  };
  return walk(json)! as Map<String, Object?>;
}
