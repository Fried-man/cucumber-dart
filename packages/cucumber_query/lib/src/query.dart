import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import 'lineage.dart';

/// The statuses of test step results, from the least to the most severe.
const List<messages.TestStepResultStatus> _statusesBySeverity = [
  messages.TestStepResultStatus.unknown,
  messages.TestStepResultStatus.passed,
  messages.TestStepResultStatus.skipped,
  messages.TestStepResultStatus.pending,
  messages.TestStepResultStatus.undefined,
  messages.TestStepResultStatus.ambiguous,
  messages.TestStepResultStatus.failed,
];

/// Given one Cucumber Message, finds another.
///
/// Messages refer to each other by ID, much like rows of a relational
/// database refer to each other by primary and foreign keys. A query indexes
/// the [messages.Envelope]s passed to [update] and answers questions about
/// them, such as the pickle of a test case or the most severe result of its
/// steps.
///
/// Queries can be made while a test run is incomplete, and then return
/// incomplete results. A message whose referenced message has not been seen
/// yields `null` or an empty list, rather than an error.
///
/// Methods that accept several kinds of message take an [Object] and throw an
/// [ArgumentError] for other kinds; their documentation lists the kinds.
final class Query {
  messages.Meta? _meta;
  messages.TestRunStarted? _testRunStarted;
  messages.TestRunFinished? _testRunFinished;
  final _testCaseStartedById = <String, messages.TestCaseStarted>{};
  final _lineageById = <String, Lineage>{};
  final _stepById = <String, messages.Step>{};
  final _pickleById = <String, messages.Pickle>{};
  final _pickleStepById = <String, messages.PickleStep>{};
  final _hookById = <String, messages.Hook>{};
  final _stepDefinitionById = <String, messages.StepDefinition>{};
  final _testCaseById = <String, messages.TestCase>{};
  final _testStepById = <String, messages.TestStep>{};
  final _testCaseFinishedByTestCaseStartedId =
      <String, messages.TestCaseFinished>{};
  final _testRunHookStartedById = <String, messages.TestRunHookStarted>{};
  final _testRunHookFinishedByTestRunHookStartedId =
      <String, messages.TestRunHookFinished>{};
  final _testStepsStartedByTestCaseStartedId =
      <String, List<messages.TestStepStarted>>{};
  final _testStepsFinishedByTestCaseStartedId =
      <String, List<messages.TestStepFinished>>{};
  final _attachmentsByTestCaseStartedId = <String, List<messages.Attachment>>{};
  final _attachmentsByTestRunHookStartedId =
      <String, List<messages.Attachment>>{};
  final _suggestionsByPickleStepId = <String, List<messages.Suggestion>>{};
  final _undefinedParameterTypes = <messages.UndefinedParameterType>[];

  /// Indexes the message in [envelope].
  void update(messages.Envelope envelope) {
    if (envelope.meta case final meta?) {
      _meta = meta;
    }
    if (envelope.gherkinDocument case final gherkinDocument?) {
      _updateGherkinDocument(gherkinDocument);
    }
    if (envelope.pickle case final pickle?) {
      _pickleById[pickle.id] = pickle;
      for (final pickleStep in pickle.steps) {
        _pickleStepById[pickleStep.id] = pickleStep;
      }
    }
    if (envelope.hook case final hook?) {
      _hookById[hook.id] = hook;
    }
    if (envelope.stepDefinition case final stepDefinition?) {
      _stepDefinitionById[stepDefinition.id] = stepDefinition;
    }
    if (envelope.testRunStarted case final testRunStarted?) {
      _testRunStarted = testRunStarted;
    }
    if (envelope.testRunHookStarted case final testRunHookStarted?) {
      _testRunHookStartedById[testRunHookStarted.id] = testRunHookStarted;
    }
    if (envelope.testRunHookFinished case final testRunHookFinished?) {
      _testRunHookFinishedByTestRunHookStartedId[testRunHookFinished
              .testRunHookStartedId] =
          testRunHookFinished;
    }
    if (envelope.testCase case final testCase?) {
      _testCaseById[testCase.id] = testCase;
      for (final testStep in testCase.testSteps) {
        _testStepById[testStep.id] = testStep;
      }
    }
    if (envelope.testCaseStarted case final testCaseStarted?) {
      _testCaseStartedById[testCaseStarted.id] = testCaseStarted;
    }
    if (envelope.testStepStarted case final testStepStarted?) {
      _testStepsStartedByTestCaseStartedId
          .putIfAbsent(testStepStarted.testCaseStartedId, () => [])
          .add(testStepStarted);
    }
    if (envelope.attachment case final attachment?) {
      if (attachment.testCaseStartedId case final id?) {
        _attachmentsByTestCaseStartedId
            .putIfAbsent(id, () => [])
            .add(attachment);
      }
      if (attachment.testRunHookStartedId case final id?) {
        _attachmentsByTestRunHookStartedId
            .putIfAbsent(id, () => [])
            .add(attachment);
      }
    }
    if (envelope.testStepFinished case final testStepFinished?) {
      _testStepsFinishedByTestCaseStartedId
          .putIfAbsent(testStepFinished.testCaseStartedId, () => [])
          .add(testStepFinished);
    }
    if (envelope.testCaseFinished case final testCaseFinished?) {
      _testCaseFinishedByTestCaseStartedId[testCaseFinished.testCaseStartedId] =
          testCaseFinished;
    }
    if (envelope.testRunFinished case final testRunFinished?) {
      _testRunFinished = testRunFinished;
    }
    if (envelope.suggestion case final suggestion?) {
      _suggestionsByPickleStepId
          .putIfAbsent(suggestion.pickleStepId, () => [])
          .add(suggestion);
    }
    if (envelope.undefinedParameterType case final undefinedParameterType?) {
      _undefinedParameterTypes.add(undefinedParameterType);
    }
  }

