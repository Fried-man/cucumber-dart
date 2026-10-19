import 'package:cucumber_messages/cucumber_messages.dart' as messages;

/// The status of a test step, hook or test case.
///
/// Values are declared in order of severity, so `a.index > b.index` means `a`
/// is worse than `b`. A test case's status is the most severe status of its
/// steps (design §5.1).
enum Status {
  /// Not yet known.
  unknown,

  /// Ran and completed normally.
  passed,

  /// Did not run, or skipped itself.
  skipped,

  /// Marked itself as pending (not implemented yet).
  pending,

  /// No step definition matched.
  undefined,

  /// More than one step definition matched.
  ambiguous,

  /// Threw an error.
  failed;

  /// Whether this status is worse than [other].
  bool isWorseThan(Status other) => index > other.index;

  /// The more severe of this status and [other].
  Status worst(Status other) => other.index > index ? other : this;

  /// Whether this status fails a run when it is the final status of a test
  /// case or hook (strict mode, design §5.7).
  bool get isFailedish =>
      this == pending ||
      this == undefined ||
      this == ambiguous ||
      this == failed;

  /// The Cucumber Messages representation of this status.
  messages.TestStepResultStatus toMessage() => switch (this) {
    unknown => messages.TestStepResultStatus.unknown,
    passed => messages.TestStepResultStatus.passed,
    skipped => messages.TestStepResultStatus.skipped,
    pending => messages.TestStepResultStatus.pending,
    undefined => messages.TestStepResultStatus.undefined,
    ambiguous => messages.TestStepResultStatus.ambiguous,
    failed => messages.TestStepResultStatus.failed,
  };

  /// The [Status] for a Cucumber Messages [status].
  static Status fromMessage(messages.TestStepResultStatus status) =>
      switch (status) {
        messages.TestStepResultStatus.unknown => unknown,
        messages.TestStepResultStatus.passed => passed,
        messages.TestStepResultStatus.skipped => skipped,
        messages.TestStepResultStatus.pending => pending,
        messages.TestStepResultStatus.undefined => undefined,
        messages.TestStepResultStatus.ambiguous => ambiguous,
        messages.TestStepResultStatus.failed => failed,
      };
}
