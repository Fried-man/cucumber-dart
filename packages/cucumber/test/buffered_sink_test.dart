import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cucumber/src/buffered_sink.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:test/test.dart';

/// Collects the chunks an [IOSink] passes on.
final class _Chunks implements StreamConsumer<List<int>> {
  final List<String> chunks = [];

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach((bytes) => chunks.add(utf8.decode(bytes)));

  @override
  Future<void> close() async {}
}

void main() {
  group('BufferedFileSink', () {
    test('passes the text on once chunkSize characters collect', () async {
      final target = _Chunks();
      final sink = BufferedFileSink(IOSink(target), chunkSize: 10);
      for (var i = 0; i < 7; i++) {
        sink.write('abc');
      }
      sink
        ..writeln('!')
        ..writeCharCode(0x7a)
        ..writeAll(['x', 'y'], ',');
      await sink.close();
      expect(target.chunks, ['abcabcabcabc', 'abcabcabc!\n', 'zx,y']);
    });

    test(
      'flush passes on what has collected, and nothing when empty',
      () async {
        final target = _Chunks();
        final sink = BufferedFileSink(IOSink(target))
          ..write('one')
          ..flush()
          ..flush()
          ..write('two');
        await sink.close();
        expect(target.chunks, ['one', 'two']);
      },
    );

    test('writes one chunk for many small writes', () async {
      final target = _Chunks();
      final sink = BufferedFileSink(IOSink(target));
      for (var i = 0; i < 1000; i++) {
        sink
          ..write('{"line":$i}')
          ..write('\n');
      }
      await sink.close();
      expect(target.chunks, hasLength(1));
      expect(
        const LineSplitter().convert(target.chunks.single),
        hasLength(1000),
      );
    });

    test('open writes to a file', () async {
      final directory = Directory.systemTemp.createTempSync('cucumber_sink_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/out.txt')..writeAsStringSync('old');
      final sink = BufferedFileSink.open(file)..write('new');
      await sink.close();
      expect(file.readAsStringSync(), 'new');
    });
  });

  test('endsUnit: the run start, test case and test-run hook ends, and the '
      'run end', () {
    final timestamp = messages.Timestamp(seconds: 0, nanos: 0);
    final ends = [
      messages.Envelope(
        testRunStarted: messages.TestRunStarted(timestamp: timestamp),
      ),
      messages.Envelope(
        testCaseFinished: messages.TestCaseFinished(
          testCaseStartedId: '1',
          timestamp: timestamp,
          willBeRetried: false,
        ),
      ),
      messages.Envelope(
        testRunHookFinished: messages.TestRunHookFinished(
          testRunHookStartedId: '1',
          result: messages.TestStepResult(
            duration: messages.Duration(seconds: 0, nanos: 0),
            status: messages.TestStepResultStatus.passed,
          ),
          timestamp: timestamp,
        ),
      ),
      messages.Envelope(
        testRunFinished: messages.TestRunFinished(
          success: true,
          timestamp: timestamp,
        ),
      ),
    ];
    final others = [
      messages.Envelope(
        meta: messages.Meta(
          protocolVersion: '1',
          implementation: messages.Product(name: 'x'),
          runtime: messages.Product(name: 'x'),
          os: messages.Product(name: 'x'),
          cpu: messages.Product(name: 'x'),
        ),
      ),
      messages.Envelope(
        testCaseStarted: messages.TestCaseStarted(
          attempt: 0,
          id: '1',
          testCaseId: '1',
          timestamp: timestamp,
        ),
      ),
      messages.Envelope(
        testStepFinished: messages.TestStepFinished(
          testCaseStartedId: '1',
          testStepId: '1',
          testStepResult: messages.TestStepResult(
            duration: messages.Duration(seconds: 0, nanos: 0),
            status: messages.TestStepResultStatus.passed,
          ),
          timestamp: timestamp,
        ),
      ),
    ];
    expect(ends.map(endsUnit), everyElement(isTrue));
    expect(others.map(endsUnit), everyElement(isFalse));
  });
}
