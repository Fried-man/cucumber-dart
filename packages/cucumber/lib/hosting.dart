/// Building blocks for hosts built on the `dart test` host of
/// `package:cucumber`, such as `cucumber_flutter`'s widget-test host.
///
/// [declareCucumberSuite] declares a suite exactly like
/// `CucumberSuite.declare` (configuration, discovery, groups, `setUpAll` and
/// `tearDownAll`, outcomes and reports), but lets the host declare each
/// scenario's test, choose the default World and check for errors after each
/// step and hook:
///
/// ```dart
/// import 'package:cucumber/cucumber.dart';
/// import 'package:cucumber/hosting.dart';
/// import 'package:test/test.dart';
///
/// void declareTracedSuite(CucumberOptions options) =>
///     declareCucumberSuite<DefaultWorld>(
///       options,
///       declareScenario: (name, body, {required location, tags, timeout}) {
///         test(name, () async {
///           print('Running $name (${location.uri}:${location.line})');
///           await body();
///         }, location: location, tags: tags, timeout: timeout);
///       },
///     );
/// ```
///
/// Suites themselves use `package:cucumber/cucumber.dart` (or a host's own
/// library), not this one.
library;

export 'src/host.dart' show ScenarioTestDeclarer, declarePackageTest;
export 'src/suite.dart' show declareCucumberSuite;
