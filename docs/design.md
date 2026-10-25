# cucumber-dart design

- **Status:** Draft. The direction is agreed. Items marked *(Proposed)* are still open for review.
- **Last updated:** 2026-10-25
- **Decision log:** [`docs/decisions/`](decisions/README.md)

This document describes how cucumber-dart becomes a production-grade Cucumber implementation for Dart that
matches [cucumber-js], [cucumber-jvm], [cucumber-ruby] and [godog]. It is built on the official Cucumber
components that already have Dart ports:

- [`cucumber_messages`][messages]
- [`cucumber_gherkin`][gherkin]
- [`cucumber_expressions`][expressions]

---

## 1. Goals and non-goals

### Goals

1. **Behaviour parity** with the official implementations:
   - Gherkin, including Rules, Backgrounds, Outlines and i18n
   - Cucumber Expressions and regular expressions
   - hooks (scenario, step, test-run), tags, retries, dry run, snippets and attachments
   - typed data tables and doc strings
   - strict result semantics
2. **Protocol parity.** We emit the [Cucumber Messages][messages] protocol (v34) as the single source of truth for all
   reporting.
3. **Conformance.** We pass the [Cucumber Compatibility Kit][cck] (CCK), and publish a short, justified skip list.
4. **First-class `dart test` integration:**
   - IDE run and debug
   - coverage and sharding
   - tags
   - navigation to `.feature` lines
5. **Flutter-ready core.** The engine has no `dart:io`, `dart:mirrors`, Flutter or `package:test` dependency.
6. **A credible path to official status** under `github.com/cucumber`:
   - official component usage
   - CCK conformance
   - upstream contributions of the shared libraries we port

### Non-goals for v1 (planned later)

| Item | Plan |
|---|---|
| Standalone CLI runner | A thin facade may follow later (ADR-0001) |
| Flutter adapters (`testWidgets`, on-device `integration_test`) | Designed for now, built after v1 (ADR-0004) |
| Annotation + `build_runner` codegen | Designed for now, built after v1 (ADR-0002) |
| JUnit XML, legacy Cucumber JSON, pretty/progress console, rerun output | After v1 (ADR-0009) |
| Gherkin in Markdown (`.feature.md`) | Needs Markdown support in `cucumber_gherkin` first |
| Parallel scenarios inside one isolate | Parallelism comes from multiple test files/isolates (ADR-0016) |

---

## 2. What the reference implementations do

| | cucumber-js 13.3 | cucumber-jvm 8.0 | cucumber-ruby 11.1+ | godog 0.16 | **cucumber-dart** |
|---|---|---|---|---|---|
| Host | Own CLI plus programmatic API | JUnit Platform engine (strategic) plus CLI | Own CLI | `go test` subtests (CLI deprecated) | `dart test` (later `flutter test`) plus a thin CLI later |
| Step API | Global `Given(...)`, `this` = World | Annotations; lambdas (fragile) | Global DSL blocks run in the World | `ctx.Step(regex, func)` via reflection | Explicit glue values (codegen later) |
| Expressions | Cucumber + regex | Cucumber + regex | Cucumber + regex | Regex only | Cucumber + regex |
| Scenario state | World per attempt | DI containers | World per scenario | `context.Context` or closures | Typed World per attempt |
| Messages / CCK | Yes / yes (skips 5) | Yes / yes (skips ~10) | Yes / key sets only | No / no | Yes / yes |
| Formatters | `@cucumber/*` libraries | Shared Java libraries | Mixed | Own | In-repo ports of the shared libraries |

**Lessons we carry forward:**

