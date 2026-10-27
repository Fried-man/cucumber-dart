# Configuration

A suite's options come from four sources. Later sources override earlier ones:

> built-in defaults < code (`cucumber(...)`, `CucumberOptions`) < `cucumber.yaml` profiles < `CUCUMBER_*` environment
> variables

So code sets up the suite, `cucumber.yaml` holds the variations a project runs (such as a CI profile), and environment
variables change a single run without editing files. The examples come from
[`packages/cucumber/fixtures/guide`](../../packages/cucumber/fixtures/guide/).

## Options

| Code | `cucumber.yaml` | Environment variable | Default | What it does |
|---|---|---|---|---|
| `glue` | — | — | (required) | The steps, hooks and types ([Writing glue](writing-glue.md)) |
| `world` | — | — | a `DefaultWorld` | Creates the World for each scenario attempt |
| `features` | `features` | `CUCUMBER_FEATURES` | `['features/']` | Where the feature files are ([below](#feature-locations)) |
| `tags` | `tags` | `CUCUMBER_FILTER_TAGS` | every scenario | A [tag expression](https://cucumber.io/docs/cucumber/api/#tag-expressions) that selects scenarios, such as `@smoke and not @slow` |
| `names` | `names` | `CUCUMBER_FILTER_NAME` | every scenario | Regular expressions: a scenario runs if its name matches one of them |
| `retry` | `retry` | `CUCUMBER_EXECUTION_RETRY` | `0` | How many more times a failed scenario runs |
| `order` | `order` | `CUCUMBER_EXECUTION_ORDER` | `defined` | `defined`, `reverse`, `random` or `random:<seed>` |
| `dryRun` | `dryRun` | `CUCUMBER_EXECUTION_DRY_RUN` | `false` | Reports the steps without running any step or hook ([below](#dry-run)) |
| `worldParameters` | `worldParameters` | `CUCUMBER_WORLD_PARAMETERS` | `{}` | JSON-like values, as `World.parameters` and `TestRun.parameters` |
| `plugins` | `plugins` | `CUCUMBER_PLUGIN` | none | The reports ([Reports](reports.md)) |
| `suiteName` | `suiteName` | — | the test file's path below `test/`, without `.dart` | Names the suite in merged reports ([Reports](reports.md)) |
| `profile` | — | `CUCUMBER_PROFILE` | `default`, if `cucumber.yaml` defines it | The `cucumber.yaml` profiles to apply ([below](#profiles)) |
| `mapTags` | `mapTags` | — | `true` | Whether Gherkin tags become `package:test` tags ([Running with `dart test`](package-test.md#tags)) |
| `scenarioTimeout` | `scenarioTimeout` | — | `package:test`'s timeout | The timeout of one attempt of a scenario ([below](#timeouts)) |
| — | — | `CUCUMBER_RUN_ID` | the process ID | Groups the report parts of one run ([Reports](reports.md#merging-ci-shards)) |

`glue` and `world` can only be set in code, because they are code. `suiteName`, `mapTags` and `scenarioTimeout` have
no environment variable.

**Values in `cucumber.yaml`.** `features`, `names` and `plugins` take a list or a single string. `scenarioTimeout`
takes a number of seconds, a duration such as `30s` or `2m`, a factor of the default such as `2x`, or `none`. Unknown
options are errors.

**Values of environment variables.** `CUCUMBER_FEATURES`, `CUCUMBER_PLUGIN` and `CUCUMBER_PROFILE` take
comma-separated lists. `CUCUMBER_FILTER_NAME` takes one regular expression, `CUCUMBER_EXECUTION_DRY_RUN` takes `true`
or `false`, and `CUCUMBER_WORLD_PARAMETERS` takes a JSON object. Empty variables are ignored.

An invalid value in any source (an unknown option, an invalid tag expression or order, a feature location that does
not exist) throws a `CucumberConfigurationException`, which `dart test` reports as a load error of the test file.

## How the sources combine

Options are merged one source at a time, in the order above:

- **Values and lists** replace the earlier ones: a profile's `features` replaces the `features` in code.
- **Tag expressions are combined with `and`**, so a later source can only narrow the selection. With
  `tags: not @wip` in code and `CUCUMBER_FILTER_TAGS=@smoke`, the suite runs `(not @wip) and (@smoke)`.
- **World parameters are merged key by key**, recursively for nested maps.
- **Plugins.** `plugins` from a profile or the environment replace the plugin specifications (`'message:…'`, `'html:…'`,
  `'summary'`) from code, but `Plugin` instances given in code are kept, because they cannot be given anywhere else.

`CucumberOptions.merge` follows the same rules, so options shared by several entry files can be refined in each
([Writing glue](writing-glue.md#sharing-glue-between-entry-files)).

## Profiles

`cucumber.yaml` (or `cucumber.yml`) at the package root maps profile names to options:

<!-- excerpt: packages/cucumber/fixtures/guide/cucumber.yaml -->
```yaml
# Applies when no profile is named.
default:
  tags: not @wip
  worldParameters:
    currency: EUR
  plugins:
    - message:build/cucumber/messages.ndjson
    - html:build/cucumber/report.html
    - summary

# Added on CI: CUCUMBER_PROFILE=default,ci
ci:
  tags: not @slow
  scenarioTimeout: 2m

# Only the scenarios in progress: CUCUMBER_PROFILE=wip
wip:
  tags: '@wip'
```

The profiles that apply are the ones named by `CUCUMBER_PROFILE`, or else by the `profile` option in code, or else
`default` if the file defines it. Several profiles are separated by commas and applied in order, so
`CUCUMBER_PROFILE=default,ci` adds the `ci` profile to the `default` one. Naming a profile replaces `default`: with
`CUCUMBER_PROFILE=wip`, the `default` profile does not apply. A profile cannot select other profiles, and naming a
profile that the file does not define is an error.

Quote tag expressions that start with `@` in YAML (`'@wip'`): `@` cannot start a plain YAML value.

<!-- run in: packages/cucumber/fixtures/guide -->
```sh
CUCUMBER_PROFILE=default,ci dart test   # leaves out @wip and @slow, with a 2 minute timeout
CUCUMBER_PROFILE=wip dart test          # fails: the @wip scenario is pending
```

## Selecting scenarios

`tags`, `names` and lines in `features` select the scenarios. Scenarios that are not selected are not declared as
tests at all, unlike the ones that `dart test --name` or `--tags` filter out
([Running with `dart test`](package-test.md#filtering)):

<!-- run in: packages/cucumber/fixtures/guide -->
```sh
CUCUMBER_FILTER_TAGS=@smoke dart test
CUCUMBER_FILTER_TAGS="@shop and not @slow" dart test
CUCUMBER_FILTER_NAME="^paying" dart test
CUCUMBER_FEATURES=features/cart.feature:13 dart test
```

### Feature locations

Each entry of `features` is relative to the package root (or absolute), and is one of:

- **a directory**: every `*.feature` file below it, except files and directories whose names start with `.`;
- **a glob**, such as `features/**/checkout_*.feature`: the `*.feature` files it matches;
- **a file**;
- **a file with lines**, `path:line` or `path:line:line…`: the scenarios at those lines. A line selects a scenario
  when it is the line of the scenario or one of its steps. The line of an `Examples` table selects its rows, the line
  of a row selects that row, and the line of a `Rule` or `Feature` selects all of its scenarios.

The files of a directory or glob are sorted by path, and the locations keep their order. A file selected twice keeps
its first position, and a file selected as a whole ignores lines given for it elsewhere. Locations that do not exist,
and lines given for a directory or a glob, are errors. Under `dart test`, an entry file finds the package root as the
closest directory above the current directory with a `pubspec.yaml`, which is where `dart test` runs.

## Order

`order: defined` runs the scenarios in the order of the files and their scenarios, and `reverse` in the reverse order.
`random` shuffles them, and prints the seed so that the order can be reproduced:

<!-- run in: packages/cucumber/fixtures/guide -->
```sh
CUCUMBER_EXECUTION_ORDER=random:42 dart test
```

<!-- output -->
```text
Cucumber: running scenarios in random order. Reproduce it with order: 'random:42'.
```

## World parameters

World parameters pass values to the glue without code changes, such as the URL of a test server.
`World.parameters` returns them, and each scenario attempt gets its own deep copy. `BeforeAll` hooks can change them
through `TestRun.parameters` before any scenario starts. The guide's shop reads the currency from them:

<!-- run in: packages/cucumber/fixtures/guide -->
```sh
CUCUMBER_WORLD_PARAMETERS='{"currency": "CHF"}' dart test
```

The values must be JSON-like: `null`, booleans, numbers, strings, lists and maps with string keys.

## Dry run

A dry run reports every scenario without running its steps or hooks. Defined steps are reported as skipped, so the
scenarios are skipped. Undefined and ambiguous steps keep those statuses and fail their scenarios, which makes a dry
run a quick check that every step is implemented:

<!-- run in: packages/cucumber/fixtures/guide -->
```sh
CUCUMBER_EXECUTION_DRY_RUN=true dart test
```

## Timeouts

`package:test` gives each scenario's test a timeout, 30 seconds unless `dart_test.yaml` or `--timeout` change it.
`scenarioTimeout` sets it for one attempt of a scenario. With retries, the test's timeout is that times the number of
attempts. Steps and hooks can have their own `timeout` ([Writing glue](writing-glue.md#timeouts-and-retries)).
