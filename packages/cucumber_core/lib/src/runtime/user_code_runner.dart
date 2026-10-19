import 'dart:async';

import '../world/context.dart';
import 'platform.dart';

/// The outcome of running user code.
final class UserCodeResult {
  /// Creates a result.
  const UserCodeResult(this.duration, [this.error, this.stackTrace]);

  /// How long the code ran.
  final Duration duration;

  /// The error thrown (or reported as uncaught), if any.
  final Object? error;

  /// The stack trace of [error].
  final StackTrace? stackTrace;

  /// Whether the code completed normally.
  bool get succeeded => error == null;
}

/// Runs user functions (steps, hooks, transformers) in guarded zones
/// (design §3.3, §5.8).
///
/// - Synchronous throws, asynchronous errors and uncaught errors in the zone
///   all end the invocation with that error.
/// - A [timeout] ends it with a [TimeoutException].
/// - Uncaught errors arriving after the invocation ended are passed to
///   `onLateError`, if given.
final class UserCodeRunner {
  /// Creates a runner measuring time with [platform].
  const UserCodeRunner(this.platform);

  /// The platform, for its stopwatch.
  final CucumberPlatform platform;

  /// Runs [body] with [context] as the current context.
  Future<UserCodeResult> run(
    FutureOr<void> Function() body, {
    required ExecutionContext context,
    Duration? timeout,
    void Function(Object error, StackTrace stackTrace)? onLateError,
  }) {
    final completer = Completer<UserCodeResult>();
    final stopwatch = platform.startStopwatch();
    Timer? timer;

    void finish(Object? error, StackTrace? stackTrace) {
      if (completer.isCompleted) {
        if (error != null) onLateError?.call(error, stackTrace!);
        return;
      }
      timer?.cancel();
      stopwatch.stop();
      completer.complete(UserCodeResult(stopwatch.elapsed, error, stackTrace));
    }

    if (timeout != null) {
      timer = Timer(timeout, () {
        finish(
          TimeoutException('Timed out after $timeout', timeout),
          StackTrace.empty,
        );
      });
    }

    runGuardedInContext(context, () {
      Future<void>.sync(body).then<void>(
        (_) => finish(null, null),
        onError: (Object error, StackTrace stackTrace) =>
            finish(error, stackTrace),
      );
    }, finish);
    return completer.future;
  }
}
