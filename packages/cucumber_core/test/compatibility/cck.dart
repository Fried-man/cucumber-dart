// Compatibility kit comparison: normalisation, canonical IDs, per-type
// comparison and partial-order assertions (design §10, ADR-0019).
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cucumber_core/engine.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import 'samples.dart';

/// Samples that cannot pass yet, with the reason (design §10).
///
/// docs/compatibility.md lists them with the full justification, and
/// packages/cucumber/test/compatibility_report_test.dart keeps it in step.
const Map<String, String> skippedSamples = {
  'markdown':
      'cucumber_gherkin has no Gherkin-in-Markdown support '
      '(docs/compatibility.md)',
  'test-run-exception':
      "depends on fake-cucumber's --error switch (docs/compatibility.md)",
};

/// The directory holding the synced samples.
Directory samplesDirectory() {
  final library = Isolate.resolvePackageUriSync(
    Uri.parse(
      'package:cucumber_compatibility_kit/cucumber_compatibility_kit.dart',
    ),
  )!;
  return Directory.fromUri(library.resolve('../features/'));
}

/// The sample directories, sorted by name.
List<Directory> sampleDirectories() =>
    samplesDirectory().listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

String sampleName(Directory dir) =>
    dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);

/// Runs [dir]'s sample through the [SerialHost] with incrementing IDs.
Future<List<messages.Envelope>> runSample(Directory dir) async {
  final name = sampleName(dir);
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.feature'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final features = [
    for (final file in files)
      FeatureSource(
        'samples/$name/${file.uri.pathSegments.last}',
        file.readAsStringSync(),
      ),
  ];

  var options = const RunOptions();
  final arguments = File('${dir.path}/$name.arguments.txt');
  if (arguments.existsSync()) {
    final args = arguments.readAsStringSync().trim().split(RegExp(r'\s+'));
    var retry = 0;
    PickleOrder order = PickleOrder.defined;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--retry':
          retry = int.parse(args[++i]);
        case '--order':
          order = PickleOrder.parse(args[++i]);
        default:
          throw UnsupportedError('Unknown sample argument ${args[i]}');
      }
    }
    options = RunOptions(retry: retry, order: order);
  }

  final collector = CollectingPlugin();
  final plan = SuitePlan.create(
    features: features,
    glue: sampleGlue[name]!(dir),
    world: CckWorld.new,
    options: options,
    plugins: [collector],
    ids: IdScheme.incrementing(),
  );
  await const SerialHost().run(plan);
  return collector.envelopes;
}

/// Reads the expected messages of [dir]'s sample.
List<Map<String, Object?>> expectedMessages(Directory dir) {
  final name = sampleName(dir);
  return [
    for (final line in File('${dir.path}/$name.ndjson').readAsLinesSync())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
  ];
}

/// Converts envelopes to JSON maps.
List<Map<String, Object?>> toJson(List<messages.Envelope> envelopes) => [
  for (final envelope in envelopes)
    jsonDecode(messages.envelopeToJsonString(envelope)) as Map<String, Object?>,
];

const List<String> _typeOrder = [
  'meta',
  'source',
  'gherkinDocument',
  'parseError',
  'pickle',
  'parameterType',
  'stepDefinition',
  'hook',
  'undefinedParameterType',
  'testRunStarted',
  'testRunHookStarted',
  'testRunHookFinished',
  'testCase',
  'testCaseStarted',
  'testStepStarted',
  'suggestion',
  'attachment',
  'testStepFinished',
  'testCaseFinished',
  'testRunFinished',
];

String typeOf(Map<String, Object?> envelope) => envelope.keys.single;

/// Whether [key] holds a message ID or a reference to one. `workerId` names
/// a worker (such as the suite of a merged report part, design §8.4), not a
/// message.
bool _isIdKey(String key) =>
    key == 'id' || (key.endsWith('Id') && key != 'workerId');

bool _isIdsKey(String key) => key.endsWith('Ids');

