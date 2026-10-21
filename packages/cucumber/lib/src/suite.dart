import 'dart:io';

import 'package:cucumber_core/engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart' show Timeout;

import 'configuration.dart';
import 'discovery.dart';
import 'host.dart';
import 'options.dart';
import 'platform.dart';
import 'plugins.dart';
import 'report_merging.dart';

/// Declares a Cucumber suite as `package:test` tests (design §4.8).
///
/// ```dart
/// // test/cucumber_test.dart  →  dart test
/// import 'package:cucumber/cucumber.dart';
///
/// void main() => cucumber(
///   features: ['features/'],
///   world: BellyWorld.new,
///   glue: bellyGlue,
/// );
/// ```
///
/// This is shorthand for `CucumberSuite<W>(CucumberOptions(...)).declare()`;
/// see [CucumberOptions] for the options and [CucumberSuite.declare] for what
/// is declared. Settings from `cucumber.yaml` and `CUCUMBER_*` environment
/// variables take precedence over the arguments (design §4.9).
void cucumber<W extends Object>({
  required List<Glue> glue,
  W Function()? world,
  List<String>? features,
  String? tags,
  List<String>? names,
  int? retry,
  String? order,
  bool? dryRun,
  Map<String, Object?>? worldParameters,
  List<Object>? plugins,
  String? suiteName,
  String? profile,
  bool? mapTags,
  Timeout? scenarioTimeout,
}) => CucumberSuite<W>(
  CucumberOptions(
    glue: glue,
    world: world,
    features: features,
    tags: tags,
    names: names,
    retry: retry,
    order: order,
    dryRun: dryRun,
    worldParameters: worldParameters,
    plugins: plugins,
    suiteName: suiteName,
    profile: profile,
    mapTags: mapTags,
    scenarioTimeout: scenarioTimeout,
  ),
).declare();

/// A Cucumber suite whose World type is [W] (ADR-0012).
///
/// [W] is the type created by [CucumberOptions.world]; step and hook bodies
/// that take a World are checked against it. [cucumber] infers it from its
/// `world` argument, but when using this class directly, pass it explicitly:
///
/// ```dart
/// void main() => CucumberSuite<ShopWorld>(sharedOptions).declare();
/// ```
final class CucumberSuite<W extends Object> {
  /// Creates a suite with [options].
  CucumberSuite(this.options);

  /// The options given in code.
  final CucumberOptions options;

  /// Declares the suite in the current `package:test` scope. This is fully
  /// synchronous, so call it directly from `main()` (or a [group] body):
  ///
  /// 1. resolves the configuration from [options], `cucumber.yaml` and the
  ///    environment;
  /// 2. finds and reads the feature files;
  /// 3. parses them, loads the glue, and filters and orders the scenarios;
  /// 4. declares a group per feature, rule, scenario outline and examples, a
  ///    test per scenario or example row, and a `setUpAll`/`tearDownAll`
  ///    pair that starts and finishes the run.
  ///
  /// The `message:` and `html:` outputs are merged reports (design §8.4):
  /// the suite writes its messages to a report part in
  /// `build/.cucumber/parts/<runId>/`, and `tearDownAll` rewrites each output
  /// from the parts of every suite of the run that configures it, so one
  /// `dart test` run of several entry files leaves one report.
  ///
  /// Invalid glue throws a `GlueException`, and an invalid configuration
  /// throws a [CucumberConfigurationException], so `dart test` reports a
  /// load failure for the test file.
  void declare() {
    final glue = options.glue;
    if (glue == null) {
      throw CucumberConfigurationException(
        'No glue: pass the step definitions and hooks with CucumberOptions(glue: ...).',
      );
    }
    final world = options.world;
    if (world != null && world is! W Function()) {
      throw CucumberConfigurationException(
        'The world factory (${world.runtimeType}) does not create a $W. Use '
        'CucumberSuite<YourWorld>(options).',
      );
    }

    final packageRoot = findPackageRoot(Directory.current.path);
    final platform = IoCucumberPlatform();
    final config = resolveConfiguration(
      options,
      packageRoot: packageRoot,
      environment: platform.environment,
    );
    final features = discoverFeatures(
      config.features,
      packageRoot: packageRoot,
    );
    final suiteName = config.suiteName?.trim() ?? '';
    final merging = ReportMerging(
      outputDirectory: p.join(packageRoot, outputDirectoryName),
      runId: resolveRunId(platform.environment),
      suiteId: suiteName.isNotEmpty ? suiteName : testFileSuiteId(packageRoot),
    );
    final plan = SuitePlan.create<W>(
      features: features.sources,
      glue: glue,
      world: world as W Function()?,
      options: config.toRunOptions(lines: features.lines),
      plugins: createPlugins(
        config.plugins,
        packageRoot: packageRoot,
        merging: merging,
      ),
      platform: platform,
    );
    PackageTestHost(
      packageRoot: packageRoot,
      mapTags: config.mapTags,
      scenarioTimeout: config.scenarioTimeout,
    ).declare(plan);
  }
}

/// The package root for [directory]: the closest directory at or above it
/// that contains a `pubspec.yaml`, or [directory] itself if there is none.
///
/// `dart test` runs in the package root, so this is normally [directory].
String findPackageRoot(String directory) {
  var current = p.normalize(p.absolute(directory));
  while (true) {
    if (File(p.join(current, 'pubspec.yaml')).existsSync()) return current;
    final parent = p.dirname(current);
    if (parent == current) return p.normalize(p.absolute(directory));
    current = parent;
  }
}
