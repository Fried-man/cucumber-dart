import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:stack_trace/stack_trace.dart';

import '../source_reference.dart';

/// Removes frames from the cucumber packages, `package:stack_trace` and the
/// Dart SDK from [stackTrace] (design §7.6).
///
/// When [gherkinFrame] (such as `features/belly.feature:12`) is given, it is
/// appended as the last frame, so traces end at the Gherkin step.
String filterStackTrace(StackTrace? stackTrace, {String? gherkinFrame}) {
  final lines = <String>[];
  if (stackTrace != null && stackTrace.toString().isNotEmpty) {
    try {
      final frames = Trace.from(
        stackTrace,
      ).frames.where((f) => !f.isCore && !internalPackages.contains(f.package));
      final trace = Trace(frames).toString().trimRight();
      if (trace.isNotEmpty) lines.add(trace);
    } on Object {
      lines.add(stackTrace.toString().trimRight());
    }
  }
  if (gherkinFrame != null) lines.add(gherkinFrame);
  return lines.join('\n');
}

/// The `exception` of a failed result.
messages.Exception exceptionMessage(
  Object error,
  StackTrace? stackTrace, {
  String? gherkinFrame,
}) {
  final trace = filterStackTrace(stackTrace, gherkinFrame: gherkinFrame);
  return messages.Exception(
    type: error.runtimeType.toString(),
    message: error.toString(),
    stackTrace: trace.isEmpty ? null : trace,
  );
}

/// The `message` of a failed result: the error and its filtered stack trace.
String errorMessage(
  Object error,
  StackTrace? stackTrace, {
  String? gherkinFrame,
}) {
  final trace = filterStackTrace(stackTrace, gherkinFrame: gherkinFrame);
  return trace.isEmpty ? '$error' : '$error\n$trace';
}