- **cucumber-jvm.**
  - The core knows nothing about reflection; step definitions are just `execute(Object[])`.
  - The test-framework engine is the main runner.
  - Its lambda backend needed per-scenario re-instantiation and `Unsafe` tricks. The maintainers proposed a
    static DSL instead (#2279). Our glue values follow that proposal.
- **godog.** Its CLI fought the toolchain (`go test` binary hijacking) and was deprecated. It also never adopted
  messages, the CCK or Cucumber Expressions, and is now listed as unmaintained.
  So: integrate with `dart test`, and adopt all three from day one.
- **cucumber-js.**
  - A new World per attempt.
  - A zone-like `world` accessor.
  - Formatters that only consume messages.
  - Console output delegated to the shared `pretty-formatter`.
- **Existing Dart packages** (`gherkin`, `flutter_gherkin`, `bdd_widget_test`, `ogurets`):
  - None uses the official parser.
  - None has real Cucumber Expressions or messages.
  - The runtime runners could not integrate with `package:test`.
  - The mirrors-based one cannot run on Flutter.
  - The most popular, `bdd_widget_test`, generates plain widget tests.

---

## 3. Architecture

### 3.1 Packages

This is a pub workspace with Dart SDK `^3.8.0`, which is the minimum required by `cucumber_gherkin`.

```
cucumber-dart/
├─ pubspec.yaml                      workspace root (publish_to: none)
├─ docs/                             this design + decision log
└─ packages/
   ├─ cucumber_core/                 runner-agnostic engine + public glue API (pure Dart)
   ├─ cucumber/                      dart test host, discovery, config, outputs, merge CLI; re-exports the core API
   ├─ cucumber_compatibility_kit/    CCK samples synced from npm + helpers (future compatibility-kit/dart)
   ├─ cucumber_html_formatter/       [M5] Dart wrapper around the prebuilt @cucumber/html-formatter assets
   ├─ cucumber_ci_environment/       [M5] port of cucumber/ci-environment (meta.ci)
   ├─ cucumber_query/                [M5] port of cucumber/query (summary, merge, future formatters)
   ├─ cucumber_flutter/              [post-v1] flutter_test / integration_test host
   └─ cucumber_builder/              [post-v1] annotations + build_runner codegen
```

```
cucumber ─────► cucumber_core ─────► cucumber_gherkin (pub.dev)
   │                 │          └──► cucumber_messages (pub.dev)
   │                 └─────────────► cucumber_expressions (pub.dev, ADR-0020)
   ├──► test (package:test)
   └──► cucumber_html_formatter, cucumber_ci_environment, cucumber_query (workspace)

cucumber_flutter ──► cucumber_core, flutter_test            (post-v1)
cucumber_builder ──► cucumber_core, build, source_gen       (post-v1)
```

**Rules:**

- **`cucumber_core` is pure Dart.**
  - It may not use `dart:io`, `dart:mirrors`, Flutter or `package:test`.
  - Hosts inject platform facts through a `Platform`-like interface: environment, clock, meta information,
    and file contents.
- **Ported shared libraries get their own packages.**
  - Each uses the name the Cucumber organisation would publish it under, with `publish_to: none`.
  - Once the upstream package is published, we swap the workspace package for the hosted one (ADR-0005).
  - The publishing order and what blocks each package are in §14.1.
- **What users depend on.** Dart users depend on `cucumber`; Flutter users will depend on `cucumber_flutter`.
  `package:cucumber/cucumber.dart` re-exports the full core API, so users never import `cucumber_core` directly.

### 3.2 Runtime pipeline

```
dart test ─► test/cucumber_test.dart: main()
  cucumber(...)  ≡  CucumberSuite(CucumberOptions(...)).declare()          [synchronous]
    1. resolve configuration     defaults < code < cucumber.yaml profile(s) < CUCUMBER_* env      (§4.9)
    2. discover features         dirs, globs, files, file:line                                     (§5.10)
    3. parse                     cucumber_gherkin → source, gherkinDocument | parseError, pickle*
    4. load glue                 validate, compile expressions, registries, ids → glue messages     (§4.5)
    5. filter + order pickles    tag expression, name regex, lines; defined | reverse | random:seed
    6. declare package:test tree
         setUpAll    → flush buffered static messages, testRunStarted, BeforeAll hooks
         group(feature) › group(rule) › group(outline) › group(examples) › test(pickle)
         tearDownAll → AfterAll hooks, testRunFinished, close outputs, merge reports           (§8.4)

test body (one per pickle)
    assemble TestCase: match steps (defined | undefined | ambiguous), attach hooks → emit testCase
    for attempt in 0..retry:
        new World → testCaseStarted → hooks/steps (status rules §5) → testCaseFinished(willBeRetried)
    report the final attempt to package:test (pass | markTestSkipped | failure)                     (§6)
```

Everything up to step 6 runs synchronously inside `main()`:

- `package:test` does await an async `main()`, but `group()` bodies must be synchronous.
- `flutter_gherkin` broke because it declared tests after an `await`.
- Parsing is synchronous, and in tests we read feature files synchronously.

### 3.3 Core components (`cucumber_core`)

| Component | Responsibility | Closest analogue |
|---|---|---|
| `SupportCodeLibrary` (glue loader) | Validate glue values; compile expressions; parameter, data-table and doc-string type registries; ordered hook lists; IDs; emit `parameterType`, `stepDefinition`, `hook` and `undefinedParameterType` | cucumber-js `SupportCodeLibraryBuilder`, cucumber-jvm `CachingGlue` |
| `SourceLoader` | Parse with injectable IDs; emit `source`, `gherkinDocument`, `pickle` and `parseError` | `@cucumber/gherkin-streams` |
| `PickleFilter`, `PickleOrder` | Tag expressions (interim evaluator, ADR-0007), names, lines; `defined`, `reverse`, `random[:seed]` | js `pickle_filter`, `order_pickles` |
| `TestCaseAssembler` | Turn a pickle into a `TestCase` message: hook steps, step matches, `stepMatchArgumentsLists` | js `assemble_test_cases` |
| `TestCaseRunner` | Attempts, World lifecycle, status rules, step-hook folding, retry, suggestions | js `test_case_runner` |
| `UserCodeRunner` | Invoke user functions in guarded zones: parameter mapping, async, timeouts, uncaught-error capture | js `user_code_runner` |
| `MessageBus` | Ordered `Envelope` delivery to plugins; buffering until the run starts | js event broadcaster |
| `SnippetGenerator` | Dart snippets via `CucumberExpressionGenerator` | js snippet builder |
| `SuitePlan` + `TestHost` | Tree of nodes that hosts declare. `SerialHost` executes a plan directly; it is used by the CCK harness and a future CLI | cucumber-jvm `CucumberExecutionContext` |
| `Plugin` | `onMessage(Envelope)`, `close()` | js formatter plugins |

`cucumber_core` has two public libraries:

- `package:cucumber_core/cucumber_core.dart`: the glue API (glue values, World, context objects, tables,
  pending/skip, plugins). `package:cucumber` re-exports it.
- `package:cucumber_core/engine.dart`: the host API (`SuitePlan`, `TestHost`, `SerialHost`, `RunOptions`,
  `FeatureSource`, filters, orders, ID schemes, `CucumberPlatform`, results). It re-exports the glue API.

---

## 4. Public API

The canonical import is `package:cucumber/cucumber.dart` (Flutter later: `package:cucumber_flutter/...`).

### 4.1 At a glance

```dart
// test/steps/belly_steps.dart
import 'package:cucumber/cucumber.dart';
import 'package:test/test.dart';

class BellyWorld extends World {          // extending World is optional (ADR-0003)
  final belly = Belly();
}

final bellyGlue = <Glue>[
  ParameterType<Color>('color', r'red|green|blue', (String s) => Color.values.byName(s)),
  DataTableType<Person>.entry((entry) => Person(entry['name']!, int.parse(entry['age']!))),

  Given('I have {int} cukes in my belly', (BellyWorld w, int cukes) => w.belly.eat(cukes)),
  Given('these people:', (BellyWorld w, List<Person> people) => w.people.addAll(people)),
  When('I wait {int} hour(s)', (BellyWorld w, int hours) async => w.belly.wait(hours)),
  Then('my belly should growl', (BellyWorld w) => expect(w.belly.isGrowling, isTrue)),
  Then('the payload is:', (DocString doc) => expect(doc.mediaType, 'application/json')),
  Then('it is not built yet', () => pending()),

  Before((BellyWorld w, Scenario s) => w.log('start ${s.name}'), tags: '@belly', name: 'reset belly'),
  After((Scenario s) { if (s.isFailed) attach(screenshot(), mediaType: 'image/png'); }),
  BeforeAll(() => server.start()),
  AfterAll(() => server.stop()),
];
```

```dart
// test/cucumber_test.dart  →  dart test
import 'package:cucumber/cucumber.dart';
import 'steps/belly_steps.dart';

void main() => cucumber(
      features: ['features/'],
      world: BellyWorld.new,
      glue: bellyGlue,
    );
```

### 4.2 Glue values (ADR-0002)

Every glue type extends the sealed class `Glue`. Glue values are **immutable, side-effect free values**. A suite
receives them as an ordered `List<Glue>`, and that order is the *definition order* used for hooks and message
emission.

When a glue value is constructed, it records its source location. It captures `StackTrace.current` and uses the
first frame outside the cucumber packages. Messages carry this as `sourceReference {uri, location.line}`.

**Steps**

```dart
Given(Object expression, Function body, {Duration? timeout})
When(Object expression, Function body, {Duration? timeout})
Then(Object expression, Function body, {Duration? timeout})
```

- **Expression type:** a `String` is a Cucumber Expression; a `RegExp` is a regular expression.
- **Keywords:** as in every Cucumber implementation, the keyword does not affect matching. It is kept for
  readability and for snippet output.
- **Body:** positional parameters in the layout `[World] expressionArgs… [multilineArgs…]` (see §4.5).

**Hooks**

```dart
Before(Function body, {String? tags, String? name, int order = 0, Duration? timeout})
After(Function body, {String? tags, String? name, int order = 0, Duration? timeout})
BeforeStep(Function body, {String? tags, String? name, int order = 0, Duration? timeout})
AfterStep(Function body, {String? tags, String? name, int order = 0, Duration? timeout})
BeforeAll(Function body, {String? name, int order = 0, Duration? timeout})
AfterAll(Function body, {String? name, int order = 0, Duration? timeout})
```

| Hook kind | Accepted bodies |
|---|---|
| Scenario hooks | `()`, `(W world)`, `(Scenario s)`, `(W world, Scenario s)` |
| Step hooks | `()`, `(W world)`, `(Step s)`, `(W world, Step s)` |
| Test-run hooks | `()`, `(TestRun run)` |

- **`tags`** is a Cucumber tag expression. It is evaluated per pickle and does not apply to test-run hooks.
- **`name`** becomes `Hook.name` in messages.
- **Ordering** (ADR-0014): hooks are stably sorted by `(order, definition index)`.
  - `Before*` and `BeforeAll` run in ascending order.
  - `After*` and `AfterAll` run in descending order.
  - So by default, after-hooks run in reverse definition order, matching cucumber-js and the CCK.

**Parameter types** (ADR-0015)

```dart
ParameterType<T>(String name, Object regexp, Function transformer,
    {bool useForSnippets = true, bool preferForRegexpMatch = false})
```

- `regexp` is a `String`, a `RegExp`, or a `List` of either. The `i` and `m` flags are rejected.
- The transformer is checked when the glue loads:
  - It takes **one `String` parameter per capture group**, or a single `String` when the regexp has no groups.
    Groups that do not participate are passed as `null`.
  - It may take a **World as its first parameter**.
  - It may return **`FutureOr<T>`**, which is awaited before the step runs.

```dart
ParameterType<Airport>('airport', r'[A-Z]{3}', (String code) => Airport(code)),
ParameterType<Flight>('flight', r'([A-Z]{3})-([A-Z]{3})', (String from, String to) => Flight(from, to)),
ParameterType<User>('user', r'"([^"]*)"', (ShopWorld w, String name) => w.users.byName(name)),
```

**Data table and doc string types** (ADR-0011)

These have fixed shapes, so they are statically typed rather than checked when the glue loads.

```dart
DataTableType<T>.entry(T Function(Map<String, String> entry), {String? replaceWithEmptyString})
DataTableType<T>.row(T Function(List<String> row), {String? replaceWithEmptyString})
DataTableType<T>.cell(T Function(String cell), {String? replaceWithEmptyString})
DataTableType<T>.table(T Function(DataTable table))
DocStringType<T>(T Function(String content), {String? contentType})
```

### 4.3 World (ADR-0003)

```dart
abstract mixin class World {
  Map<String, Object?> get parameters;     // world parameters; deep copy per attempt
  Scenario get scenario;                   // the scenario currently running
  void attach(Object data, {String? mediaType, String? fileName});
  void log(String text);
  void link(String url, {String? title});
}
```

- **Creation and type:**
  - The suite option `world: W Function()` is called once per **test-case attempt**, before the first `Before`
    hook. Each retry gets a fresh World.
  - When `world` is omitted, a plain `World` instance is used.
  - Any class may be the World. Extending or mixing in `World` is optional and only adds the convenience members.
- **Lifetime of the members:** World members resolve the active scenario through a zone value. They work inside
  that scenario's steps, hooks and transformers, including across `await`s. Anywhere else they throw `StateError`.
- **Top-level functions:** `attach()`, `log()` and `link()` do the same as the World methods and work anywhere in
  scenario or test-run context, including in helpers.
  - Known trade-off: the top-level `log` clashes with `dart:math`'s `log`. Users import
    `dart:math hide log` or use a prefix (§15).
- *(Proposed)* `World` declares a no-op `FutureOr<void> dispose()`. The runner calls it after the last `After`
  hook, which gives resource cleanup without an extra hook.

### 4.4 Scenario, Step, TestRun

```dart
abstract interface class Scenario {
  String get id;            // pickle id
  String get name;
  String get uri;           // feature file, relative to the package root
  int get line;             // Pickle.location.line (example row for outlines)
  List<String> get tags;    // inherited tags included, with '@'
  String get language;
  int get attempt;          // 0-based
  Status get status;        // most severe so far (meaningful in After hooks)
  bool get isFailed;
  Object? get error;        // error of the first failed step/hook, if any
  void attach(Object data, {String? mediaType, String? fileName});
  void log(String text);
  void link(String url, {String? title});
}

abstract interface class Step {
  Scenario get scenario;
  String get text; String get keyword; int get line;
  Status get status; Object? get error;   // meaningful in AfterStep
}

abstract interface class TestRun {
  Map<String, Object?> get parameters;    // mutable in BeforeAll (cucumber-js semantics)
  void attach(Object data, {String? mediaType, String? fileName});
  void log(String text);
  void link(String url, {String? title});
}

enum Status { unknown, passed, skipped, pending, undefined, ambiguous, failed }   // ordered by severity
```

### 4.5 How step parameters are mapped and checked

Dart has no mirrors on Flutter or AOT, but generics are reified at runtime. That lets us check function shapes
without codegen:

- `f is Function(Never, Never)` tells us that `f` takes exactly two positional parameters.
- `f is Function(T, Never)` tells us that the first parameter accepts `T`.

The checking helper is generated code for arities up to a fixed bound (initially 12).

1. **When the glue loads,** we determine:
   - the body's arity `k`;
   - the expression's parameter types `P1..Pn`:
     - for a Cucumber Expression, its parameter nodes;
     - for a regex, its top-level capture groups. These are typed by the parameter type whose regexp matches the
       group (e.g. `(\d+)` → `int`), otherwise `String`.
2. **Valid layouts** are `[W] P1..Pn [M1 [M2]]`, where `M` are the step's multiline arguments (data table and/or
   doc string) in Gherkin `argumentIndex` order.
