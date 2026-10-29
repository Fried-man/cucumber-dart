## 0.0.1 (unreleased)

- Initial version: the Flutter widget-test host of Cucumber for Dart.
  - `cucumberWidgets()` and `CucumberWidgetSuite`: declare Gherkin features as Flutter widget tests, with the
    groups, configuration, outcomes and reports of `package:cucumber`.
  - `FlutterWorld` gives steps and hooks the scenario's `WidgetTester`; exceptions that Flutter reports during a
    step or hook fail it.
  - Reports of the test files of one `flutter test` run are merged without `CUCUMBER_RUN_ID`.
  - Re-exports the API of `package:cucumber`.
