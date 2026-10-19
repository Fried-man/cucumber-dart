import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import 'plugin.dart';

/// Delivers messages to plugins in order.
///
/// Messages emitted before [start] are buffered. Hosts declare suites
/// synchronously but only start a run when at least one test runs, so a suite
/// whose tests are all filtered out writes nothing (design §6).
final class MessageBus {
  /// Creates a bus delivering to [plugins].
  MessageBus([List<Plugin> plugins = const []]) : _plugins = [...plugins];

  final List<Plugin> _plugins;
  final List<messages.Envelope> _buffer = [];
  bool _started = false;
  bool _closed = false;

  /// Whether [start] has been called.
  bool get isStarted => _started;

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  /// Adds a plugin. Messages already delivered are not replayed, but buffered
  /// ones will be.
  void addPlugin(Plugin plugin) {
    if (_closed) throw StateError('The message bus is closed.');
    _plugins.add(plugin);
  }

  /// Emits [envelope]: delivers it now if the bus has started, otherwise
  /// buffers it.
  void emit(messages.Envelope envelope) {
    if (_closed) throw StateError('The message bus is closed.');
    if (_started) {
      _deliver(envelope);
    } else {
      _buffer.add(envelope);
    }
  }

  /// Starts delivery, flushing buffered messages first. Calling it again does
  /// nothing.
  void start() {
    if (_started) return;
    _started = true;
    for (final envelope in _buffer) {
      _deliver(envelope);
    }
    _buffer.clear();
  }

  /// Closes every plugin. Buffered messages are discarded if the bus was never
  /// started.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _buffer.clear();
    for (final plugin in _plugins) {
      await plugin.close();
    }
  }

  void _deliver(messages.Envelope envelope) {
    for (final plugin in _plugins) {
      plugin.onMessage(envelope);
    }
  }
}