3. **Resolving the World parameter.** Whether a pickle step carries `m` multiline arguments is only known when it
   runs, so the layout is resolved then:
   - `k == n + m` means there is no World parameter;
   - `k == n + m + 1` means the World comes first;
   - anything else fails the step with an arity message, as in js and jvm.
   - When the glue loads, any `k` outside `n..n+3` is a definition error.
4. **Type checks:**
   - A World parameter must accept `W`.
   - Each `Pi` must accept its parameter type's `T`.
   - These run when the glue loads wherever possible, otherwise at execution. Errors name the definition's source
     location.
5. **Multiline argument conversion.** The first conversion that the parameter accepts wins.
   - **Data table:**
     1. `DataTable` is passed as-is.
     2. `List<List<String>>` receives the raw cells.
     3. Registered conversions:
        - `List<T>` uses an entry or row type, or a cell type when the table has one column.
        - `List<List<T>>` uses a cell type.
        - `T` uses a table type.
        - `Map`/`List<Map>` of the built-in cell types.
   - **Doc string:**
     1. `DocString` is passed as-is.
     2. `String` receives the content.
     3. A `DocStringType<T>` matching the content type is used, otherwise the unique `DocStringType<T>` for that `T`.
6. **Return values** are ignored, and `Future`s are awaited.

**Errors when the glue loads** are thrown from `cucumber()`, so `dart test` reports a load failure for that file.
They include:

- invalid expressions;
- duplicate parameter type names;
- invalid hook tag expressions;
- impossible arities;
- type mismatches.

**Undefined parameter types are not load errors.** As in cucumber-js and the CCK, they emit
`undefinedParameterType`, the definition is dropped, and the steps that would have used it become UNDEFINED.

### 4.6 DataTable and DocString (ADR-0011)

```dart
final class DataTable {
  DataTable(List<List<String>> rows);              // public: user-built tables compare by value (CCK)
  List<List<String>> get raw;
  int get width; int get height; bool get isEmpty;
  String cell(int row, int column);
  List<String> row(int index); List<String> column(int index);
  DataTable rows(int from, [int? to]); DataTable columns(int from, [int? to]);
  DataTable transpose();
  List<T> asList<T>();                             // untyped call → List<String> of all cells
  List<List<T>> asLists<T>();
  List<Map<K, V>> asMaps<K, V>();                  // header row → keys
  Map<K, V> asMap<K, V>();                         // first column → keys
  T convert<T>();                                  // table transformer
  void diff(Object expected);                      // throws TableDiffException
}

final class DocString {
  DocString(this.content, {this.mediaType});
  final String content; final String? mediaType;
  T convert<T>();
}
```

The semantics follow cucumber-jvm's `datatable` module, adapted to Dart:

- **Calls without type arguments** return strings.
- **Empty cells.** `raw` keeps empty cells as `''`. Typed conversion to a nullable type maps `''` to `null`.
- **Empty-string marker.** `replaceWithEmptyString` (e.g. `'[blank]'`) turns that marker into `''`.
- **Built-in cell types:** `String`, `int`, `double`, `num`, `bool`, `BigInt`.
- **Where conversions come from.** Tables passed to steps carry the suite's converter. Tables a user builds can
  only convert to the built-in types.

### 4.7 Pending, skipped and failed (ADR-0008)

```dart
class PendingException implements Exception { PendingException([String message = 'TODO: implement me']); }
class SkippedException implements Exception { SkippedException([String? reason]); }
Never pending([String message = 'TODO: implement me']);   // throws PendingException
Never skip([String? reason]);                             // throws SkippedException
```

Any other thrown object, including `TestFailure` from `expect`, means FAILED:

- `exception.type` is the runtime type name;
- `message` is `toString()`;
- the stack trace is filtered (§7.6).

### 4.8 Suite entrypoint (ADR-0012)

```dart
void cucumber<W extends Object>({
  required List<Glue> glue,
  W Function()? world,
  List<String>? features,             // default: ['features/']
  String? tags,                       // Cucumber tag expression
  List<String>? names,                // regexes on pickle names
  int? retry,                         // extra attempts for FAILED test cases
  String? order,                      // 'defined' | 'reverse' | 'random' | 'random:<seed>'
  bool? dryRun,
  Map<String, Object?>? worldParameters,
  List<Object>? plugins,              // 'message:<path>' | 'html:<path>' | 'summary' | Plugin instances
  String? suiteName,                  // names this suite's report part (default: the test file name)
  String? profile,                    // cucumber.yaml profile(s), comma separated
  bool? mapTags,                      // Gherkin tags → package:test tags (default: true)
  Timeout? scenarioTimeout,
});

final class CucumberOptions { /* same fields; CucumberOptions merge(CucumberOptions other) */ }
final class CucumberSuite<W extends Object> {
  CucumberSuite(CucumberOptions options);
  void declare();
}
```

`cucumber(...)` is a convenience wrapper around `CucumberSuite(CucumberOptions(...)).declare()`. An options value can
be shared and refined across several entry files.

### 4.9 Configuration (ADR-0010)

Sources are merged with this precedence (later sources win):

> built-in defaults < code (`CucumberOptions`) < `cucumber.yaml` profile(s) < `CUCUMBER_*` environment variables

`glue` and `world` can only be set in code.

*(Proposed)* merge rules:
- Scalars override.
- `tags` are combined with `and`, so higher-precedence sources can only narrow the selection.
- Lists are replaced.

```yaml
# cucumber.yaml (package root)
default:
  features: [features/]
  tags: not @wip
  plugins:
    - message:build/cucumber/messages.ndjson
    - html:build/cucumber/report.html
    - summary
ci:
  tags: not @wip and not @manual
  retry: 1
```

| Environment variable | Meaning |
|---|---|
| `CUCUMBER_PROFILE` | Profile(s) to apply, comma separated (default: `default` if present) |
| `CUCUMBER_FEATURES` | Feature paths, comma separated; `path:line` supported |
| `CUCUMBER_FILTER_TAGS` | Tag expression (AND-ed with other sources) |
| `CUCUMBER_FILTER_NAME` | Regex on pickle names |
| `CUCUMBER_PLUGIN` | Plugins, comma separated |
| `CUCUMBER_EXECUTION_DRY_RUN` | `true` / `false` |
| `CUCUMBER_EXECUTION_ORDER` | `defined` / `reverse` / `random[:seed]` |
| `CUCUMBER_EXECUTION_RETRY` | Integer |
| `CUCUMBER_WORLD_PARAMETERS` | JSON object |
| `CUCUMBER_RUN_ID` | Correlates report parts across isolates or machines (§8.4) |

The names follow cucumber-jvm's property naming (`cucumber.filter.tags` → `CUCUMBER_FILTER_TAGS`). Flutter devices
cannot read the environment, so `cucumber_flutter` will read the same keys from `--dart-define`.

---

## 5. Execution semantics (ADR-0017)

These rules follow the CCK reference implementation (fake-cucumber) and the current direction of cucumber-js,
cucumber-jvm and cucumber-ruby.

### 5.1 Status

