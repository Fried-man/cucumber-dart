/// Detects the CI environment of a run from its environment variables.
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:cucumber_ci_environment/cucumber_ci_environment.dart';
///
/// void main() {
///   final ci = detectCiEnvironment(Platform.environment);
///   print(ci?.toJson() ?? 'No CI environment detected');
/// }
/// ```
///
/// The result is the `Ci` message of `meta.ci` in Cucumber Messages.
///
/// This package is a Dart port of
/// [cucumber/ci-environment](https://github.com/cucumber/ci-environment).
/// Its CI environment templates and acceptance test data are synced from a
/// pinned upstream release by `tool/sync.dart` (ADR-0005).
///
/// Where the upstream implementations differ, this port follows JavaScript,
/// except that a GitHub pull request event payload that cannot be read
/// falls back to `GITHUB_SHA` instead of throwing, as in Java.
library;

export 'src/detect_ci_environment.dart' show ReadTextFile, detectCiEnvironment;
