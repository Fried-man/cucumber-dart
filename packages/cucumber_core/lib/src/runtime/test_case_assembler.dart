import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import '../expressions/step_expression.dart';
import '../gherkin/gherkin_index.dart';
import '../glue/definitions.dart';
import '../glue/support_code_library.dart';
import 'ids.dart';

/// A step definition that matched a pickle step, with its arguments.
final class StepMatch {
  /// Creates a match.
  const StepMatch(this.definition, this.arguments);

  /// The matching step definition.
  final StepDefinition definition;

  /// The matched arguments.
  final List<StepArgument> arguments;
}

/// A test step: a hook or a pickle step.
final class TestStepPlan {
  TestStepPlan._hook(this.message, HookDefinition this.hook)
    : pickleStep = null,
      gherkinStep = null,
      matches = const [];

  TestStepPlan._step(
    this.message,
    messages.PickleStep this.pickleStep,
    this.gherkinStep,
    this.matches,
  ) : hook = null;

  /// The `TestStep` message.
  final messages.TestStep message;

  /// The hook, for hook steps.
  final HookDefinition? hook;

  /// The pickle step, for pickle steps.
  final messages.PickleStep? pickleStep;

  /// The Gherkin step the pickle step was compiled from.
  final messages.Step? gherkinStep;

  /// The matching step definitions (none: undefined; several: ambiguous).
  final List<StepMatch> matches;

  /// The test step ID.
  String get id => message.id;
}

/// A pickle turned into test steps.
final class AssembledTestCase {
  AssembledTestCase._(this.message, this.pickle, this.steps);

  /// The `TestCase` message.
  final messages.TestCase message;

  /// The pickle.
  final messages.Pickle pickle;

  /// The test steps: `Before` hooks, pickle steps, then `After` hooks.
  final List<TestStepPlan> steps;
}

/// Turns pickles into test cases (design §5.2): matching `Before` hooks in
/// ascending order, the pickle steps matched against every step definition,
/// then matching `After` hooks in descending order.
final class TestCaseAssembler {
  /// Creates an assembler.
  const TestCaseAssembler(this.library, this.ids);

  /// The glue.
  final SupportCodeLibrary library;

  /// The ID scheme.
  final IdScheme ids;

  /// Assembles [pickle]. [index] is the index of its Gherkin document.
  AssembledTestCase assemble(
    messages.Pickle pickle, {
    GherkinIndex? index,
    String? testRunStartedId,
  }) {
    final testCaseId = ids.newId();
    final tags = [for (final tag in pickle.tags) tag.name];
    final steps = <TestStepPlan>[];

    TestStepPlan hookStep(HookDefinition hook) => TestStepPlan._hook(
      messages.TestStep(id: ids.newId(), hookId: hook.id),
      hook,
    );

    for (final hook in library.beforeHooks) {
      if (hook.appliesTo(tags)) steps.add(hookStep(hook));
    }
    for (final pickleStep in pickle.steps) {
      final matches = <StepMatch>[];
      for (final definition in library.stepDefinitions) {
        final arguments = definition.match(pickleStep.text);
        if (arguments != null) matches.add(StepMatch(definition, arguments));
      }
      steps.add(
        TestStepPlan._step(
          messages.TestStep(
            id: ids.newId(),
            pickleStepId: pickleStep.id,
            stepDefinitionIds: [for (final m in matches) m.definition.id],
            stepMatchArgumentsLists: [
              for (final m in matches)
                messages.StepMatchArgumentsList(
                  stepMatchArguments: [
                    for (final argument in m.arguments) argument.toMessage(),
                  ],
                ),
            ],
          ),
          pickleStep,
          index?.stepOf(pickleStep),
          matches,
        ),
      );
    }
    for (final hook in library.afterHooks) {
      if (hook.appliesTo(tags)) steps.add(hookStep(hook));
    }

    return AssembledTestCase._(
      messages.TestCase(
        id: testCaseId,
        pickleId: pickle.id,
        testSteps: [for (final step in steps) step.message],
        testRunStartedId: testRunStartedId,
      ),
      pickle,
      List.unmodifiable(steps),
    );
  }
}
