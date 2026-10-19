import 'dart:async';

import 'package:cucumber_messages/cucumber_messages.dart' as messages;

/// Receives the Cucumber Messages of a test run (design §8.1).
///
/// Formatters and report writers are plugins. They only consume messages.
abstract interface class Plugin {
  /// Called for each message, in emission order.
  void onMessage(messages.Envelope envelope);

  /// Called once after the last message.
  FutureOr<void> close();
}

/// A [Plugin] that keeps every message in memory.
///
/// Useful in tests and for hosts that post-process a run.
final class CollectingPlugin implements Plugin {
  final List<messages.Envelope> _envelopes = [];

  /// Whether [close] has been called.
  bool get isClosed => _closed;
  bool _closed = false;

  /// The messages received so far, in order.
  List<messages.Envelope> get envelopes => List.unmodifiable(_envelopes);

  @override
  void onMessage(messages.Envelope envelope) => _envelopes.add(envelope);

  @override
  void close() => _closed = true;
}

/// A [Plugin] that forwards each message to a callback.
final class CallbackPlugin implements Plugin {
  /// Creates a plugin that calls [onEnvelope] for each message, and [onClose]
  /// when the run ends.
  CallbackPlugin(this.onEnvelope, {this.onClose});

  /// Called for each message.
  final void Function(messages.Envelope envelope) onEnvelope;

  /// Called when the run ends.
  final FutureOr<void> Function()? onClose;

  @override
  void onMessage(messages.Envelope envelope) => onEnvelope(envelope);

  @override
  FutureOr<void> close() => onClose?.call();
}
