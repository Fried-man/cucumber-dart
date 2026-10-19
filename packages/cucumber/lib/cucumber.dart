/// Cucumber for Dart.
///
/// Declares Gherkin features as `package:test` tests:
///
/// ```dart
/// // test/cucumber_test.dart
/// import 'package:cucumber/cucumber.dart';
///
/// void main() => cucumber(
///       features: ['features/'],
///       world: BellyWorld.new,
///       glue: bellyGlue,
///     );
/// ```
///
/// This library re-exports the complete `package:cucumber_core` glue API and
/// adds the `dart test` host: feature discovery, configuration
/// (`cucumber.yaml` profiles and `CUCUMBER_*` environment variables) and
/// report outputs. See `docs/design.md`.
library;

export 'package:cucumber_core/cucumber_core.dart';

export 'src/configuration.dart' show CucumberConfigurationException;
export 'src/options.dart' show CucumberOptions;
export 'src/plugins.dart' show NdjsonPlugin;
export 'src/suite.dart' show CucumberSuite, cucumber;
