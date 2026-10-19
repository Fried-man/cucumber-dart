import 'source_reference.dart';

/// Thrown by a step or hook to mark itself as pending (not implemented yet).
///
/// The step's status becomes PENDING (design §4.7, ADR-0008). Use [pending]
/// for a terser form.
class PendingException implements Exception {
  /// Creates a pending marker with an optional [message].
  PendingException([this.message = 'TODO: implement me']);

  /// Why the step is pending.
  final String message;

  @override
  String toString() => message;
}

/// Thrown by a step or hook to skip the rest of the scenario.
///
/// The step's status becomes SKIPPED, and the remaining steps of the scenario
/// are skipped. `After` hooks still run (design §5.3, ADR-0008). Use [skip] for
/// a terser form.
class SkippedException implements Exception {
  /// Creates a skip marker with an optional [reason].
  SkippedException([this.reason]);

  /// Why the step was skipped, if given.
  final String? reason;

  @override
  String toString() => reason ?? 'skipped';
}

/// Marks the current step or hook as pending by throwing a
/// [PendingException].
Never pending([String message = 'TODO: implement me']) =>
    throw PendingException(message);

/// Skips the current step or hook, and the rest of the scenario, by throwing a
/// [SkippedException].
Never skip([String? reason]) => throw SkippedException(reason);

/// A problem with a single glue value, found when the glue loads.
final class GlueError {
  /// Creates a glue error for the glue defined at [source].
  const GlueError(this.message, {this.source});

  /// What is wrong.
  final String message;

  /// Where the faulty glue value was constructed, when known.
  final SourceReference? source;

  @override
  String toString() => source == null ? message : '$message\n  at $source';
}

/// Thrown when glue values are invalid: invalid expressions, duplicate
/// parameter types, invalid hook tag expressions, impossible arities or type
/// mismatches (design §4.5).
///
/// Undefined parameter types are *not* glue errors; they are reported as
/// `undefinedParameterType` messages and make matching steps UNDEFINED.
final class GlueException implements Exception {
  /// Creates an exception reporting [errors].
  GlueException(List<GlueError> errors) : errors = List.unmodifiable(errors);

  /// Every problem found, in definition order.
  final List<GlueError> errors;

  @override
  String toString() {
    final buffer = StringBuffer(
      'Invalid Cucumber glue (${errors.length} '
      '${errors.length == 1 ? 'problem' : 'problems'}):',
    );
    for (final error in errors) {
      buffer.write('\n\n- ${error.toString().replaceAll('\n', '\n  ')}');
    }
    return buffer.toString();
  }
}
