import 'dart:io';

import 'package:cucumber_messages/cucumber_messages.dart' as messages;

/// Collects text written to a file's [IOSink] and passes it on in chunks.
///
/// Every `IOSink.write` to a file becomes its own asynchronous write, so
/// writing each message (and its line break) separately made a report of
/// 50,000 messages take seconds to write (docs/performance.md). This sink
/// passes the text on when [chunkSize] characters have collected, when
/// [flush] is called, and when it is closed.
final class BufferedFileSink implements StringSink {
  /// Creates a sink writing to [sink], such as `File.openWrite()`.
  BufferedFileSink(this._sink, {this.chunkSize = defaultChunkSize});

  /// Opens [file] for writing (truncating it).
  factory BufferedFileSink.open(File file) =>
      BufferedFileSink(file.openWrite());

  /// The default [chunkSize]: 64 Ki characters.
  static const int defaultChunkSize = 64 * 1024;

  /// The number of characters collected before they are passed on.
  final int chunkSize;

  final IOSink _sink;
  final StringBuffer _buffer = StringBuffer();

  @override
  void write(Object? object) {
    _buffer.write(object);
    if (_buffer.length >= chunkSize) flush();
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    _buffer.writeAll(objects, separator);
    if (_buffer.length >= chunkSize) flush();
  }

  @override
  void writeCharCode(int charCode) {
    _buffer.writeCharCode(charCode);
    if (_buffer.length >= chunkSize) flush();
  }

  @override
  void writeln([Object? object = '']) {
    _buffer.writeln(object);
    if (_buffer.length >= chunkSize) flush();
  }

  /// Passes the collected text on to the file.
  void flush() {
    if (_buffer.isEmpty) return;
    _sink.write(_buffer.toString());
    _buffer.clear();
  }

  /// Flushes and closes the file.
  Future<void> close() async {
    flush();
    await _sink.close();
  }
}

/// Whether [envelope] ends a unit of a message stream: the start of the run
/// (after the static messages), a test case attempt, a test-run hook, or the
/// run.
///
/// NDJSON outputs flush after these messages, so a stream that is still being
/// written ends with whole test cases and changes on disk as scenarios finish
/// (design §8.4).
bool endsUnit(messages.Envelope envelope) =>
    envelope.testRunStarted != null ||
    envelope.testCaseFinished != null ||
    envelope.testRunHookFinished != null ||
    envelope.testRunFinished != null;
