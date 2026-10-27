# Running with `dart test`

cucumber-dart has no runner of its own: an entry file declares `package:test` tests, so `dart test`, IDEs, CI
reporters, sharding and coverage work as for any other test. This page describes what they see. The examples come
from [`packages/cucumber/fixtures/guide`](../../packages/cucumber/fixtures/guide/).

## Tests and groups

A suite declares:

- a group for each feature, and inside it for each rule, scenario outline and `Examples` table;
- a test for each scenario, and for each row of an `Examples` table;
- a `setUpAll` that starts the run (and runs the `BeforeAll` hooks), and a `tearDownAll` that finishes it (and runs
  the `AfterAll` hooks, prints the summary and writes the reports).

Groups and tests are named after the Gherkin element's name, or its keyword when it has none. Example rows are named
`Example #<examples>.<row>`, counted from 1, followed by `: <name>` when the row's scenario name differs from the
outline's because the name has parameters. A test's full name, which `--name` matches, is its groups' names and its
own. In the guide's cart, this runs the second row of the outline:

<!-- run in: packages/cucumber/fixtures/guide -->
```sh
dart test --name "Example #1.2"
```

<!-- output -->
```text
Cart orders from €10.00 get 10% off <count> melons cost <total> Examples Example #1.2: 5 melons cost €9.00
+1: All tests passed!
```

A feature file that cannot be parsed becomes a failing test named after the file, with the parse errors as its
message.

## Locations and IDEs

Every group and test has the location of its line in the feature file. The JSON reporter, which IDEs use, reports
it, so the IDE's test view links each scenario to its `.feature` line, and runs or debugs a single scenario.
Breakpoints in step definitions work as in any test.

With the JSON reporter, `package:test` itself records a stack trace for every test and group, which takes several
seconds for thousands of scenarios ([Performance](../performance.md#not-ours-packagetest-with-the-json-reporter)).

## Tags

Gherkin tags become `package:test` tags without the `@`, so `dart test`'s tag options select scenarios:

<!-- run in: packages/cucumber/fixtures/guide -->
```sh
dart test --tags smoke
dart test --exclude-tags slow
dart test --tags "shop && !slow"
```

Declare the tags in `dart_test.yaml`, as `package:test` warns about undeclared tags. There, tags can also change how
their tests run, for example with a longer timeout:

<!-- excerpt: packages/cucumber/fixtures/guide/dart_test.yaml -->
```yaml
# Gherkin tags become package:test tags. Declaring them here avoids
# package:test's warnings about undeclared tags.
tags:
  shop:
  slow:
  smoke:
  wip:
```

`package:test` only accepts tags that are identifiers, possibly with hyphens, so tags such as `@issue:123` are not
mapped. They still work in Cucumber's tag expressions. `mapTags: false` turns the mapping off.

`dart test --tags` and the `tags` option select scenarios differently. `--tags` takes a `package:test` boolean
selector (`smoke && !slow`), and its tests are still declared and then filtered. The `tags` option takes a Cucumber
tag expression (`@smoke and not @slow`), and scenarios that it leaves out are not declared at all.

## Outcomes

A test reports the final attempt of its scenario:

| Scenario | The test |
|---|---|
| Passed | Passes |
| Skipped | Is skipped, with the step and the reason as the skip reason |
| Pending, undefined or ambiguous | Fails with a message that names the steps. For undefined steps, it includes snippets |
| Failed | Prints the failed step and its location, then fails with the step's original error and stack trace |

If a `BeforeAll` hook fails, every test fails without running its scenario, and the message shows the hook's error.
A failed `AfterAll` hook fails the `tearDownAll`.

## Retries

The `retry` option retries failed scenarios inside their tests. Do not use `package:test`'s `retry`: it would also
retry pending and undefined scenarios, and the reports would not know that an attempt was retried. The test's
timeout covers every attempt ([Configuration](configuration.md#timeouts)).

## Filtering

`dart test --name`, `--plain-name`, `--tags`, `--exclude-tags` and sharding select which declared tests run. The
scenarios of the tests that do not run are left out of the reports: a scenario is only reported once it starts. If
no test of an entry file runs, its `setUpAll` and `tearDownAll` do not run either, so its `BeforeAll` and `AfterAll`
hooks do not run and it writes no report.

<!-- run in: packages/cucumber/fixtures/guide -->
```sh
dart test --total-shards 2 --shard-index 0
dart test --total-shards 2 --shard-index 1
```

[Reports](reports.md#merging-ci-shards) shows how to merge the reports of shards.

## Test files and isolates

`dart test` runs each test file in its own isolate, several at once. Each entry file is a separate suite, with its own
`BeforeAll` and `AfterAll` hooks, Worlds and summary, and their reports are merged
([Reports](reports.md#reports-of-several-test-files)). The scenarios of one entry file run one after another.

Coverage works as for other tests: `dart test --coverage=coverage` collects the coverage of the code that the steps
call.