- Severity order: `UNKNOWN < PASSED < SKIPPED < PENDING < UNDEFINED < AMBIGUOUS < FAILED`.
- A test case's status is the most severe status of any of its steps, hook steps included.

### 5.2 Test case composition

`testSteps` is built in this order:

1. `Before` hooks whose tags match, in ascending order;
2. the pickle steps;
3. `After` hooks whose tags match, in descending order.

Each pickle step is matched against every step definition:

| Matches | Step result | `stepDefinitionIds` / `stepMatchArgumentsLists` |
|---|---|---|
| 0 | UNDEFINED | both empty |
| 1 | defined | one entry each |
| >1 | AMBIGUOUS | every candidate's id and arguments |

`BeforeStep`/`AfterStep` are not test steps. Their results are folded into the pickle step's result (worst status,
summed duration), and their attachments carry the step's id (cucumber-js behaviour).

### 5.3 Step execution rules

The rules below are applied in order, and the first one that matches decides the step's outcome:

1. **After an explicit skip** (a SKIPPED result with no failed-ish result before it), every later step and
   `Before` hook is SKIPPED. No suggestions are emitted, even for undefined steps.
2. **Ambiguous** gives AMBIGUOUS with a zero duration. **Undefined** emits a `suggestion`, then gives UNDEFINED.
   Both apply even after a failure.
3. **After a failed-ish result** (PENDING, UNDEFINED, AMBIGUOUS or FAILED), the step is SKIPPED with a zero duration.
4. **Otherwise the step executes**, running `BeforeStep` hooks, then the step, then `AfterStep` hooks:

| Step outcome | Result |
|---|---|
| Returns normally | PASSED |
| Throws `PendingException` | PENDING |
| Throws `SkippedException` | SKIPPED |
| Throws anything else | FAILED |

`After` hooks always execute, except in dry run.

### 5.4 Hook semantics

- **`Before` fails or is skipped:** later `Before` hooks and all steps are SKIPPED, but `After` hooks still run.
- **`After` fails:** the test case fails.
- **`BeforeAll`:**
  - All of them run, even after one fails.
  - If any failed, **no test case runs**.
  - Every `AfterAll` still runs and the run fails.
  - Each emits `testRunHookStarted` and `testRunHookFinished`.
  - Attachments made in them carry `testRunHookStartedId`.
- **`AfterAll`:** all run in descending order, even after failures.

### 5.5 Retry

- Only a test case whose worst status is **FAILED** is retried. AMBIGUOUS, UNDEFINED and PENDING are never retried
  (CCK `retry-*`).
- `retry: N` allows N+1 attempts.
- Each attempt:
  - creates a new World;
  - emits a new `testCaseStarted` with the same `testCaseId` and `attempt` = 0, 1, …;
  - carries `willBeRetried` on its `testCaseFinished`.
- Only the final attempt counts.

### 5.6 Dry run

- Test-run hooks are reported as SKIPPED (`testRunHookStarted` and `testRunHookFinished` are still emitted).
- Scenario hooks and defined steps are SKIPPED; undefined and ambiguous steps keep those statuses.
- No user code runs, but the World factory is called.
- *(Proposed)* As in cucumber-jvm and cucumber-ruby, a dry run fails when steps are undefined or ambiguous. That
  makes "are all steps implemented?" a useful CI check.

### 5.7 Run success (strict only)

The run fails if a **final** attempt ended PENDING, UNDEFINED, AMBIGUOUS or FAILED, or if any test-run hook failed.
SKIPPED counts as success. There is no non-strict mode: cucumber-jvm v7 and cucumber-ruby's main branch both
removed it.

### 5.8 Timeouts and uncaught errors

- **Per-definition `timeout`:** there is none by default. When one is exceeded, the step fails with a
  `TimeoutException`.
- **Scenario timeout:** the `package:test` timeout for each scenario test is
  `scenarioTimeout × (retry + 1)` *(Proposed)*.
- **Uncaught errors:** user code runs in a guarded zone, so an uncaught asynchronous error fails the step that is
  currently running. Errors that arrive after it finished are attached to the scenario.

### 5.9 Errors outside steps

| Error | Handling |
|---|---|
| Gherkin parse error | `parseError` message. A failing test named after the file is declared so the run fails visibly. |
| Glue definition error | Thrown from `cucumber()`, so `dart test` reports a load failure for that file. |
| Internal error during the run | `testRunFinished {success: false, exception}` |

### 5.10 Discovery, filtering and ordering

- **Feature locations:** directories (recursively `*.feature`), globs, files, and `file:line[:line]`.
  - A line in a scenario selects that scenario.
  - A line on an Examples row selects that row (cucumber-js line semantics).
- **Filters:** Cucumber tag expressions, name regexes and lines are applied **before declaration**, so filtered
  pickles are never declared. They are still emitted as `pickle` messages, as cucumber-js does.
- **Order:** `defined` (default), `reverse`, or `random[:seed]`. Random ordering prints its seed, as cucumber-js
  does.

---

## 6. Mapping to `package:test` (ADR-0013)

### Tree and names

- **Groups:**
  - `group(feature)`
  - `group(rule)`
  - `group(scenario outline)`
  - `group(examples)`
- **Tests:** `test(scenario)` or `test(example row)`.
- **Naming** follows cucumber-jvm's "short" strategy: a node's name, or its keyword when it has no name.
- **Example rows** are named `Example #<examples>.<row>`. When the pickle name differs from the outline name
  (parameterised titles), `: <pickle name>` is appended (cucumber-jvm `number-and-pickle-if-parameterized`).

### Locations

Each group and test gets a `TestLocation(featureFileUri, line, column)`. The JSON reporter exposes it, so IDEs jump
straight to the `.feature` line.

Flutter 3.44's `flutter_test` wrappers do not forward `location`, so that needs an upstream Flutter change (§12).

### Tags

- Gherkin tags become `package:test` tags with the `@` removed. Then `dart test --tags smoke` and `dart_test.yaml`
  tag configuration work.
- `package:test` **throws** for tags that are not hyphenated identifiers (`[a-zA-Z_-][a-zA-Z0-9_-]*`). Such tags
  (e.g. `@issue:123`) are not mapped; they still work in Cucumber tag expressions.
- `package:test` warns about tags not declared in `dart_test.yaml`. This is documented, and `mapTags: false` turns
  the mapping off.

### Outcomes

| Final status | What `package:test` sees |
|---|---|
| PASSED | The test passes |
| SKIPPED | `markTestSkipped(reason)` |
| PENDING / UNDEFINED / AMBIGUOUS | A `TestFailure` explaining the cause. Undefined steps include ready-to-paste Dart snippets |
| FAILED | The original error is rethrown with its original stack trace (`Error.throwWithStackTrace`), after the Cucumber context (failed step, `feature:line`) has been printed with `printOnFailure` |

### Retry

Retries happen inside the test body (§5.5). `package:test`'s own `retry:` is not used, for two reasons:

- it would also retry pending and undefined scenarios;
- it cannot set `willBeRetried`.

### Filtering by `package:test`

`--name`, `--plain-name`, `--tags` and shards can stop tests from running. Those tests then never emit messages:
`testCase` is emitted lazily, just before the first `testCaseStarted`. As a result, reports only contain what
actually ran.

### Run-level messages

`setUpAll` and `tearDownAll` only run when at least one test in the suite runs. Static messages are buffered until
`setUpAll`, so an entry file that is filtered out completely writes nothing.

---

## 7. Messages

### 7.1 Emission order (serial, per suite)

```
meta
per feature file, in discovery order:  source, gherkinDocument | parseError*, pickle*
(parameterType | stepDefinition | hook)* in definition order, then undefinedParameterType*
testRunStarted
(testRunHookStarted, attachment*, testRunHookFinished)*     BeforeAll, ascending
per executed test case (declaration order, lazily):
  testCase                                                  emitted once, before the first attempt
  per attempt: testCaseStarted, (testStepStarted, attachment*, suggestion?, testStepFinished)*, testCaseFinished
(testRunHookStarted, attachment*, testRunHookFinished)*     AfterAll, descending
testRunFinished
```

This differs from the CCK reference in one way. The reference emits every `testCase` right after the `BeforeAll`
hooks. We emit each `testCase` just before its first `testCaseStarted`, for two reasons:

- the CCK's partial-order rules allow it, and cucumber-ruby does the same;
- `package:test` may skip tests that we cannot predict at declaration time.

### 7.2 IDs (ADR-0018, Proposed)

- **Static messages** (Gherkin AST, pickles, glue) get **deterministic** IDs:
  - Feature files use `<fnv64(uri)>-<n>`, with a counter per file.
  - Glue uses a hash of its source reference and pattern, plus its definition index.
  - The same feature file or glue parsed in several isolates therefore gets the same IDs, which lets the report
    merge de-duplicate them (§8.4).
- **Dynamic messages** (test run, test cases, test steps, starts) get UUID v4s.
- An incrementing generator is used for the CCK and for deterministic tests.

