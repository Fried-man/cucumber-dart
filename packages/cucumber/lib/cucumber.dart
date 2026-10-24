/// Cucumber for Dart: runs Gherkin `.feature` files as `package:test` tests.
///
/// This is the only library a test suite needs. It re-exports the glue API of
/// `package:cucumber_core` (steps, hooks, types, World, tables) and adds the
/// `dart test` host: feature discovery, configuration and reports.
///
/// Define the steps as glue values, with a World that holds each scenario's
/// state:
///
/// ```dart
/// // test/steps/belly_steps.dart
/// import 'package:cucumber/cucumber.dart';
/// import 'package:test/test.dart';
///
/// class BellyWorld extends World {
///   int cukes = 0;
/// }
///
/// final bellyGlue = <Glue>[
///   Given('I have {int} cukes in my belly', (BellyWorld w, int cukes) {
///     w.cukes += cukes;
///   }),
///   Then('my belly should contain {int} cukes', (BellyWorld w, int cukes) {
///     expect(w.cukes, cukes);
///   }),
///   Before((Scenario s) => log('Starting ${s.name}')),
/// ];
/// ```
///
/// Then declare the suite in a test file and run `dart test`:
///
/// ```dart
/// // test/cucumber_test.dart
/// import 'package:cucumber/cucumber.dart';
///
/// import 'steps/belly_steps.dart';
///
/// void main() => cucumber(
///   features: ['features/'],
///   world: BellyWorld.new,
///   glue: bellyGlue,
/// );
/// ```
///
/// ## Suites
///
/// [cucumber] declares a suite: a group per feature, rule, scenario outline
/// and examples, and a test per scenario or example row. It is shorthand for
/// [CucumberSuite] with [CucumberOptions], whose values can be shared and
/// refined with [CucumberOptions.merge] across several test files. Options in
/// code are overridden by `cucumber.yaml` profiles, which are overridden by
/// `CUCUMBER_*` environment variables. Invalid glue throws a [GlueException],
/// and an invalid configuration throws a [CucumberConfigurationException].
///
/// ## Glue
///
/// A suite takes an ordered list of [Glue] values:
///
/// - steps: [Given], [When] and [Then] (all [StepGlue]), with a Cucumber
///   Expression (`String`) or a `RegExp`;
/// - scenario and step hooks: [Before], [After], [BeforeStep] and [AfterStep]
///   (all [HookGlue]), which can receive the [Scenario] or the [Step];
/// - test-run hooks: [BeforeAll] and [AfterAll], which can receive the
///   [TestRun];
/// - types: [ParameterType] for `{name}` parameters, and [DataTableType] and
///   [DocStringType] for typed data tables and doc strings.
///
/// Step and hook bodies may take the World as their first parameter, followed
/// by the step's parameters and its [DataTable] or [DocString]. The shapes
/// and types are checked when the glue loads.
///
/// ## Scenario state and outcomes
///
/// - [World] is an optional base class for the World, which is created for
///   every scenario attempt. Without a `world` factory, a [DefaultWorld] is
///   used.
/// - [attach], [log] and [link] add attachments to the report.
/// - [pending] and [skip] mark a step as pending or skipped. Any other
///   exception, including a failed `expect`, fails it. [Status] lists the
///   results.
/// - [DataTable.diff] throws a [TableDiffException] when two tables differ,
///   and failed table and doc string conversions throw a
///   [ConversionException].
///
/// ## Reports
///
/// The `plugins` option takes plugin specifications, which can also be set in
/// `cucumber.yaml` and `CUCUMBER_PLUGIN`:
///
/// - `message:<path>`: the Cucumber Messages as NDJSON ([NdjsonPlugin]);
/// - `html:<path>`: a standalone HTML report ([HtmlPlugin]);
/// - `summary`: failures, counts and snippets for undefined steps, printed
///   when the suite ends ([SummaryPlugin], [formatSummary]).
///
/// It also takes [Plugin] instances, such as a [CallbackPlugin] or a
/// [CollectingPlugin]. Plugins receive `Envelope`s from
/// `package:cucumber_messages`.
///
/// When one `dart test` run has several suites, their `message:` and `html:`
/// reports are merged into one. [mergeReportParts] merges [ReportPart]s in
/// code, and `dart run cucumber:merge` merges the parts of CI shards.
///
/// Hosts for other test frameworks use `package:cucumber_core/engine.dart`
/// instead. See the
/// [design](https://github.com/Fried-man/cucumber-dart/blob/main/docs/design.md)
/// for the semantics.
library;

export 'package:cucumber_core/cucumber_core.dart';

export 'src/configuration.dart' show CucumberConfigurationException;
export 'src/merge.dart' show ReportPart, mergeReportParts;
export 'src/options.dart' show CucumberOptions;
export 'src/plugins.dart' show HtmlPlugin, NdjsonPlugin;
export 'src/suite.dart' show CucumberSuite, cucumber;
export 'src/summary.dart' show SummaryPlugin, formatSummary, formatSummaryOf;