  void _updateGherkinDocument(messages.GherkinDocument gherkinDocument) {
    final feature = gherkinDocument.feature;
    if (feature == null) {
      return;
    }
    var lineage = Lineage(gherkinDocument: gherkinDocument, feature: feature);
    for (final child in feature.children) {
      if (child.background case final background?) {
        lineage = _copy(lineage, background: background);
        _updateSteps(background.steps);
      }
      if (child.scenario case final scenario?) {
        _updateScenario(scenario, lineage);
      }
      if (child.rule case final rule?) {
        var ruleLineage = _copy(lineage, rule: rule);
        for (final ruleChild in rule.children) {
          if (ruleChild.background case final background?) {
            ruleLineage = _copy(ruleLineage, ruleBackground: background);
            _updateSteps(background.steps);
          }
          if (ruleChild.scenario case final scenario?) {
            _updateScenario(scenario, ruleLineage);
          }
        }
      }
    }
  }

  void _updateScenario(messages.Scenario scenario, Lineage parent) {
    final lineage = _copy(parent, scenario: scenario);
    _lineageById[scenario.id] = lineage;
    for (final (examplesIndex, examples) in scenario.examples.indexed) {
      final examplesLineage = _copy(
        lineage,
        examples: examples,
        examplesIndex: examplesIndex,
      );
      _lineageById[examples.id] = examplesLineage;
      for (final (exampleIndex, example) in examples.tableBody.indexed) {
        _lineageById[example.id] = _copy(
          examplesLineage,
          example: example,
          exampleIndex: exampleIndex,
        );
      }
    }
    _updateSteps(scenario.steps);
  }

  void _updateSteps(List<messages.Step> steps) {
    for (final step in steps) {
      _stepById[step.id] = step;
    }
  }

  /// Counts the test cases started (excluding attempts that will be retried)
  /// by the most severe status of their steps.
  ///
  /// Every status is a key; test cases without finished steps are not
  /// counted.
  Map<messages.TestStepResultStatus, int>
  countMostSevereTestStepResultStatus() {
    final counts = {for (final status in _statusesBySeverity) status: 0};
    for (final testCaseStarted in findAllTestCaseStarted()) {
      final result = findMostSevereTestStepResultBy(testCaseStarted);
      if (result != null) {
        counts[result.status] = counts[result.status]! + 1;
      }
    }
    return counts;
  }

  /// The number of test cases started, excluding attempts that will be
  /// retried.
  int countTestCasesStarted() => findAllTestCaseStarted().length;

  /// All pickles.
  List<messages.Pickle> findAllPickles() => [..._pickleById.values];

  /// All pickle steps.
  List<messages.PickleStep> findAllPickleSteps() => [..._pickleStepById.values];

  /// All step definitions.
  List<messages.StepDefinition> findAllStepDefinitions() => [
    ..._stepDefinitionById.values,
  ];

