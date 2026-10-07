/// Runner-agnostic Cucumber engine for Dart.
///
/// This library will expose the glue API (`Given`, `When`, `Then`, hooks,
/// parameter types, data table and doc string types, the `World`) and the
/// engine that turns Gherkin pickles into executed test cases and Cucumber
/// Messages.
///
/// It must stay pure Dart: no `dart:io`, `dart:mirrors`, Flutter or
/// `package:test`. Hosts such as `package:cucumber` inject platform facts.
///
/// Most users should depend on `package:cucumber`, which re-exports this
/// library and runs features with `dart test`. See `docs/design.md`.
library;