/// Removes what the comparison ignores (design §10): timestamps, durations,
/// `meta` except its protocol version, code source references, messages,
/// exception details and snippet code.
Object? normalise(Object? value, {String? type, String? key}) {
  if (value is List<Object?>) {
    return [for (final item in value) normalise(item, type: type, key: key)];
  }
  if (value is! Map<String, Object?>) return value;
  if (key == 'meta') return {'protocolVersion': value['protocolVersion']};
  if (key == 'exception') return const <String, Object?>{};
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final k = entry.key;
    if (k == 'timestamp' || k == 'duration') continue;
    if (k == 'sourceReference' &&
        (type == 'stepDefinition' ||
            type == 'hook' ||
            type == 'parameterType')) {
      continue;
    }
    if (k == 'message' &&
        (type == 'testStepFinished' ||
            type == 'testRunHookFinished' ||
            type == 'testRunFinished')) {
      continue;
    }
    if (type == 'suggestion' &&
        key == 'snippets' &&
        (k == 'code' || k == 'language')) {
      continue;
    }
    result[k] = normalise(entry.value, type: type ?? k, key: k);
  }
  return result;
}

/// Sorts envelopes by type (stable) and replaces IDs with canonical ones, in
/// order of first appearance. Map keys are visited in sorted order so both
/// sides are traversed identically.
Map<String, List<Object?>> canonicalise(List<Map<String, Object?>> envelopes) {
  final byType = <String, List<Map<String, Object?>>>{};
  for (final envelope in envelopes) {
    (byType[typeOf(envelope)] ??= []).add(envelope);
  }
  final unknown = byType.keys.where((t) => !_typeOrder.contains(t));
  if (unknown.isNotEmpty) throw StateError('Unknown message types $unknown');

  final ids = <String, String>{};
  String map(String id) => ids.putIfAbsent(id, () => '#${ids.length}');
  Object? walk(Object? value) {
    if (value is List<Object?>) return [for (final item in value) walk(item)];
    if (value is! Map<String, Object?>) return value;
    final keys = value.keys.toList()..sort();
    return {
      for (final k in keys)
        k: switch (value[k]) {
          final String id when _isIdKey(k) => map(id),
          final List<Object?> list when _isIdsKey(k) => [
            for (final id in list) map(id! as String),
          ],
          final other => walk(other),
        },
    };
  }

  return {
    for (final type in _typeOrder)
      if (byType[type] case final list?)
        type: [
          for (final envelope in list)
            walk(normalise(envelope[type], type: type, key: type)),
        ],
  };
}

/// Returns the differences between [expected] and [actual], where [actual]
/// may have extra map entries.
List<String> subsetDifferences(Object? expected, Object? actual, String path) {
  if (expected is Map<String, Object?>) {
    if (actual is! Map<String, Object?>) {
      return ['$path: expected an object, got ${jsonEncode(actual)}'];
    }
    return [
      for (final entry in expected.entries)
        if (!actual.containsKey(entry.key))
          '$path.${entry.key}: missing (expected ${jsonEncode(entry.value)})'
        else
          ...subsetDifferences(
            entry.value,
            actual[entry.key],
            '$path.${entry.key}',
          ),
    ];
  }
  if (expected is List<Object?>) {
    if (actual is! List<Object?>) {
      return ['$path: expected a list, got ${jsonEncode(actual)}'];
    }
    if (actual.length != expected.length) {
      return [
        '$path: expected ${expected.length} items, got ${actual.length}\n'
            '  expected: ${jsonEncode(expected)}\n'
            '  actual:   ${jsonEncode(actual)}',
      ];
    }
    return [
      for (var i = 0; i < expected.length; i++)
        ...subsetDifferences(expected[i], actual[i], '$path[$i]'),
    ];
  }
  if (expected != actual) {
    return [
      '$path: expected ${jsonEncode(expected)}, got ${jsonEncode(actual)}',
    ];
  }
  return const [];
}

/// Compares the canonical message sequences of each type.
List<String> compareMessages(
  List<Map<String, Object?>> expected,
  List<Map<String, Object?>> actual,
) {
  final e = canonicalise(expected);
  final a = canonicalise(actual);
  final problems = <String>[];
  for (final type in {...e.keys, ...a.keys}) {
    final expectedList = e[type] ?? const [];
    final actualList = a[type] ?? const [];
    if (expectedList.length != actualList.length) {
      problems.add(
        '$type: expected ${expectedList.length} messages, got '
        '${actualList.length}\n'
        '  expected: ${expectedList.map(jsonEncode).join('\n            ')}\n'
        '  actual:   ${actualList.map(jsonEncode).join('\n            ')}',
      );
      continue;
    }
    for (var i = 0; i < expectedList.length; i++) {
      problems.addAll(
        subsetDifferences(expectedList[i], actualList[i], '$type[$i]'),
      );
    }
  }
  return problems;
}