  /// The started test cases, ordered by timestamp and then ID.
  ///
  /// Attempts that finished and will be retried are left out, so each test
  /// case appears once, with its final (or current) attempt.
  List<messages.TestCaseStarted> findAllTestCaseStarted() => _sortedByTime(
    _testCaseStartedById.values.where(
      (testCaseStarted) =>
          _testCaseFinishedByTestCaseStartedId[testCaseStarted.id]
              ?.willBeRetried !=
          true,
    ),
    timestamp: (testCaseStarted) => testCaseStarted.timestamp,
    id: (testCaseStarted) => testCaseStarted.id,
  );

  /// The finished test cases that will not be retried, ordered by timestamp
  /// and then by the ID of their [messages.TestCaseStarted].
  List<messages.TestCaseFinished> findAllTestCaseFinished() => _sortedByTime(
    _testCaseFinishedByTestCaseStartedId.values.where(
      (testCaseFinished) => !testCaseFinished.willBeRetried,
    ),
    timestamp: (testCaseFinished) => testCaseFinished.timestamp,
    id: (testCaseFinished) => testCaseFinished.testCaseStartedId,
  );

  /// [findAllTestCaseStarted], ordered by the value that [findOrderBy]
  /// finds for each, compared with [order].
  ///
  /// Test cases for which [findOrderBy] finds nothing come last. The order
  /// is stable.
  List<messages.TestCaseStarted> findAllTestCaseStartedOrderBy<T>(
    T? Function(Query query, messages.TestCaseStarted testCaseStarted)
    findOrderBy,
    int Function(T a, T b) order,
  ) => _orderBy(findAllTestCaseStarted(), findOrderBy, order);

  /// [findAllTestCaseFinished], ordered by the value that [findOrderBy]
  /// finds for each, compared with [order].
  ///
  /// Test cases for which [findOrderBy] finds nothing come last. The order
  /// is stable.
  List<messages.TestCaseFinished> findAllTestCaseFinishedOrderBy<T>(
    T? Function(Query query, messages.TestCaseFinished testCaseFinished)
    findOrderBy,
    int Function(T a, T b) order,
  ) => _orderBy(findAllTestCaseFinished(), findOrderBy, order);

  /// All test cases.
  List<messages.TestCase> findAllTestCases() => [..._testCaseById.values];

  /// All test steps of all test cases.
  List<messages.TestStep> findAllTestSteps() => [..._testStepById.values];

  /// All started test steps, grouped by test case attempt.
  List<messages.TestStepStarted> findAllTestStepStarted() => [
    for (final list in _testStepsStartedByTestCaseStartedId.values) ...list,
  ];

  /// All finished test steps, grouped by test case attempt.
  List<messages.TestStepFinished> findAllTestStepFinished() => [
    for (final list in _testStepsFinishedByTestCaseStartedId.values) ...list,
  ];

  /// All started test run hooks.
  List<messages.TestRunHookStarted> findAllTestRunHookStarted() => [
    ..._testRunHookStartedById.values,
  ];

  /// All finished test run hooks.
  List<messages.TestRunHookFinished> findAllTestRunHookFinished() => [
    ..._testRunHookFinishedByTestRunHookStartedId.values,
  ];

  /// All undefined parameter types.
  List<messages.UndefinedParameterType> findAllUndefinedParameterTypes() => [
    ..._undefinedParameterTypes,
  ];

  /// The attachments made by a test step or a test run hook.
  ///
  /// [element] is a [messages.TestStepFinished] or a
  /// [messages.TestRunHookFinished].
  List<messages.Attachment> findAttachmentsBy(
    Object element,
  ) => switch (element) {
    messages.TestStepFinished(:final testCaseStartedId, :final testStepId) => [
      for (final attachment
          in _attachmentsByTestCaseStartedId[testCaseStartedId] ??
              const <messages.Attachment>[])
        if (attachment.testStepId == testStepId) attachment,
    ],
    messages.TestRunHookFinished(:final testRunHookStartedId) => [
      ...?_attachmentsByTestRunHookStartedId[testRunHookStartedId],
    ],
    _ => _unsupported(element, 'findAttachmentsBy'),
  };

  /// The hook of a test step (`null` for a step of a pickle) or of a test run
  /// hook.
  ///
  /// [element] is a [messages.TestStep], a [messages.TestRunHookStarted] or
  /// a [messages.TestRunHookFinished].
  messages.Hook? findHookBy(Object element) => switch (element) {
    messages.TestStep(:final hookId) => _hookById[hookId],
    messages.TestRunHookStarted(:final hookId) => _hookById[hookId],
    final messages.TestRunHookFinished finished =>
      switch (findTestRunHookStartedBy(finished)) {
        final started? => findHookBy(started),
        null => null,
      },
    _ => _unsupported(element, 'findHookBy'),
  };

