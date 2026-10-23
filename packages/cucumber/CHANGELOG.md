## 0.0.1 (unreleased)

- Initial version: the `dart test` host of Cucumber for Dart.
  - `cucumber()`, `CucumberOptions` and `CucumberSuite`: declare Gherkin features as `package:test` tests, with
    groups per feature, rule, outline and examples, test locations at the `.feature` lines, and Gherkin tags as
    `package:test` tags.
  - Feature discovery (directories, globs, `path:line`) and configuration from code, `cucumber.yaml` profiles and
    `CUCUMBER_*` environment variables.
  - Reports: `message:` (NDJSON), `html:` and `summary`, merged across the test files of a run.
  - `dart run cucumber:merge` to merge the report parts of CI shards.
  - Re-exports the glue API of `cucumber_core`.
