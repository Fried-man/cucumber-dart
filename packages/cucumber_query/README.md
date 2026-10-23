# cucumber_query

A Dart port of [cucumber/query][upstream]: given one [Cucumber Message][messages], find another. A `Query` indexes
the messages of a run and answers questions about it: the final attempt of each test case, the most severe status
of its steps, its pickle and that pickle's place in the Gherkin document, attachments, suggestions, durations and
counts. Formatters and report tools are built on it.

```dart
import 'package:cucumber_messages/cucumber_messages.dart';
import 'package:cucumber_query/cucumber_query.dart';

void printResults(Iterable<Envelope> envelopes) {
  final query = Query();
  envelopes.forEach(query.update);

  for (final testCaseStarted in query.findAllTestCaseStarted()) {
    final pickle = query.findPickleBy(testCaseStarted)!;
    final result = query.findMostSevereTestStepResultBy(testCaseStarted);
    print('${pickle.name}: ${result?.status.value}');
  }
}
```

[`example/cucumber_query_example.dart`](example/cucumber_query_example.dart) reads the messages from an NDJSON file.
`namingStrategy(...)` creates the upstream naming strategies for test cases (short or long, with or without the
feature name), which are `LineageReducer`s over a pickle's lineage in the Gherkin document.

## Status

This is an in-repository port used by [`cucumber`][cucumber] (Cucumber for Dart) for its summary and for report
merging. It is meant to be contributed to cucumber/query and published from there, so it is not published from this
repository (`publish_to: none`, [ADR-0005][adr-0005]). It follows the API of upstream release 16.1.1.

- **Data.** `tool/sync.dart` downloads the acceptance test data of a pinned upstream commit, checks its digest, and
  writes it to `testdata/`. `dart run tool/sync.dart --check` fails when it drifts.
- **Conformance.** The tests run the 41 queries of the upstream `QueryAcceptanceTest.java` and the 5 naming
  strategies on every sample that has expected results.
- **Differences.** It follows the JavaScript API (`Query.update(envelope)`; methods that accept several kinds of
  message take an `Object`), but returns `null` instead of throwing when a referenced message is missing, as the
  Java implementation does.

[upstream]: https://github.com/cucumber/query
[messages]: https://github.com/cucumber/messages
[cucumber]: https://github.com/Fried-man/cucumber-dart/tree/main/packages/cucumber
[adr-0005]: https://github.com/Fried-man/cucumber-dart/blob/main/docs/decisions/0005-monorepo-and-in-repo-ports.md
