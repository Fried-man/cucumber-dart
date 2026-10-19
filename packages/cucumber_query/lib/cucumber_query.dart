/// Given one Cucumber Message, find another.
///
/// A [Query] indexes a stream of Cucumber Messages and answers questions
/// about it: the final attempt of each test case, the most severe status of
/// its steps, its pickle and that pickle's place in the Gherkin document, its
/// attachments and suggestions, durations, and counts.
///
/// ```dart
/// final query = Query();
/// envelopes.forEach(query.update);
///
/// for (final testCaseStarted in query.findAllTestCaseStarted()) {
///   final pickle = query.findPickleBy(testCaseStarted)!;
///   final result = query.findMostSevereTestStepResultBy(testCaseStarted);
///   print('${pickle.name}: ${result?.status.value}');
/// }
/// ```
///
/// This package is a Dart port of
/// [cucumber/query](https://github.com/cucumber/query), following its
/// JavaScript API. Its acceptance test data is synced from a pinned upstream
/// commit by `tool/sync.dart` (ADR-0005). Like the Java implementation, it
/// returns `null` instead of throwing when a referenced message is missing,
/// and also has `findAllTestCases`, and [LineageReducer.reduce] with an
/// optional pickle.
library;

export 'src/lineage.dart';
export 'src/query.dart';
