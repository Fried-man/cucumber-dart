import 'package:cucumber_core/engine.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;

/// The outcome of running features through the [SerialHost].
final class Run {
  Run(this.result, this.envelopes);

  final TestRunResult result;
  final List<messages.Envelope> envelopes;

  /// The step statuses of the final attempt of each test case.
  List<List<Status>> get statuses => [
    for (final testCase in result.testCases)
      [for (final step in testCase.steps) step.status],
  ];

  /// The attachments emitted, in order.
  List<messages.Attachment> get attachments => [
    for (final e in envelopes) ?e.attachment,
  ];

  /// The `testStepFinished` results, in order.
  List<messages.TestStepResult> get stepResults => [
    for (final e in envelopes)
      if (e.testStepFinished case final finished?) finished.testStepResult,
  ];
}

/// Plans and runs [gherkin] (one feature file) with [glue].
Future<Run> runFeature<W extends Object>(
  String gherkin,
  List<Glue> glue, {
  W Function()? world,
  RunOptions options = const RunOptions(),
  String uri = 'features/test.feature',
}) => runFeatures(
  [FeatureSource(uri, gherkin)],
  glue,
  world: world,
  options: options,
);

/// Plans and runs [features] with [glue].
Future<Run> runFeatures<W extends Object>(
  List<FeatureSource> features,
  List<Glue> glue, {
  W Function()? world,
  RunOptions options = const RunOptions(),
}) async {
  final collector = CollectingPlugin();
  final plan = SuitePlan.create<W>(
    features: features,
    glue: glue,
    world: world,
    options: options,
    plugins: [collector],
    ids: IdScheme.incrementing(),
  );
  final result = await const SerialHost().run(plan);
  return Run(result, collector.envelopes);
}
