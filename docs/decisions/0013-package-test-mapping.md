# ADR-0013: `package:test` tree, names, locations, tags and outcomes

- **Status:** Accepted
- **Date:** 2026-10-06
- **Design:** §6

## Context

cucumber-jvm's JUnit Platform engine maps Gherkin onto a tree of test descriptors:

- Features, Rules, Outlines and Examples become containers.
- Scenarios and example rows become tests.

It uses a "short" naming strategy, and names example rows `number-and-pickle-if-parameterized`.

`package:test`'s `test()` and `group()` accept a `TestLocation`, which IDEs read through the JSON reporter. The tag
rules are:

- `package:test` throws for tags that are not hyphenated identifiers.
- It warns about tags that are not declared in `dart_test.yaml`.

## Decision

- **Tree:**
  - `group(feature)`, `group(rule)`, `group(outline)` and `group(examples)`;
  - `test(scenario or example row)`.
- **Names:** a node's name, or its keyword when it has no name. Example rows are named `Example #<e>.<r>`, with
  `: <pickle name>` appended when the pickle name differs from the outline name.
- **Locations:** each group and test gets a `TestLocation` pointing at its `.feature` line.
- **Tags:**
  - Gherkin tags become `package:test` tags with the `@` removed.
  - Tags that are not valid hyphenated identifiers are not mapped, but still work in Cucumber tag expressions.
  - `mapTags: false` turns the mapping off.
  - Cucumber tag expressions from configuration filter pickles before declaration.
- **Outcomes:**

  | Final status | Reported to `package:test` as |
  |---|---|
  | PASSED | pass |
  | SKIPPED | `markTestSkipped` |
  | PENDING, UNDEFINED, AMBIGUOUS | `TestFailure`, with snippets for undefined steps |
  | FAILED | The original error, rethrown with its original stack trace, after the Cucumber context is printed with `printOnFailure` |

- **Retry** happens inside the test body, not through `package:test`'s `retry:`.
- **`testCase` messages** are emitted lazily, so tests filtered out by `package:test` (`--name`, `--tags`, shards)
  produce no messages.

## Consequences

**Benefits:**
- IDE navigation to `.feature` lines in pure Dart.
- `dart test --tags` works for valid tags.

**Costs:**
- Undeclared-tag warnings, which we document.
- Flutter needs `flutter_test` to forward `location` before it gets the same navigation.
