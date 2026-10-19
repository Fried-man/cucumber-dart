// Runs the language-neutral acceptance test data of cucumber/query, synced by
// tool/sync.dart:
//
// - testdata/src/<sample>.<query>.results.json: the result of each query (as
//   in QueryAcceptanceTest.java) on testdata/src/<sample>.ndjson;
// - testdata/src/<sample>.naming-strategy.<strategy>.txt: the name of each
//   pickle (as in NamingStrategyAcceptanceTest.java).
import 'dart:convert';
import 'dart:io';

import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:cucumber_query/cucumber_query.dart';
import 'package:test/test.dart';

void main() {
  final testdata = Directory('testdata/src');
  final files = [
    for (final entity in testdata.listSync())
      if (entity is File) entity.uri.pathSegments.last,
  ]..sort();
  final samples = [
    for (final name in files)
      if (name.endsWith('.ndjson')) name.substring(0, name.indexOf('.')),
  ];

  test('the test data is synced and every expectation is checked', () {
    expect(samples, hasLength(greaterThanOrEqualTo(12)));
    final unknown = [
      for (final name in files)
        if (!name.endsWith('.ndjson') &&
            !_queries.keys.any(
              (query) => name.endsWith('.$query.results.json'),
            ) &&
            !_strategies.keys.any(
              (strategy) => name.endsWith('.naming-strategy.$strategy.txt'),
            ))
          name,
    ];
    expect(unknown, isEmpty, reason: 'expectations without a query');
  });

  for (final sample in samples) {
    group(sample, () {
      late final Query query = _load(File('${testdata.path}/$sample.ndjson'));

      for (final MapEntry(key: name, value: run) in _queries.entries) {
        final expected = File('${testdata.path}/$sample.$name.results.json');
        test(name, () {
          expect(_json(run(query)), jsonDecode(expected.readAsStringSync()));
        });
      }

      for (final MapEntry(key: name, value: strategy) in _strategies.entries) {
        final expected = File(
          '${testdata.path}/$sample.naming-strategy.$name.txt',
        );
        if (!expected.existsSync()) {
          continue;
        }
        test('naming strategy $name', () {
          final names = [
            for (final pickle in query.findAllPickles())
              if (query.findLineageBy(pickle) case final lineage?)
                strategy.reduce(lineage, pickle),
          ];
          expect(
            names,
            const LineSplitter().convert(expected.readAsStringSync()),
          );
        });
      }
    });
  }
}

Query _load(File ndjson) {
  final query = Query();
  for (final line in ndjson.readAsLinesSync()) {
    if (line.trim().isNotEmpty) {
      query.update(messages.parseEnvelopeJson(line));
    }
  }
  return query;
}

final Map<String, NamingStrategy> _strategies = {
  'long': namingStrategy(NamingStrategyLength.long),
  'long-exclude-feature-name': namingStrategy(
    NamingStrategyLength.long,
    featureName: NamingStrategyFeatureName.exclude,
  ),
  'long-with-pickle-name': namingStrategy(
    NamingStrategyLength.long,
    exampleName: NamingStrategyExampleName.pickle,
  ),
  'long-with-pickle-name-if-parameterized': namingStrategy(
    NamingStrategyLength.long,
    exampleName: NamingStrategyExampleName.numberAndPickleIfParameterized,
  ),
  'short': namingStrategy(NamingStrategyLength.short),
};

/// Orders pickles by URI, then line, then column, all descending.
int _reversePickleComparator(messages.Pickle a, messages.Pickle b) {
  if (a.uri != b.uri) {
    return b.uri.compareTo(a.uri);
  }
  final lineA = a.location?.line ?? 0;
  final lineB = b.location?.line ?? 0;
  if (lineA != lineB) {
    return lineB.compareTo(lineA);
  }
  return (b.location?.column ?? 0).compareTo(a.location?.column ?? 0);
}