  /// The `meta` message.
  messages.Meta? findMeta() => _meta;

  /// The most severe result of the finished steps of a test case attempt, or
  /// `null` when none of its steps has finished.
  ///
  /// Of several results with the most severe status, the first is returned.
  ///
  /// [element] is a [messages.TestCaseStarted] or a
  /// [messages.TestCaseFinished].
  messages.TestStepResult? findMostSevereTestStepResultBy(Object element) {
    final testCaseStarted = _testCaseStarted(
      element,
      'findMostSevereTestStepResultBy',
    );
    if (testCaseStarted == null) {
      return null;
    }
    messages.TestStepResult? mostSevere;
    var mostSevereOrdinal = -1;
    for (final testStepFinished in findTestStepsFinishedBy(testCaseStarted)) {
      final result = testStepFinished.testStepResult;
      final ordinal = _statusesBySeverity.indexOf(result.status);
      if (ordinal > mostSevereOrdinal) {
        mostSevere = result;
        mostSevereOrdinal = ordinal;
      }
    }
    return mostSevere;
  }

  /// The location of [pickle] in its source: its own location or, for older
  /// messages without one, that of its example row or scenario.
  messages.Location? findLocationOf(messages.Pickle pickle) {
    if (pickle.location case final location?) {
      return location;
    }
    final lineage = findLineageBy(pickle);
    return lineage?.example?.location ?? lineage?.scenario?.location;
  }

  /// The pickle of a test case or of one of its attempts or steps.
  ///
  /// [element] is a [messages.TestCase], a [messages.TestCaseStarted], a
  /// [messages.TestCaseFinished], a [messages.TestStepStarted] or a
  /// [messages.TestStepFinished].
  messages.Pickle? findPickleBy(Object element) {
    final testCase = element is messages.TestCase
        ? element
        : _findTestCaseBy(element, 'findPickleBy');
    return testCase == null ? null : _pickleById[testCase.pickleId];
  }

  /// The pickle step of [testStep], or `null` for a hook step.
  messages.PickleStep? findPickleStepBy(messages.TestStep testStep) =>
      _pickleStepById[testStep.pickleStepId];

  /// The Gherkin step that [pickleStep] was made from.
  messages.Step? findStepBy(messages.PickleStep pickleStep) =>
      pickleStep.astNodeIds.isEmpty
      ? null
      : _stepById[pickleStep.astNodeIds.first];

  /// The step definitions that match [testStep]: none when it is undefined,
  /// several when it is ambiguous.
  List<messages.StepDefinition> findStepDefinitionsBy(
    messages.TestStep testStep,
  ) => [
    for (final id in testStep.stepDefinitionIds ?? const <String>[])
      ?_stepDefinitionById[id],
  ];

  /// The suggestions for an undefined pickle step, or for the steps of a
  /// pickle.
  ///
  /// [element] is a [messages.PickleStep] or a [messages.Pickle].
  List<messages.Suggestion> findSuggestionsBy(Object element) =>
      switch (element) {
        messages.PickleStep(:final id) => [...?_suggestionsByPickleStepId[id]],
        messages.Pickle(:final steps) => [
          for (final step in steps) ...findSuggestionsBy(step),
        ],
        _ => _unsupported(element, 'findSuggestionsBy'),
      };

  /// The step definition of [testStep] when exactly one matches it.
  messages.StepDefinition? findUnambiguousStepDefinitionBy(
    messages.TestStep testStep,
  ) => switch (testStep.stepDefinitionIds) {
    [final id] => _stepDefinitionById[id],
    _ => null,
  };

  /// The test case of an attempt or of one of its steps.
  ///
  /// [element] is a [messages.TestCaseStarted], a
  /// [messages.TestCaseFinished], a [messages.TestStepStarted] or a
  /// [messages.TestStepFinished].
  messages.TestCase? findTestCaseBy(Object element) =>
      _findTestCaseBy(element, 'findTestCaseBy');

  messages.TestCase? _findTestCaseBy(Object element, String method) {
    final testCaseStarted = element is messages.TestCaseStarted
        ? element
        : _findTestCaseStartedBy(element, method);
    return testCaseStarted == null
        ? null
        : _testCaseById[testCaseStarted.testCaseId];
  }

