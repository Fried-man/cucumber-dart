# Performance

This page records how long cucumber-dart takes on a large generated suite, what that showed, and how to measure it
again. The benchmark is [`packages/cucumber/benchmark/`](../packages/cucumber/benchmark/), and
[`test/benchmark_test.dart`](../packages/cucumber/test/benchmark_test.dart) runs it on a tiny suite in CI, so it keeps
working.

## Rerunning it

From `packages/cucumber`:

<!-- not run: the benchmark takes minutes; test/benchmark_test.dart runs it on a tiny suite -->
```sh
dart run benchmark/benchmark.dart                    # the suite below, about 2 minutes
dart run benchmark/benchmark.dart --features 50      # a smaller suite
dart run benchmark/benchmark.dart --no-dart-test     # only the in-process phases
dart run benchmark/benchmark.dart --json build/benchmark/results.json
dart run benchmark/benchmark.dart --help             # --scenarios, --repeat, --dart-test-repeat
```

It generates the features into `build/benchmark/features/` and prints the median and minimum of each phase. Compare
runs on the same machine only: on the machine below, the same phase varies by up to about 20% from one run to the
next.

## The suite

Generated deterministically by [`benchmark/src/generator.dart`](../packages/cucumber/benchmark/src/generator.dart),
with the glue in [`benchmark/src/glue.dart`](../packages/cucumber/benchmark/src/glue.dart). Every scenario passes.

| | Count |
|---|---|
| Feature files (in 6 directories) | 300 |
| Pickles (`dart test` tests): 7 scenarios and 3 example rows per feature | 3,000 |
| Pickle steps, background steps included | 10,800 |
| Step definitions: 25 families of 8, Cucumber Expressions and regular expressions | 200 |
| Parameter types (`{color}`, `{weight}`), data table types | 2, 1 |
| Hooks: `BeforeAll`, 2 × `Before` (one tagged), `AfterStep` (tagged), `After`, `AfterAll` | 6 |
| Messages of a run (NDJSON) | 49,115 (19.2 MB) |

Each feature has a background, tags (some of them tag expressions select, one that `package:test` cannot take), a
data table, a doc string, and a rule with a scenario outline. Every pickle step is matched against all 200 step
definitions and matches one.

## Results

Windows 11, 16 processors, Dart 3.12.1, 2026-10-27. In-process phases: the median of 5 runs after a warm-up.
`dart test`: the median of 3 runs of `dart test benchmark/suite_test.dart`, wall time of the whole process.
"Before" is the code before the two fixes below; "after" is the code with them.

**In process**

| Phase | What it covers | Before | After |
|---|---|---|---|
| discover + read | `discoverFeatures`: list and read the 300 files | 21 ms | 19 ms |
| parse | `SourceLoader`: Gherkin, pickles, AST index | 59 ms | 61 ms |
| glue loading | Construct the glue values and `SupportCodeLibrary.load` | **110 ms** | **14 ms** |
| `SuitePlan.create` | Parse, glue loading, filter, order, plan tree | **209 ms** | **78 ms** |
| `SerialHost` run | Assemble and run all 3,000 test cases, no plugins | 493 ms | 412 ms |
| `SerialHost` run + NDJSON | The same, serializing every message | 692 ms | 693 ms |
| parse NDJSON | Read the messages back, as the automatic merge does | 145 ms | 121 ms |
| `mergeReportParts` | Merge the run as one report part | 251 ms | 251 ms |
| HTML report | `MessagesToHtmlWriter` to memory | 192 ms | 191 ms |
| summary | `formatSummaryOf` | 28 ms | 22 ms |

The fixes do not touch the phases from `SerialHost` run on, so their differences are noise.

**`dart test`**

| Run | Before | After |
|---|---|---|
| Baseline: the same entry file on 1 scenario (compiling, starting the isolate) | 1.1 s | 1.0 s |
| The suite (expanded reporter) | 2.6 s | 2.3 s |
| The suite with `message:`, `html:` and `summary` (`CUCUMBER_PLUGIN`) | **11.9 s** | **3.7 s** |
| The suite with the JSON reporter, as IDEs run it | 7.9 s | 7.8 s |

Under `dart test`, the suite costs about 1.3 s more than the baseline: about 0.4 ms per scenario for declaring,
running and reporting it. The three reports add about 1.4 s, for 49,115 messages.

## What it showed

### Fixed: writing reports one message at a time

Every `IOSink.write` to a file becomes its own asynchronous write. The report part (§8.4), `NdjsonPlugin`, `HtmlPlugin`
and the merged outputs wrote each message and its line break separately: about 100,000 writes for the part alone,
which the suite's `tearDownAll` then waited for. They now write through a `BufferedFileSink`
([`lib/src/buffered_sink.dart`](../packages/cucumber/lib/src/buffered_sink.dart)), which passes the text on every 64 Ki
characters. NDJSON outputs (the part and `NdjsonPlugin`) also flush after `testRunStarted`, each `testCaseFinished`
and `testRunHookFinished`, and `testRunFinished`. So a part that another suite merges while it is still being written
still ends with whole test cases, and a run in progress keeps changing on disk as its scenarios finish, which pruning
relies on (design §8.4).

Result: the reports add about 1.4 s instead of 9.3 s. Writing one 49,115-message output went from about 1 s to
0.2 s.

### Fixed: parsing the whole stack trace for each glue value

Each glue value records where it was constructed (design §4.2). `SourceReference.capture` parsed the whole current
stack trace with `package:stack_trace`, about 1.5 ms per call in a test, although it only needs the first frame
outside the cucumber packages. Getting the trace as a string takes about 25 µs. On the VM it now parses the frames
one at a time and stops at the first user frame, which is usually within the first five. Other platforms still parse
the whole trace.

Result: glue loading takes 14 ms instead of 110 ms for 209 glue values. Every entry file pays this cost, because
each one loads its glue in its own isolate.

### Not ours: `package:test` with the JSON reporter

With the JSON reporter (`dart test -r json`, which the Dart IDE plugins use) or a test selected by line,
`package:test` captures a stack trace for every `test()` and `group()` and formats it for the runner
(`collectTraces` in `test_core`). The deeper the groups are nested, the deeper the traces, and the costlier they are.
In this suite, it makes the run take 7.8 s instead of 2.3 s. Declaring the same 3,000 tests and 1,200 groups
with plain `test()` and `group()` calls, without cucumber, costs the same: 8.5 s with `-r json` against 2.2 s with
`-r silent`. cucumber-dart passes an explicit `location` for every test and group (design §6), so the JSON reporter
never needs these traces, but `package:test` has no way to turn them off. Command-line runs with the default
reporter are not affected.

### Left as is

- **Step matching.** About half of a `SerialHost` run (200 ms of 410 ms) is matching every pickle step against every
  step definition: 2.16 million attempts, about 0.1 µs each. Every Cucumber implementation matches this way. Caching
  the matches by step text would help suites that repeat the same step text often, but it is not a defect, and at
  about 40 µs per step for everything (matching, hooks, messages and IDs), the engine's overhead is small next to
  real step bodies.
- **Work when a suite ends.** With reports, each suite re-reads, merges and rewrites the parts of every suite of the
  run that has finished so far (design §8.4). For 49,115 messages, parsing, merging and writing NDJSON and HTML take
  about 0.8 s. With many entry files, the total work grows with the number of entry files times the size of the
  report. This benchmark has one entry file, so it does not measure that.