/// Checks the partial order of [envelopes] (design §10): nothing is referenced
/// before it is emitted, everything started is finished, and nesting is
/// respected.
List<String> partialOrderProblems(List<Map<String, Object?>> envelopes) {
  final problems = <String>[];
  final defined = <String>{};
  final openTestCases = <String>{};
  final openSteps = <String>{};
  final openHooks = <String>{};
  var runStarted = false;
  var runFinished = false;

  void collect(Object? value, void Function(String key, String id) visit) {
    if (value is List<Object?>) {
      for (final item in value) {
        collect(item, visit);
      }
    } else if (value is Map<String, Object?>) {
      for (final entry in value.entries) {
        final v = entry.value;
        if (_isIdKey(entry.key) && v is String) {
          visit(entry.key, v);
        } else if (_isIdsKey(entry.key) && v is List<Object?>) {
          for (final id in v) {
            visit(entry.key, id! as String);
          }
        } else {
          collect(v, visit);
        }
      }
    }
  }

  for (var i = 0; i < envelopes.length; i++) {
    final envelope = envelopes[i];
    final type = typeOf(envelope);
    final message = envelope[type]! as Map<String, Object?>;
    if (runFinished) problems.add('#$i $type: after testRunFinished');

    collect(message, (key, id) {
      if (key != 'id' && !defined.contains(id)) {
        problems.add('#$i $type.$key: references "$id" before it is emitted');
      }
    });
    collect(message, (key, id) {
      if (key == 'id') defined.add(id);
    });

    final testCaseStartedId = message['testCaseStartedId'] as String?;
    switch (type) {
      case 'testRunStarted':
        runStarted = true;
      case 'testRunFinished':
        runFinished = true;
        if (openTestCases.isNotEmpty || openHooks.isNotEmpty) {
          problems.add('#$i testRunFinished: unfinished test cases or hooks');
        }
      case 'testCase' || 'testCaseStarted' || 'testRunHookStarted':
        if (!runStarted) problems.add('#$i $type: before testRunStarted');
        if (type == 'testCaseStarted') {
          if (openTestCases.isNotEmpty) {
            problems.add('#$i testCaseStarted: test cases overlap');
          }
          openTestCases.add(message['id']! as String);
        }
        if (type == 'testRunHookStarted') {
          openHooks.add(message['id']! as String);
        }
      case 'testRunHookFinished':
        if (!openHooks.remove(message['testRunHookStartedId'])) {
          problems.add('#$i testRunHookFinished: hook was not started');
        }
      case 'testStepStarted':
        if (!openTestCases.contains(testCaseStartedId)) {
          problems.add('#$i testStepStarted: outside its test case');
        }
        openSteps.add('$testCaseStartedId/${message['testStepId']}');
      case 'testStepFinished':
        if (!openSteps.remove('$testCaseStartedId/${message['testStepId']}')) {
          problems.add('#$i testStepFinished: step was not started');
        }
      case 'testCaseFinished':
        if (!openTestCases.remove(testCaseStartedId)) {
          problems.add('#$i testCaseFinished: test case was not started');
        }
        if (openSteps.any((s) => s.startsWith('$testCaseStartedId/'))) {
          problems.add('#$i testCaseFinished: unfinished steps');
        }
      case 'attachment' || 'suggestion':
        if (testCaseStartedId != null &&
            !openSteps.contains(
              '$testCaseStartedId/${message['testStepId']}',
            )) {
          problems.add('#$i $type: outside its test step');
        }
        final hookId = message['testRunHookStartedId'] as String?;
        if (hookId != null && !openHooks.contains(hookId)) {
          problems.add('#$i $type: outside its test-run hook');
        }
    }
  }
  if (envelopes.isNotEmpty && !runFinished) {
    problems.add('no testRunFinished');
  }
  return problems;
}
