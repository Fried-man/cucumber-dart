# ADR-0021: Flutter widget-test host outside the pub workspace, built on the `dart test` host

- **Status:** Accepted
- **Date:** 2026-10-29
- **Design:** §3.1, §6, §8.4, §12

## Context

ADR-0004 plans `cucumber_flutter`: widget tests with a `WidgetTester` in the World. Building it raised five
questions.

- **The workspace.** The repository is a pub workspace that CI resolves with a plain Dart SDK, from 3.8.0 up.
  - A package that depends on `flutter_test` cannot be resolved without the Flutter SDK, so in the workspace it
    would break `dart pub get`, `dart analyze` and every job that does not install Flutter.
  - `flutter_test` also needs Dart 3.10 or later.
  - Flutter pins `test_api`; Flutter 3.44 pins 0.7.11, which is the oldest that `package:cucumber`'s
    `test: ^1.31.0` accepts.
- **Reuse.** The `dart test` host already has configuration, discovery, groups, `setUpAll`/`tearDownAll`, outcome
  mapping and merged reports. Only the declaration of each scenario's test differs (`testWidgets` instead of
  `test`). `flutter_test`'s wrappers use the same zone-scoped declarer as `package:test`.
- **Errors Flutter catches.** Flutter catches exceptions thrown while building, laying out or painting widgets and
  hands them to the test binding, which fails the test after its body. A step that pumps a broken widget therefore
  returns normally: the report would say PASSED while `flutter test` says failed.
- **Fake async.** `testWidgets` runs its body in a fake-async zone that only flushes its own microtask queue.
  Awaiting a future that was created in another zone continues in that zone's queue. `SuitePlan.runPickle` awaited
  the future of `start()`, which `setUpAll` had created, so every widget test hung at its first `pump`.
- **Run IDs.** `flutter test` runs each test file in its own process, so the process ID that correlates the report
  parts of one `dart test` run (ADR-0016) differs per file (§15).

## Decision

1. **Outside the root workspace.**
   - `packages/cucumber_flutter` is a pub workspace of its own (its example and fixtures are its members), resolved
     with `flutter pub get`.
   - It depends on `cucumber` by path, and overrides `cucumber`'s unpublished dependencies by path.
   - It requires Flutter 3.44 and Dart 3.12.
   - The root `analysis_options.yaml` excludes it. It has a copy of the rules, which a test keeps in step.
   - The CI test loop skips packages that depend on the Flutter SDK. A `flutter` job resolves, analyzes, tests and
     documents it, and runs the guide's `flutter` commands.
2. **Built on the `dart test` host.**
   - `package:cucumber/hosting.dart` exposes `declareCucumberSuite(options, {defaultWorld, declareScenario,
     afterUserCode})`. `CucumberSuite.declare` is implemented with it.
   - `PackageTestHost` gets a `ScenarioTestDeclarer`, whose default declares `package:test`'s `test`.
   - `cucumberWidgets`/`CucumberWidgetSuite` pass a declarer that calls `testWidgets` and runs the scenario with the
     tester in a zone value, which `FlutterWorld.tester` reads.
   - `FlutterWorld` is a mixin class that implements `World` by delegation, so a World can extend it or mix it in.
   - Without a `world`, the suite's World type is `FlutterWorld` and its factory makes a `DefaultFlutterWorld`, so
     snippets read `(FlutterWorld world, …)`.
3. **`SuitePlan.create(afterUserCode:)` in the core.** It runs after every step and hook body that returns normally,
   in the same guarded zone and context, and an error it throws fails that step or hook. The Flutter host passes a
   function that rethrows `WidgetTester.takeException()`.
4. **`runPickle` stays in its zone.** Once the run has started, `runPickle` no longer awaits `start()`. A core test
   runs it in a zone with its own microtask queue.
5. **Run ID under `flutter test`.** Without `CUCUMBER_RUN_ID`, and when `FLUTTER_TEST` is set, the run ID is
   `flutter-` plus a hash of `FONTCONFIG_FILE`. `flutter test` creates that file in a new temporary directory for
   each run and passes it to every test process. An end-to-end test checks that two entry files merge into one
   report without `CUCUMBER_RUN_ID`.

## Consequences

**Benefits:**
- The widget-test host is about a hundred lines. Configuration, reports, merging, outcomes and names behave as under
  `dart test` and are tested there.
- The Dart-only jobs, and contributors without Flutter, are unaffected.
- A step that leaves Flutter with an exception fails in the report as well as in `flutter test`.

**Costs:**
- `testWidgets` takes no location, so scenarios' tests point at the `cucumberWidgets` call. Groups keep their
  `.feature` locations, through `package:test`'s `group(location:)`. An upstream proposal stays open (§12).
- The run-ID fallback relies on an implementation detail of `flutter_tools`. If it changes, each test file gets its
  own run directory and the reports are no longer merged (each file's report overwrites the previous one). The
  end-to-end test would catch that, and `CUCUMBER_RUN_ID` still works.
- `cucumber_flutter` cannot be published before `cucumber` (§14.1).
- Flutter packages' API docs cannot be generated on Windows when the Flutter checkout has CRLF line endings (a
  dartdoc crash), so the `flutter` job generates them on Linux.

## Alternatives considered

- **In the root workspace.** Every job would need Flutter, and the minimum SDK would rise from 3.8 to 3.10.
- **A copy of the `dart test` host in `cucumber_flutter`.** Duplicates configuration, discovery, outcome mapping and
  report merging.
- **Our own `testWidgets` (to pass a location).** `WidgetTester`'s constructor is private, and `testWidgets` sets up
  the binding, semantics and leak tracking. Copying it would break with each Flutter release.
- **Failing on Flutter exceptions only at the end of the test.** The binding already does that, but then the report
  shows the scenario as passed.
- **Requiring `CUCUMBER_RUN_ID` under `flutter test`.** Simple and robust, but without it each test file's report
  would silently overwrite the others'.