/// The queries of QueryAcceptanceTest.java, by name.
final Map<String, Object? Function(Query query)> _queries = {
  'countMostSevereTestStepResultStatus': (query) =>
      query.countMostSevereTestStepResultStatus(),
  'countTestCasesStarted': (query) => query.countTestCasesStarted(),
  'findAllPickles': (query) => query.findAllPickles().length,
  'findAllPickleSteps': (query) => query.findAllPickleSteps().length,
  'findAllStepDefinitions': (query) => query.findAllStepDefinitions().length,
  'findAllTestCaseStarted': (query) => query.findAllTestCaseStarted().length,
  'findAllTestCaseStartedOrderBy': (query) => [
    for (final testCaseStarted in query.findAllTestCaseStartedOrderBy(
      (q, testCaseStarted) => q.findPickleBy(testCaseStarted),
      _reversePickleComparator,
    ))
      testCaseStarted.id,
  ],
  'findAllTestCaseFinished': (query) => query.findAllTestCaseFinished().length,
  'findAllTestCaseFinishedOrderBy': (query) => [
    for (final testCaseFinished in query.findAllTestCaseFinishedOrderBy(
      (q, testCaseFinished) => q.findPickleBy(testCaseFinished),
      _reversePickleComparator,
    ))
      testCaseFinished.testCaseStartedId,
  ],
  'findAllTestRunHookStarted': (query) =>
      query.findAllTestRunHookStarted().length,
  'findAllTestRunHookFinished': (query) =>
      query.findAllTestRunHookFinished().length,
  'findAllTestSteps': (query) => query.findAllTestSteps().length,
  'findAllTestStepStarted': (query) => query.findAllTestStepStarted().length,
  'findAllTestStepFinished': (query) => query.findAllTestStepFinished().length,
  'findAllTestCases': (query) => query.findAllTestCases().length,
  'findAllUndefinedParameterTypes': (query) => [
    for (final type in query.findAllUndefinedParameterTypes())
      [type.name, type.expression],
  ],
  'findAttachmentsBy': (query) => {
    'testStepFinished': [
      for (final testCaseStarted in query.findAllTestCaseStarted())
        for (final (testStepFinished, _)
            in query.findTestStepFinishedAndTestStepBy(testCaseStarted))
          for (final attachment in query.findAttachmentsBy(testStepFinished))
            [
              attachment.testStepId,
              attachment.testCaseStartedId,
              attachment.mediaType,
              attachment.contentEncoding.value,
            ],
    ],
    'testRunHookFinished': [
      for (final testRunHookFinished in query.findAllTestRunHookFinished())
        for (final attachment in query.findAttachmentsBy(testRunHookFinished))
          [
            attachment.testRunHookStartedId,
            attachment.mediaType,
            attachment.contentEncoding.value,
          ],
    ],
  },
  'findHookBy': (query) => {
    'testStep': [
      for (final testStep in query.findAllTestSteps())
        ?query.findHookBy(testStep)?.id,
    ],
    'testRunHookStarted': [
      for (final started in query.findAllTestRunHookStarted())
        ?query.findHookBy(started)?.id,
    ],
    'testRunHookFinished': [
      for (final finished in query.findAllTestRunHookFinished())
        ?query.findHookBy(finished)?.id,
    ],
  },
  'findLineageBy': (query) {
    final strategy = namingStrategy(NamingStrategyLength.long);
    List<String> names(Iterable<Object> elements) => [
      for (final element in elements)
        if (query.findLineageBy(element) case final lineage?)
          strategy.reduce(lineage),
    ];
    return {
      'testCaseStarted': names(query.findAllTestCaseStarted()),
      'testCaseFinished': names(query.findAllTestCaseFinished()),
      'pickle': names(query.findAllPickles()),
    };
  },
  'findLocationOf': (query) => [
    for (final pickle in query.findAllPickles()) ?query.findLocationOf(pickle),
  ],
  'findMeta': (query) => query.findMeta()?.implementation.name,
  'findMostSevereTestStepResultBy': (query) => {
    'testCaseStarted': [
      for (final testCaseStarted in query.findAllTestCaseStarted())
        ?query.findMostSevereTestStepResultBy(testCaseStarted)?.status,
    ],
    'testCaseFinished': [
      for (final testCaseFinished in query.findAllTestCaseFinished())
        ?query.findMostSevereTestStepResultBy(testCaseFinished)?.status,
    ],
  },
  'findPickleBy': (query) => {
    'testCaseStarted': [
      for (final element in query.findAllTestCaseStarted())
        query.findPickleBy(element)?.name,
    ],
    'testCaseFinished': [
      for (final element in query.findAllTestCaseFinished())
        query.findPickleBy(element)?.name,
    ],
    'testStepStarted': [
      for (final element in query.findAllTestStepStarted())
        query.findPickleBy(element)?.name,
    ],
    'testStepFinished': [
      for (final element in query.findAllTestStepFinished())
        query.findPickleBy(element)?.name,
    ],
  },
  'findPickleStepBy': (query) => [
    for (final testStep in query.findAllTestSteps())
      ?query.findPickleStepBy(testStep)?.text,
  ],
  'findStepBy': (query) => [
    for (final pickleStep in query.findAllPickleSteps())
      query.findStepBy(pickleStep)?.text,
  ],
  'findStepDefinitionsBy': (query) => [
    for (final testStep in query.findAllTestSteps())
      [
        for (final stepDefinition in query.findStepDefinitionsBy(testStep))
          stepDefinition.id,
      ],
  ],
  'findSuggestionsBy': (query) => {
    'pickleStep': [
      for (final pickleStep in query.findAllPickleSteps())
        for (final suggestion in query.findSuggestionsBy(pickleStep))
          suggestion.id,
    ],
    'pickle': [
      for (final pickle in query.findAllPickles())
        for (final suggestion in query.findSuggestionsBy(pickle)) suggestion.id,
    ],
  },
  'findUnambiguousStepDefinitionBy': (query) => [
    for (final testStep in query.findAllTestSteps())
      ?query.findUnambiguousStepDefinitionBy(testStep)?.id,
  ],
  'findTestCaseStartedBy': (query) => {
    'testCaseFinished': [
      for (final element in query.findAllTestCaseFinished())
        query.findTestCaseStartedBy(element)?.id,
    ],
    'testStepStarted': [
      for (final element in query.findAllTestStepStarted())
        query.findTestCaseStartedBy(element)?.id,
    ],
    'testStepFinished': [
      for (final element in query.findAllTestStepFinished())
        query.findTestCaseStartedBy(element)?.id,
    ],
  },
  'findTestCaseBy': (query) => {
    'testCaseStarted': [
      for (final element in query.findAllTestCaseStarted())
        query.findTestCaseBy(element)?.id,
    ],
    'testCaseFinished': [
      for (final element in query.findAllTestCaseFinished())
        query.findTestCaseBy(element)?.id,
    ],
    'testStepStarted': [
      for (final element in query.findAllTestStepStarted())
        query.findTestCaseBy(element)?.id,
    ],
    'testStepFinished': [
      for (final element in query.findAllTestStepFinished())
        query.findTestCaseBy(element)?.id,
    ],
  },
  'findTestCaseDurationBy': (query) => {
    'testCaseStarted': [
      for (final element in query.findAllTestCaseStarted())
        query.findTestCaseDurationBy(element),
    ],
    'testCaseFinished': [
      for (final element in query.findAllTestCaseFinished())
        query.findTestCaseDurationBy(element),
    ],
  },
  'findTestCaseFinishedBy': (query) => [
    for (final testCaseStarted in query.findAllTestCaseStarted())
      query.findTestCaseFinishedBy(testCaseStarted)?.testCaseStartedId,
  ],
  'findTestRunDuration': (query) => query.findTestRunDuration(),
  'findTestRunFinished': (query) => query.findTestRunFinished(),
  'findTestRunStarted': (query) => query.findTestRunStarted(),
  'findTestStepsStartedBy': (query) => {
    'testCaseStarted': [
      for (final element in query.findAllTestCaseStarted())
        [
          for (final started in query.findTestStepsStartedBy(element))
            started.testStepId,
        ],
    ],
    'testCaseFinished': [
      for (final element in query.findAllTestCaseFinished())
        [
          for (final started in query.findTestStepsStartedBy(element))
            started.testStepId,
        ],
    ],
  },
  'findTestStepsFinishedBy': (query) => {
    'testCaseStarted': [
      for (final element in query.findAllTestCaseStarted())
        [
          for (final finished in query.findTestStepsFinishedBy(element))
            finished.testStepId,
        ],
    ],
    'testCaseFinished': [
      for (final element in query.findAllTestCaseFinished())
        [
          for (final finished in query.findTestStepsFinishedBy(element))
            finished.testStepId,
        ],
    ],
  },
  'findTestRunHookFinishedBy': (query) => [
    for (final started in query.findAllTestRunHookStarted())
      query.findTestRunHookFinishedBy(started)?.testRunHookStartedId,
  ],
  'findTestRunHookStartedBy': (query) => [
    for (final finished in query.findAllTestRunHookFinished())
      query.findTestRunHookStartedBy(finished)?.id,
  ],
  'findTestStepBy': (query) => {
    'testStepStarted': [
      for (final testCaseStarted in query.findAllTestCaseStarted())
        for (final started in query.findTestStepsStartedBy(testCaseStarted))
          query.findTestStepBy(started)?.id,
    ],
    'testStepFinished': [
      for (final testCaseStarted in query.findAllTestCaseStarted())
        for (final finished in query.findTestStepsFinishedBy(testCaseStarted))
          query.findTestStepBy(finished)?.id,
    ],
  },
  'findTestStepFinishedAndTestStepBy': (query) => [
    for (final testCaseStarted in query.findAllTestCaseStarted())
      for (final (testStepFinished, testStep)
          in query.findTestStepFinishedAndTestStepBy(testCaseStarted))
        [testStepFinished.testStepId, testStep.id],
  ],
};

/// Converts a query result to JSON values, as Jackson does in the Java
/// acceptance test.
Object? _json(Object? value) => switch (value) {
  null || String() || num() || bool() => value,
  messages.TestStepResultStatus() => value.value,
  messages.Location() => value.toJson(),
  messages.Duration() => value.toJson(),
  messages.TestRunStarted() => value.toJson(),
  messages.TestRunFinished() => value.toJson(),
  Map<Object?, Object?>() => {
    for (final MapEntry(:key, :value) in value.entries)
      _json(key)! as String: _json(value),
  },
  Iterable<Object?>() => [for (final element in value) _json(element)],
  _ => throw ArgumentError.value(value, 'value', 'has no JSON form'),
};
