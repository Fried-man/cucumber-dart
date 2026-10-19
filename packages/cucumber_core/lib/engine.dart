/// The Cucumber engine API for hosts: plan a suite, declare it in a test
/// framework, run it and collect its messages (ADR-0001).
///
/// ```dart
/// final plan = SuitePlan.create(
///   features: [FeatureSource('features/belly.feature', text)],
///   glue: bellyGlue,
///   world: BellyWorld.new,
///   plugins: [collector],
/// );
/// final result = await const SerialHost().run(plan);
/// ```
///
/// `package:cucumber` builds its `dart test` host on this library. It
/// re-exports the glue API of `package:cucumber_core/cucumber_core.dart`.
library;

export 'cucumber_core.dart';
export 'src/filter/pickle_filter.dart' show PickleFilter;
export 'src/filter/pickle_order.dart'
    show DefinedOrder, PickleOrder, RandomOrder, ReverseOrder;
export 'src/gherkin/gherkin_index.dart'
    show ExampleRowLocation, GherkinIndex, ScenarioLocation;
export 'src/gherkin/source_loader.dart'
    show FeatureSource, LoadedFeature, SourceLoader;
export 'src/glue/support_code_library.dart' show SupportCodeLibrary;
export 'src/plan/plan_nodes.dart'
    show
        ExamplesNode,
        FeatureNode,
        OutlineNode,
        ParseErrorNode,
        PickleNode,
        PlanGroup,
        PlanNode,
        RuleNode;
export 'src/plan/suite_plan.dart'
    show RunOptions, SerialHost, SuitePlan, TestHost;
export 'src/runtime/ids.dart'
    show IdGenerator, IdScheme, IncrementingIdGenerator, UuidIdGenerator;
export 'src/runtime/message_bus.dart' show MessageBus;
export 'src/runtime/platform.dart' show CucumberPlatform;
export 'src/runtime/results.dart'
    show StepResult, TestCaseResult, TestRunResult;
export 'src/runtime/snippets.dart' show SnippetGenerator;
export 'src/version.dart'
    show cucumberCoreVersion, implementationName, protocolVersion;