### 7.3 Meta

`meta` contains:

| Field | Value |
|---|---|
| `protocolVersion` | The `cucumber_messages` version we build against |
| `implementation` | `cucumber-dart` and its version |
| `runtime` | `Dart` and `Platform.version` |
| `os` | Operating system and version |
| `cpu` | ABI |
| `ci` | Detected from the environment by `cucumber_ci_environment`; absent outside CI |

The host supplies these values; the core stays pure. It also supplies the clock: the `dart test` host's is the
wall-clock time when the suite is declared plus a running `Stopwatch`, so timestamps are monotonic with microsecond
resolution. (`DateTime.now()` can be as coarse as 15 ms on Windows, which gave quick scenarios equal timestamps, and
`cucumber_query` orders test cases by timestamp, then by ID.)

### 7.4 Attachments

| Input | Encoding | Default media type |
|---|---|---|
| `String` | `IDENTITY` | `text/plain` |
| `List<int>` / `Uint8List` | `BASE64` | `application/octet-stream` |
| `log(text)` | `IDENTITY` | `text/x.cucumber.log+plain` |
| `link(url, title:)` | `IDENTITY` | `text/uri-list`; the title is stored in `fileName` |

- Every attachment gets a `timestamp`.
- Inside a scenario it is linked through `testCaseStartedId` and `testStepId`.
- Inside a test-run hook it is linked through `testRunHookStartedId`.
- The deprecated `Attachment.url`, `Attachment.source` and `Attachment.testRunStartedId` are never set.
- The `cucumber` host adds `attachFile(path, {mediaType, fileName})`.
- `externalAttachment` (for large files) will come after v1.

### 7.5 Suggestions and snippets

Each UNDEFINED step emits `suggestion {pickleStepId, snippets[{language: 'dart', code}]}` between its
`testStepStarted` and `testStepFinished`.

- **Expressions:** `CucumberExpressionGenerator` produces the candidate expressions.
  - In the `suggestion` message, each expression becomes its own `Snippet`, as fake-cucumber and the CCK expect.
  - In output for people (`TestCaseResult.snippets`, used by hosts), the first becomes code and the rest are added
    as comments.
- **Keyword:** taken from `PickleStep.type`:

| `PickleStep.type` | Keyword |
|---|---|
| Context | `Given` |
| Action | `When` |
| Outcome | `Then` |
| Unknown | `Given` |

- **Parameters:**
  - A data table or doc string adds a trailing `DataTable dataTable` / `DocString docString`.
  - When the suite has a World type, it is included as the first parameter.

```dart
Given('I have {int} cukes in my belly', (BellyWorld world, int int1) {
  // Write code here that turns the phrase above into concrete actions
  throw PendingException();
}),
```

### 7.6 Error details

For a failed step, `testStepResult` contains:

- `message`: the error's `toString()` plus its filtered stack trace;
- `exception {type, message, stackTrace}`.

Frames from inside the cucumber packages are removed. *(Proposed)* A final `<feature uri>:<line>` frame is
appended, as fake-cucumber and cucumber-jvm do, so traces end at the Gherkin step.

---

## 8. Outputs, plugins and report merging

### 8.1 Plugin API

```dart
abstract interface class Plugin {
  void onMessage(Envelope envelope);
  FutureOr<void> close();
}
```

- **Built-in plugin specifications** (usable from code, YAML or the environment):
  - `message:<path>`: NDJSON
  - `html:<path>`
  - `summary`: console
- **Custom plugins** are passed as instances in code. Dart cannot load classes by name, so only registered names can
  be used in YAML or the environment.

### 8.2 v1 outputs (ADR-0009)

- **NDJSON (`message`):** the canonical stream (`cucumber_messages` `envelopeToJsonString`).
- **HTML (`html`):** `cucumber_html_formatter`.
  - It embeds the prebuilt assets of `@cucumber/html-formatter` (`index.mustache`, `main.js`, `main.css`,
    `icon.url`, `main.js.LICENSE.txt`). They are pinned and synced from npm, and compiled into Dart constants (§9).
  - `MessagesToHtmlWriter` streams the messages as JSON with `<` escaped as `\x3C`, which is what the Java, Ruby
    and .NET wrappers do: the template head, then the comma-separated messages as the elements of
    `window.CUCUMBER_MESSAGES`, then the tail.
  - `HtmlPlugin` (`html:<path>`, relative to the package root as for `message:`) creates the file when the first
    message arrives, so a suite that never starts its run writes nothing, and completes the report when it is
    closed.
- **`message:` and `html:` under `dart test`** are merged reports: the suite writes a report part, and its
  `tearDownAll` rewrites the files from the parts of every suite of the run that configures them (§8.4).
  `NdjsonPlugin` and `HtmlPlugin` instances passed in code write only their suite's messages.
