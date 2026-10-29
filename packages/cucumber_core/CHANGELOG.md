## 0.0.1 (unreleased)

- Initial version: the runner-agnostic engine of Cucumber for Dart.
  - Glue API: steps with Cucumber Expressions or regular expressions, scenario, step and test-run hooks, parameter
    types, typed data tables and doc strings, a typed World, attachments, `pending()` and `skip()`.
  - Engine: `SuitePlan` (parsing, glue loading with arity and type checks, filtering by tags, names and lines,
    ordering) and `SerialHost`; retries, dry run, snippets and Cucumber Messages 34.
  - `SuitePlan.create(afterUserCode:)` lets hosts fail a step or hook for errors their framework catches outside
    the user code's zone (used by `cucumber_flutter` for exceptions reported during widget tests).
  - Passes 47 of the 49 Cucumber Compatibility Kit 31.0.0 samples.