  /// The time between the start and the end of a test case attempt, or
  /// `null` while it has not finished.
  ///
  /// [element] is a [messages.TestCaseStarted] or a
  /// [messages.TestCaseFinished].
  messages.Duration? findTestCaseDurationBy(Object element) {
    final (started, finished) = switch (element) {
      final messages.TestCaseStarted started => (
        started,
        findTestCaseFinishedBy(started),
      ),
      final messages.TestCaseFinished finished => (
        findTestCaseStartedBy(finished),
        finished,
      ),
      _ => _unsupported(element, 'findTestCaseDurationBy'),
    };
    if (started == null || finished == null) {
      return null;
    }
    return _durationBetween(started.timestamp, finished.timestamp);
  }

  /// The attempt of a finished test case or of a test step.
  ///
  /// [element] is a [messages.TestCaseFinished], a
  /// [messages.TestStepStarted] or a [messages.TestStepFinished].
  messages.TestCaseStarted? findTestCaseStartedBy(Object element) =>
      _findTestCaseStartedBy(element, 'findTestCaseStartedBy');

  messages.TestCaseStarted? _findTestCaseStartedBy(
    Object element,
    String method,
  ) => switch (element) {
    messages.TestCaseFinished(:final testCaseStartedId) ||
    messages.TestStepStarted(:final testCaseStartedId) ||
    messages.TestStepFinished(
      :final testCaseStartedId,
    ) => _testCaseStartedById[testCaseStartedId],
    _ => _unsupported(element, method),
  };

  /// The end of [testCaseStarted], or `null` while it has not finished.
  messages.TestCaseFinished? findTestCaseFinishedBy(
    messages.TestCaseStarted testCaseStarted,
  ) => _testCaseFinishedByTestCaseStartedId[testCaseStarted.id];

  /// The start of [testRunHookFinished].
  messages.TestRunHookStarted? findTestRunHookStartedBy(
    messages.TestRunHookFinished testRunHookFinished,
  ) => _testRunHookStartedById[testRunHookFinished.testRunHookStartedId];

  /// The end of [testRunHookStarted], or `null` while it has not finished.
  messages.TestRunHookFinished? findTestRunHookFinishedBy(
    messages.TestRunHookStarted testRunHookStarted,
  ) => _testRunHookFinishedByTestRunHookStartedId[testRunHookStarted.id];

  /// The time between the start and the end of the test run, or `null`
  /// while it has not finished.
  messages.Duration? findTestRunDuration() {
    final started = _testRunStarted;
    final finished = _testRunFinished;
    if (started == null || finished == null) {
      return null;
    }
    return _durationBetween(started.timestamp, finished.timestamp);
  }

  /// The `testRunFinished` message.
  messages.TestRunFinished? findTestRunFinished() => _testRunFinished;

  /// The `testRunStarted` message.
  messages.TestRunStarted? findTestRunStarted() => _testRunStarted;

  /// The test step that started or finished.
  ///
  /// [element] is a [messages.TestStepStarted] or a
  /// [messages.TestStepFinished].
  messages.TestStep? findTestStepBy(Object element) => switch (element) {
    messages.TestStepStarted(:final testStepId) ||
    messages.TestStepFinished(:final testStepId) => _testStepById[testStepId],
    _ => _unsupported(element, 'findTestStepBy'),
  };

  /// The started steps of a test case attempt, in order.
  ///
  /// [element] is a [messages.TestCaseStarted] or a
  /// [messages.TestCaseFinished].
  List<messages.TestStepStarted> findTestStepsStartedBy(Object element) {
    final testCaseStartedId = switch (element) {
      messages.TestCaseStarted(:final id) => id,
      messages.TestCaseFinished(:final testCaseStartedId) => testCaseStartedId,
      _ => _unsupported(element, 'findTestStepsStartedBy'),
    };
    return [...?_testStepsStartedByTestCaseStartedId[testCaseStartedId]];
  }

  /// The finished steps of a test case attempt, in order.
  ///
  /// [element] is a [messages.TestCaseStarted] or a
  /// [messages.TestCaseFinished].
  List<messages.TestStepFinished> findTestStepsFinishedBy(Object element) {
    final testCaseStarted = _testCaseStarted(
      element,
      'findTestStepsFinishedBy',
    );
    return testCaseStarted == null
        ? []
        : [...?_testStepsFinishedByTestCaseStartedId[testCaseStarted.id]];
  }