- **Summary and snippets (`summary`):** printed when the suite ends (from `tearDownAll`, so the test reporter
  shows it). It follows cucumber-js's summary formatter, in this order:
  - undefined parameter types;
  - `Failures:` everything that fails the run (§5.7): final attempts that ended FAILED, AMBIGUOUS, UNDEFINED or
    PENDING, and failed `BeforeAll`/`AfterAll` hooks. cucumber-js lists PENDING as a warning; we are strict-only;
  - `Warnings:` the other non-passing scenarios: attempts that will be retried (`(attempt 1, retried)`) and final
    attempts that ended SKIPPED;
  - each listed scenario has its long `cucumber_query` name, its `uri:line`, its steps with their statuses and the
    messages of non-passing ones, and its non-passing hooks;
  - `5 scenarios (1 failed, 1 undefined, 3 passed)` and `23 steps (…)`: final attempts only, pickle steps only
    (not hooks), statuses from the most to the least severe;
  - `0m01.234s (executing steps: 0m00.567s)`: the run, then the sum of all step durations;
  - `You can implement missing steps with the snippets below:` (cucumber-jvm's wording) and the de-duplicated
    Dart snippets, taken from the `suggestion` messages and presented as in §7.5.

  `formatSummary(Query)` (and `formatSummaryOf(envelopes)`) is a pure function of the messages, built on
  `cucumber_query`, so the merge CLI can reuse it on a merged stream (§8.4). Under `dart test`, each suite prints
  the summary of its own messages (§8.4). A suite that never starts its run prints nothing.

### 8.3 Later outputs

The following are planned after v1:

- JUnit XML (port of `junit-xml-formatter`, needs `cucumber_query`)
- legacy Cucumber JSON
- pretty and progress console output (port of `pretty-formatter`)
- rerun files
- usage reports
- publishing to reports.cucumber.io

### 8.4 Report merging (ADR-0016)

`dart test` runs each entry file in its own isolate, so a run can produce several message streams.

1. **Parts.** Each suite that has a `message:` or `html:` output writes its NDJSON part to
   `<outputDir>/.cucumber/parts/<runId>/<suiteId>.ndjson`, next to a manifest, `<suiteId>.json`, that lists the
   suite's outputs.
   - `outputDir` is `<packageRoot>/build`.
   - `runId` is `CUCUMBER_RUN_ID` if set. Otherwise it is the process id, which all isolates started by one
     `dart test` invocation share.
   - `suiteId` is the `suiteName` if set. Otherwise it is the test file's path relative to `test/`, without
     `.dart` (`test/checkout/cart_test.dart` → `checkout/cart_test`), found from the `main` on the stack when the
     suite is declared. If another suite of the run already has the ID (several suites in one file, or the same
     `suiteName` twice), the part takes the first free `<suiteId>#2`, `<suiteId>#3`, … The part file is created
     exclusively, so this also holds across isolates.
   - IDs become file names by percent-encoding everything except ASCII letters, digits, `-`, `_` and
     (not leading) `.`, so `checkout/cart_test` is stored as `checkout%2Fcart_test.ndjson`.
   - The part and its manifest are created when the first message arrives.
2. **Automatic merge.** In `tearDownAll`, after closing its part (as the last plugin to close), the suite:
   1. takes an exclusive lock on `<outputDir>/.cucumber/merge.lock`;
   2. merges the parts of the same `runId`;
   3. rewrites the configured `message:` and `html:` outputs from the merged stream;
   4. releases the lock.

   The last isolate to finish leaves the complete report.
   - **Each output is merged from the suites that configure it.** An output is rewritten from the parts whose
     manifest lists it, in suite ID order. Suites that share `cucumber.yaml`'s outputs (the usual case) therefore
     share one report, while a suite with its own output file (such as each CCK sample, or the `BeforeAll` suite
     of `fixtures/e2e`) keeps its own report.
   - During the run, the outputs are only written by the merge, under the lock, so isolates never write the same
     file at the same time. Outputs are written to a temporary file and renamed, so readers never see a partial
     report.
   - A part that is still being written (another suite has not finished yet) is merged up to its last complete
     line, and counts as unfinished. That suite rewrites the outputs again when it finishes.
   - **The lock.** On Linux and macOS, file locks belong to the process, so `RandomAccessFile.lock` alone does not
     exclude the isolates of one `dart test` process. The isolates of a process first take turns through a guard
     file, `merge.lock.<pid>`, created exclusively and deleted on release (a guard older than two minutes, left by
     an isolate that died while merging, is taken over). The guard holder then takes an exclusive
     `RandomAccessFile.lock` on `merge.lock`, which excludes other processes and is released by the operating
     system if the process dies.
3. **Merge algorithm** (`mergeReportParts`, a pure function exported by `package:cucumber`).
   - One `meta`: the first part's.
   - Static messages are de-duplicated (§7.2): `source` and `gherkinDocument` by URI; `pickle`, `stepDefinition`,
     `hook` and `parameterType` by ID; `parseError` and `undefinedParameterType` by content.
   - One synthetic `testRunStarted`, with the minimum timestamp and the first part's ID.
   - One `testRunFinished` (if at least one part finished), with the maximum timestamp. `success` is true only if
     every part finished and succeeded. Its `message` names the parts that did not finish and carries the parts'
     own messages (prefixed with their suite IDs when there are several parts); its `exception` is the first part's.
   - All `testRunStartedId` references are remapped to the synthetic run.
   - `workerId` is set to the suite id on `testCaseStarted` and `testRunHookStarted`. This mirrors cucumber-js's
     parallel workers, which also run `BeforeAll` once per worker.
   - Dynamic IDs are kept unless an earlier part or a static message already uses them (as with incrementing
     IDs); such an ID becomes `<suiteId>/<id>` and every reference in its part follows.
   - **Order** (§7.1): `meta`, the Gherkin messages of every part, the glue messages of every part,
     `testRunStarted`, the dynamic messages of each part one part after the other (unfinished parts last), and
     `testRunFinished`.
4. **Summary: per suite.** Each suite prints the summary of its own messages in its `tearDownAll`, as before. A
   merged summary would repeat the earlier suites' results in every later suite's output, and its content would
   depend on which isolates happen to have finished, since no isolate knows whether it is the last one. The
   merged NDJSON and HTML reports have the complete picture, and the merge CLI prints a merged summary
   (`formatSummary` is a pure function of the messages).
5. **Suites that never start.** A suite whose tests are all filtered out never runs `setUpAll`/`tearDownAll`
   (§6), so it writes no part, takes no lock and rewrites nothing. Its scenarios are not in the merged report;
   the outputs are left as the other suites of the run merged them. If no suite of the run starts, the outputs
   are not written at all (any report from an earlier run stays).
6. **CLI.** `dart run cucumber:merge [options] <input>...` merges parts collected from CI shards on several
   machines (`bin/merge.dart` is a thin wrapper around `runMergeCommand` in `lib/src/merge_command.dart`; parsing,
   finding and reading parts are separate functions).
   - **Inputs**: part directories (the `*.ndjson` files directly in them, such as `build/.cucumber/parts/<runId>/`),
     `.ndjson` part files, and globs of them (expanded by the CLI, so they also work in shells that do not expand
     them, such as PowerShell). A directory without parts is an error, which names its subdirectories (passing
     `build/.cucumber/parts/` instead of a run directory is the usual mistake). A file given twice is read once.
   - **Suite IDs**: the part's manifest's `suiteId` if it has one, otherwise its file name, percent-decoded, without
     `.ndjson`.
   - **Order**: the inputs in the order given; the parts of a directory by suite ID (as the automatic merge does, so
     merging a run directory reproduces the automatic merge), and the matches of a glob by path.
   - **Repeated suite IDs.** Shards usually run the same suites (`dart test --shard-index` splits the tests of every
     file), and `mergeReportParts` rejects duplicate IDs. In the merge order, the first part keeps its ID and each
     later one gets the first `<suiteId>#2`, `<suiteId>#3`, … that no other input uses, as within a run (item 1).
     Directory names cannot be used: with `CUCUMBER_RUN_ID` set from the CI run, every shard's run directory has
     the same name. Each renaming is reported on stderr (`Note: …`).
   - **Outputs**: `-p`/`--plugin`, repeatable, with the plugin specifications of §8.1: `message:<path>` and
     `html:<path>` (relative to the current directory, written through a temporary file as in item 2) and `summary`
     (`formatSummary` of the merged stream, on stdout). Without `--plugin`, the summary is printed.
   - Parts without any complete line are skipped with a warning, and an incomplete last line is left out (the part
     then counts as unfinished, item 3).
   - **Exit code**: 0 if the merged `testRunFinished` succeeded; 1 if it failed or no part finished (with a
     warning); 2 for a usage error (invalid arguments, a missing input, a file that is not an `.ndjson` part, a
     line that is not a Cucumber Messages envelope, or an output that cannot be written), printed on stderr as
     `Error: …` with a pointer to `--help`.
7. **Cleanup.** After the automatic merge, still holding the lock, the suite deletes the part directories of other
   runs below `build/.cucumber/parts/` that have not been modified for **an hour** (`pruneReportParts`).
   - A run's last modification is the latest modification time of the entries of its directory (or of the
     directory itself while it is empty, so a run that has just created it is kept). Suites write their parts as
     they run, so a run in progress (in another `dart test` process) keeps changing and is never deleted; the
     current run is never deleted at all.
   - An hour keeps every run that may still be in progress (no message for an hour means no step started or
     finished) while bounding the parts to roughly an hour of runs. Keeping the last N runs instead would not
     protect a long run in progress from many short ones.
   - Pruning never fails a suite: a run directory that cannot be inspected or deleted (on Windows, a file still
     open) is left, possibly in part, for a later suite. Symbolic links are not followed.

---

## 9. Ported shared libraries (ADR-0005)

| Package | Upstream | v1? | Shared test data used for conformance |
|---|---|---|---|
| interim tag expressions (private, in `cucumber_core`) | cucumber/tag-expressions | yes | `parsing.yml`, `evaluations.yml`, `errors.yml` |
| `cucumber_compatibility_kit` | cucumber/compatibility-kit | yes | npm `@cucumber/compatibility-kit` 31.0.0 |
| `cucumber_html_formatter` | cucumber/html-formatter | yes | Prebuilt assets of npm `@cucumber/html-formatter` 24.2.0; writer tests and a smoke test on every CCK sample's messages |
| `cucumber_ci_environment` | cucumber/ci-environment | yes | `testdata/src/*.txt(.json)` and `CiEnvironments.json`, v15.0.0 |
| `cucumber_query` | cucumber/query | yes (summary, merge) | `testdata/src/*.results.json` and `*.naming-strategy.*.txt`, v16.1.1 API, test data from `main` @ `08bf6f0` (CCK 31) |
| `cucumber_junit_xml_formatter` | cucumber/junit-xml-formatter | later | `testdata/src/*.xml` |
| `cucumber_pretty_formatter` | cucumber/pretty-formatter | later | `testdata/src/*` |

Each port follows the upstream API and its language-neutral test data, so contributing it upstream is a move rather
than a rewrite.