  /// The finished steps of [testCaseStarted], each with its test step.
  List<(messages.TestStepFinished, messages.TestStep)>
  findTestStepFinishedAndTestStepBy(messages.TestCaseStarted testCaseStarted) =>
      [
        for (final testStepFinished in findTestStepsFinishedBy(testCaseStarted))
          if (_testStepById[testStepFinished.testStepId] case final testStep?)
            (testStepFinished, testStep),
      ];

  /// The ancestors in its Gherkin document of a pickle, or of the pickle of
  /// a test case attempt.
  ///
  /// [element] is a [messages.Pickle], a [messages.TestCaseStarted] or a
  /// [messages.TestCaseFinished].
  Lineage? findLineageBy(Object element) {
    final pickle = switch (element) {
      final messages.Pickle pickle => pickle,
      messages.TestCaseStarted() ||
      messages.TestCaseFinished() => findPickleBy(element),
      _ => _unsupported(element, 'findLineageBy'),
    };
    if (pickle == null || pickle.astNodeIds.isEmpty) {
      return null;
    }
    // The last AST node is the deepest: the example row of an outline.
    return _lineageById[pickle.astNodeIds.last];
  }

  /// The [messages.TestCaseStarted] of a test case attempt, given its start
  /// or its end (`null` for an end whose start is unknown).
  messages.TestCaseStarted? _testCaseStarted(Object element, String method) =>
      switch (element) {
        final messages.TestCaseStarted started => started,
        final messages.TestCaseFinished finished => findTestCaseStartedBy(
          finished,
        ),
        _ => _unsupported(element, method),
      };

  /// [elements] stably sorted by the value [findOrderBy] finds for each,
  /// with elements without a value last.
  List<E> _orderBy<E, T>(
    List<E> elements,
    T? Function(Query query, E element) findOrderBy,
    int Function(T a, T b) order,
  ) {
    final keyed = [
      for (final (index, element) in elements.indexed)
        (index, element, findOrderBy(this, element)),
    ];
    keyed.sort((a, b) {
      final (indexA, _, keyA) = a;
      final (indexB, _, keyB) = b;
      final result = switch ((keyA, keyB)) {
        (null, null) => 0,
        (null, _) => 1,
        (_, null) => -1,
        (final keyA?, final keyB?) => order(keyA, keyB),
      };
      return result == 0 ? indexA.compareTo(indexB) : result;
    });
    return [for (final (_, element, _) in keyed) element];
  }
}

Never _unsupported(Object? element, String method) => throw ArgumentError.value(
  element,
  'element',
  '$method does not accept a ${element.runtimeType}',
);

Lineage _copy(
  Lineage lineage, {
  messages.Background? background,
  messages.Rule? rule,
  messages.Background? ruleBackground,
  messages.Scenario? scenario,
  messages.Examples? examples,
  int? examplesIndex,
  messages.TableRow? example,
  int? exampleIndex,
}) => Lineage(
  gherkinDocument: lineage.gherkinDocument,
  feature: lineage.feature,
  background: background ?? lineage.background,
  rule: rule ?? lineage.rule,
  ruleBackground: ruleBackground ?? lineage.ruleBackground,
  scenario: scenario ?? lineage.scenario,
  examples: examples ?? lineage.examples,
  examplesIndex: examplesIndex ?? lineage.examplesIndex,
  example: example ?? lineage.example,
  exampleIndex: exampleIndex ?? lineage.exampleIndex,
);

/// [elements] sorted by [timestamp] and then by [id], keeping the original
/// order of ties.
List<E> _sortedByTime<E>(
  Iterable<E> elements, {
  required messages.Timestamp Function(E) timestamp,
  required String Function(E) id,
}) {
  final indexed = elements.indexed.toList()
    ..sort((a, b) {
      final ta = timestamp(a.$2);
      final tb = timestamp(b.$2);
      var result = ta.seconds.compareTo(tb.seconds);
      if (result == 0) {
        result = ta.nanos.compareTo(tb.nanos);
      }
      if (result == 0) {
        result = id(a.$2).compareTo(id(b.$2));
      }
      return result == 0 ? a.$1.compareTo(b.$1) : result;
    });
  return [for (final (_, element) in indexed) element];
}

messages.Duration _durationBetween(
  messages.Timestamp start,
  messages.Timestamp end,
) {
  const nanosPerSecond = 1000000000;
  final nanos =
      (end.seconds - start.seconds) * nanosPerSecond + end.nanos - start.nanos;
  final remainder = nanos % nanosPerSecond;
  return messages.Duration(
    seconds: (nanos - remainder) ~/ nanosPerSecond,
    nanos: remainder,
  );
}