- **Sync.** Each port's `tool/sync.dart` downloads the GitHub source archive of a pinned upstream commit and checks
  a SHA-256 digest of the files it uses (archives are not guaranteed to be byte-stable, so the digest covers the
  extracted files). It writes them byte-for-byte to `testdata/` (and, for `cucumber_ci_environment`,
  `CiEnvironments.json` into `lib/src/ci_environments.g.dart`). `.gitattributes` marks them `-text`, and CI runs
  `tool/sync.dart --check`.
  - `cucumber_html_formatter` has no test data: its `tool/sync.dart` downloads the pinned npm tarball, verifies its
    published SHA-512 `dist.integrity` (npm tarballs are byte-stable), and generates `lib/src/assets.g.dart`.
    That file holds `index.mustache`, `main.js`, `main.js.LICENSE.txt`, `main.css` and `icon.url` as Dart string
    literals, with `\`, `$`, carriage returns and the bidirectional formatting characters of `main.js` escaped, plus
    the SHA-256 of each asset, so a test checks that the embedding is lossless. The sync also checks that the
    template has every placeholder once, in order.
- **Conformance.** `cucumber_ci_environment` runs every `testdata/src/*.txt` environment. `cucumber_query` runs the
  41 queries of upstream `QueryAcceptanceTest.java` and the 5 naming strategies on every sample that has expected
  results. `cucumber_html_formatter` checks the exact output against the template, the escaping of `<`, an empty run,
  and, for every CCK sample, that the report differs from an empty run's only by the messages, which are all
  embedded, in order, and equal to the sample's.
- **Where implementations differ.** `cucumber_query` follows the JavaScript API (`Query.update(envelope)`; methods
  that accept several kinds of message take an `Object`), but returns `null` rather than throwing for missing
  references, as Java does. `cucumber_ci_environment` follows JavaScript, but falls back to `GITHUB_SHA` when a
  GitHub pull request event cannot be read, as Java does. `cucumber_html_formatter` follows Java's
  `MessagesToHtmlWriter`: `write(envelope)` writes the template head with the first message, `close()` writes the
  tail (and the head of an empty run), and writing after `close()` throws. The builder becomes named parameters
  (`title`, `icon`, `css`, `customCss`, `script`, `customScript`), and the writer writes to a `StringSink` that its
  owner closes. Messages are separated by `,` as in Java and JavaScript (Ruby writes `,\n`).

---

## 10. Compatibility kit plan (ADR-0019, Proposed)

- **Samples.**
  - `packages/cucumber_compatibility_kit/features/` is synced byte-for-byte from the pinned npm tarball by
    `tool/sync.dart`, which verifies the SHA-512 integrity.
  - `.gitattributes` marks the samples `-text`, so Windows checkouts keep LF.
  - CI runs `tool/sync.dart --check` to catch drift.
- **Harness.**
  - Each sample has its own Dart glue (equivalent to the sample's reference `.ts` file).
  - The harness runs the core `SerialHost` with incrementing IDs and compares the emitted messages with the
    sample's `.ndjson`.
  - Every sample that is not skipped also runs through the real `dart test` host as an integration check.
  - Sample arguments are translated: `--retry 2` → `retry: 2`, `--order reverse` → `order: 'reverse'`.
- **Normalisation:**
  - IDs are remapped to canonical IDs in order of first appearance, then compared exactly. This also checks that
    references point at the right messages, which is stricter than cucumber-js or cucumber-jvm. `workerId` names a
    worker, not a message, so it is not an ID here (merged reports set it to the suite ID, §8.4).
  - Timestamps and durations are ignored.
  - For `meta`, only `protocolVersion` is checked.
  - The URI and line of code `sourceReference`s are ignored.
  - `message`, `exception.message` and `exception.stackTrace` are ignored. `exception.type` is ignored too, because
    the samples throw JavaScript `Error`s; only the presence of `exception` is compared.
  - Snippet `code` and `language` are ignored here and checked against Dart golden snippets separately.
  - These are kept and compared: Gherkin locations, statuses, `stepMatchArguments` (including group `start`
    offsets), attachment bodies, encodings and media types.
- **Order.** Message sequences are compared per type, plus explicit partial-order assertions:
  - a message is never referenced before it is emitted;
  - every started message comes before its finished message;
  - nesting is respected.
- **Extra fields are tolerated,** as cucumber-jvm does. For example, exception-based pending adds a `message` to the
  `pending` sample.
- **Expected skips (initial):**
  - `markdown`: no Gherkin-in-Markdown support in `cucumber_gherkin`;
  - `test-run-exception`: depends on fake-cucumber's `--error` switch.

  The target is all other **47** samples.
- **Report.** [`docs/compatibility.md`](compatibility.md) lists every sample with its result through each host and
  justifies each skip. `packages/cucumber/test/compatibility_report_test.dart` fails when it no longer matches the
  samples or the skip lists the two harnesses use.

---

## 11. Gaps in the hosted `cucumber_expressions` (ADR-0020)

The runner uses the published [`cucumber_expressions`][expressions] package (20.1.0). It lacks three things the
runner needs. Each is worked around in `cucumber_core` or contributed to cucumber/cucumber-expressions.

1. **Offsets for every group.**
   - `Group.start` (and `end`) are only set on the root group, because `RegExpMatch` exposes no group offsets.
   - The CCK `testCase.stepMatchArgumentsLists` needs `start` for every argument and nested group, e.g.
     `{flight}` → `LHR`@0, `CDG`@4.
   - Plan: `TreeRegexp` rewrites the pattern so that every top-level sibling and every alternative is captured, and
     computes offsets from captured lengths.
     - For a quantified group, the start is derived from the end of the enclosing capture.
     - Numbered back-references are renumbered.
     - Groups inside lookarounds are handled on a best-effort basis.
   - Conformance fixtures with offsets will be added.
2. **Non-nullable built-in parameter types.**
   - Change `ParameterType<int?>` to `ParameterType<int>`, and likewise for `double` and `String`.
   - This is needed for the reified type checks in §4.5. A top-level parameter group always participates in a
     match, so its value is never null.
3. **Parameter types before matching.**
   - Expose an expression's parameter types (Cucumber Expression nodes, or regex top-level groups with resolved
     types) before any match happens.
   - This enables the arity and type checks when glue loads.

Upstream contributions come with conformance fixtures and keep the API compatible. Until they are released, any
workaround lives in `cucumber_core`, not in a fork.

**Current workarounds in `cucumber_core`** (`lib/src/expressions/`):

1. `TreeRegexp` parses the expression's `regexp` and rewrites it as planned above, then computes every group's
   `start` from the measuring captures. If a pattern cannot be rewritten, nested groups get no `start`.
2. `cucumber_core` keeps its own registry of the built-in types with non-nullable Dart types and transformers.
   They mirror the hosted ones, which are still used for parsing and snippet generation.
3. Parameter types are known when glue loads: Cucumber Expressions are scanned for their (already validated)
   `{name}` references, and regular expression groups are typed by looking up their source in that registry.

**Upstream wishlist** for the other Dart ports:
- `cucumber_gherkin`: Markdown support and a default-dialect option.
- `cucumber_messages`: ID generators and status-ordering helpers, which the JS and Ruby messages packages have.

---

## 12. Flutter roadmap (post-v1, ADR-0004)

- **Widget tests.**
  - `cucumber_flutter` adds `cucumberWidgets(...)`, which declares `testWidgets`.
  - `FlutterWorld` exposes the `WidgetTester`.
  - Widget tests run on the host VM, so feature files load from disk as in pure Dart.
- **`integration_test` on a device.**
  - A builder generates `features.g.dart` containing the feature sources, so declaration stays synchronous and needs
    no file access.
  - Configuration comes from `--dart-define`.
  - Messages are sent back to the host as framed NDJSON on stdout, or via `reportData` under `flutter drive`.
  - A host-side collector writes the reports.
- **Upstream.** Propose `location:` support in the `flutter_test` wrappers so Flutter tests can link to `.feature`
  lines.

## 13. Codegen roadmap (post-v1, ADR-0002)

- `cucumber_builder` adds annotations for steps, hooks and parameter types:
  `@Given`, `@When`, `@Then`, `@Before`, `@After`, `@ParameterType`, and so on.
- Annotated methods live on plain classes whose constructors receive the World and other dependencies. The builder
  generates the equivalent `List<Glue>`.
- This adds compile-time checks (`{int}` against `int`), exact source references, and discovery of step libraries
  without hand-written lists.

---

## 14. Milestones

| Milestone | Scope | Exit criteria |
|---|---|---|
| **M0 Scaffold** | Workspace, package skeletons, hosted `cucumber_expressions` dependency, CCK sample sync tool, `.gitattributes`, lints, CI | `dart analyze` clean; samples synced and drift-checked |
| **M1 Foundations** | Expressions gaps (§11), upstream or in `cucumber_core`; interim tag expressions; ID generators; glue value types with source references; arity and type checking | Unit tests; tag-expression conformance suite green |
| **M2 Engine** | `SupportCodeLibrary`, source loading, filtering, ordering, assembly, `TestCaseRunner` (§5), messages (§7), snippets, World, Scenario, attachments, basic tables and doc strings; `SerialHost`; CCK harness | ≥ 40 CCK samples passing through `SerialHost` |
| **M3 `dart test` host** | `cucumber()`, `CucumberOptions`, `CucumberSuite`, discovery, `path:line`, configuration (YAML profiles + env), test tree, names, locations, tag mapping, outcome mapping, NDJSON plugin | End-to-end example project; CCK subset green through `dart test` |
| **M4 Typed tables** | `DataTableType` and `DocStringType` registries, conversions, `diff` | Ported cucumber-jvm `datatable` behaviour tests |
| **M5 Reports** | `cucumber_query`, `cucumber_ci_environment`, `cucumber_html_formatter`, summary and snippets, automatic merge and merge CLI | Port conformance suites green; merged HTML across 3 entry files |
| **M6 v1 hardening** | Docs, examples, API docs, CI matrix (minimum SDK and stable; Linux, macOS, Windows), performance, published CCK report and skip list | 47/49 CCK; dry-run publish of each package |
| **M7** | `cucumber_flutter`: widget tests | Example Flutter app |
| **M8** | `cucumber_builder`: codegen | Example; compile-time checks |
| **M9** | `integration_test` on device | Device run producing reports |
| **M10 Upstreaming** | Remaining expressions PRs (§11); tag-expressions, ci-environment, query, html-formatter and compatibility-kit Dart ports; JUnit and pretty formatters; Dart support in the Cucumber language server; listing on cucumber.io | Published under `cucumber.io`; this repository switched to the hosted packages |

**Status (2026-10-25):** M1, M2 and M4 are implemented in `cucumber_core`. 47 of 49 CCK samples pass through
`SerialHost` (`packages/cucumber_core/test/compatibility/`), and the tag-expression conformance suite is green. M3
is implemented in `package:cucumber` (entrypoint, configuration, discovery, `package:test` mapping, NDJSON plugin).
Its end-to-end tests run `dart test` on `packages/cucumber/fixtures/e2e` and on the example project, and the same 47 CCK
samples pass through the real host (`fixtures/cck`). M5 (reports) is complete: `cucumber_ci_environment` (sets `meta.ci` in the `dart test` host) and
`cucumber_query` are implemented, and their upstream conformance suites are green (§9). The `summary` plugin (§8.2)
is implemented on `cucumber_query`: unit tests cover its formatter (including retry, undefined, ambiguous, pending,
an empty run and every CCK sample's messages), and the end-to-end tests check what it prints through `dart test`.
`cucumber_html_formatter` wraps the assets of `@cucumber/html-formatter` 24.2.0 (synced and drift-checked, §9), and
the `html:<path>` plugin (§8.2) writes the report: unit tests cover the writer (escaping, an empty run, every CCK
sample's messages) and the plugin, and the end-to-end tests check that the reports written through `dart test`
(from code and from `cucumber.yaml`) embed every message. Automatic report merging (§8.4) is implemented:
`mergeReportParts` (unit tests cover de-duplication, timestamps, success, ID remapping and `workerId`, and every CCK
sample merged with itself still answers `cucumber_query`'s queries consistently), report parts with the merge lock
(tested across isolates and processes), and the merge in `tearDownAll`. The end-to-end tests run one `dart test` on
`fixtures/merge`, whose 3 entry files leave one merged NDJSON and HTML report with every scenario. The
`dart run cucumber:merge` CLI (§8.4) is implemented: unit tests cover argument parsing and errors, finding parts
(manifests, file names, globs), merging two shard directories with a repeated suite ID into NDJSON and HTML, the
summary and the exit codes, and the end-to-end tests run it on the parts left by `fixtures/merge` (reproducing the
automatic merge, and merging them with a copy as a second shard). Old parts are pruned after the automatic merge
(§8.4): unit tests cover the policy (the current run, runs in progress, stale runs) and the end-to-end tests check
that `dart test` prunes a stale run and keeps a recent one. M6 (v1 hardening) has started with publish readiness
(§14.1). Every package has a README, a CHANGELOG, an example (run by a test, except for the compatibility kit's
listing and `cucumber`'s example project, which the end-to-end tests run) and a `.pubignore`. `dart pub publish
--dry-run` passes without warnings for all six packages, and the `publish-dry-run` CI job runs it for the five that
no unpublished dependency blocks. `cucumber_core` no longer has `publish_to: none` and can be published; `cucumber`
waits for its workspace dependencies. API docs are done: every public library has a library doc comment with an
example, and `package:cucumber/cucumber.dart` introduces the whole API it re-exports from `cucumber_core`. The
`api-docs` CI job runs `dart doc --validate-links` for each package and fails on any warning. It also requires the
library doc comments, because dartdoc no longer reports missing ones. The CI matrix was already in place: the minimum
SDK (3.8.0) and 3.12.0 on Linux, and 3.12.0 on macOS and Windows. The CCK report is published:
[`docs/compatibility.md`](compatibility.md) lists every sample of CCK 31.0.0 with its result through `SerialHost`
and through `dart test` (47 of 49 each, the M6 target) and justifies each skip (§10): `markdown` and
`test-run-exception` for both hosts, and none only for `dart test`. `empty`, which had been left out of the
`dart test` run, passes there too. A test in `package:cucumber` fails when the report no longer matches the samples
or the skip lists that the harnesses use, so the CI test job keeps it current. The READMEs of `cucumber_core`,
`cucumber` and `cucumber_compatibility_kit` link to it. Docs and performance remain.

### 14.1 Publishing

The local dry run is not enough on its own. In the workspace it resolves unpublished dependencies to workspace
packages, but pub.dev rejects an upload if a package in `dependencies` does not exist on pub.dev. `dev_dependencies`
are not checked, and pub.dev's analysis (pana) only scores `lib/` and `bin/`. All six package names were free on
pub.dev on 2026-10-22.

Publishing order, dependencies first:

| Step | Package | Unpublished dependencies | Status | `publish_to` |
|---|---|---|---|---|
| 0 | `cucumber_messages`, `cucumber_gherkin`, `cucumber_expressions` | none | On pub.dev (publisher `cucumber.io`) | n/a |
| 1 | `cucumber_core` | none (dev: `cucumber_compatibility_kit`) | Ready to publish from this repository | not set |
| 2 | `cucumber_ci_environment`, `cucumber_query`, `cucumber_html_formatter` | none | Dry run passes. To be published upstream by the Cucumber organisation (ADR-0005, M10), not from here | `none` |
| 2 | `cucumber_compatibility_kit` | none | As above. Only ever a dev dependency, so it does not block step 3 | `none` |
| 3 | `cucumber` | `cucumber_core`, `cucumber_ci_environment`, `cucumber_html_formatter`, `cucumber_query` | Blocked until all four are on pub.dev | `none` |

- **CI.** The `publish-dry-run` job runs `dart pub publish --dry-run` for steps 1 and 2, and warnings fail it.
  `cucumber` is left out because its dry run passes but proves nothing about its real blocker.
- **Until step 3.** Users depend on `cucumber` from Git, overriding its four workspace dependencies with Git
  dependencies as well (`packages/cucumber/README.md`).
- **Contents.** Each archive has the README, CHANGELOG, LICENSE, `example/`, `lib/`, `bin/`, `test/` and `tool/`.
  `.pubignore` leaves out `build/`, the synced upstream test data (`testdata/` of `cucumber_ci_environment` and
  `cucumber_query`, and `test/tag_expressions/testdata/` of `cucumber_core`) and `cucumber`'s `fixtures/`, which
  are workspace packages. The archives are 11–85 KB. `cucumber_html_formatter` is 293 KB, because its payload,
  `lib/src/assets.g.dart`, is 924 KB uncompressed. `repository` points at each package's directory.
- **Can wait (not blocking).**
  - The tests that read the left-out data or the fixtures do not run from an archive.
  - `dart pub get` in an extracted `cucumber_core`, `cucumber_html_formatter` or `cucumber` fails until
    `cucumber_compatibility_kit` is published, because of the dev dependency. Their tests only run in this
    repository.
  - `cucumber`'s example keeps `resolution: workspace`; its README says to remove it outside the repository.
- **Before uploading `cucumber_core`:** choose the uploader (a verified publisher or a personal account) and replace
  `(unreleased)` in its CHANGELOG. Its version (0.0.1) is reported in `meta.implementation`
  (`cucumberCoreVersion`), which a test keeps in step with the pubspec.

---

## 15. Risks and open questions

| Topic | Notes |
|---|---|
| Group offsets in Dart | The hosted `cucumber_expressions` only reports root-group offsets (§11). Rewriting regexes to recover offsets must handle quantifiers, alternation, back-references and lookarounds, and must be covered by conformance fixtures and the CCK. |
| Top-level `log` | Clashes with `dart:math`. Mitigation: `hide log` or a prefix. Could be renamed before 1.0 if it proves annoying. |
| Undeclared tag warnings | `package:test` warns about tags missing from `dart_test.yaml`. Options: document it, generate the list, or turn mapping off. |
| Report correlation under `flutter test` | Each test file runs in its own process, so the process id is not shared. `CUCUMBER_RUN_ID` is required there (revisit in M7). |
| Deterministic static IDs | An unusual choice (ADR-0018). It needs validation against the CCK and the HTML formatter. |
| World type name in snippets | `Type.toString()` can be minified on web and AOT. Snippets are produced in JIT test runs, so this is acceptable. |
| Publishing | `cucumber` cannot be published to pub.dev until `cucumber_core` and the ported packages it depends on are published (ADR-0005, §14.1). `cucumber_core` is ready; the ports wait for upstream (M10). `cucumber_expressions` is already on pub.dev (ADR-0020). If upstreaming the ports stalls, v1 needs another route, for example inlining them in `cucumber` (an alternative ADR-0005 rejected for now). |
| Official adoption | Talk to the Cucumber maintainers early (Discord `#committers`). The org's contribution policy requires disclosing any AI assistance. |

[cucumber-js]: https://github.com/cucumber/cucumber-js
[cucumber-jvm]: https://github.com/cucumber/cucumber-jvm
[cucumber-ruby]: https://github.com/cucumber/cucumber-ruby
[godog]: https://github.com/cucumber/godog
[messages]: https://github.com/cucumber/messages
[gherkin]: https://github.com/cucumber/gherkin
[expressions]: https://pub.dev/packages/cucumber_expressions
[cck]: https://github.com/cucumber/compatibility-kit
