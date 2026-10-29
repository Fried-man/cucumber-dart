import 'dart:convert';
import 'dart:io';

import 'package:cucumber/cucumber.dart';
import 'package:cucumber/src/attachments.dart' show mediaTypeOfPath;
import 'package:cucumber_core/engine.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Runs one scenario with a step (and test-run hooks) that call [body], and
/// returns the attachments.
Future<List<messages.Attachment>> attachments(
  void Function() body, {
  bool inBeforeAll = false,
}) async {
  final collector = CollectingPlugin();
  final plan = SuitePlan.create(
    features: const [
      FeatureSource('features/a.feature', '''
Feature: f
  Scenario: s
    Given a step
'''),
    ],
    glue: [
      if (inBeforeAll) BeforeAll(body),
      Given('a step', inBeforeAll ? () {} : body),
    ],
    plugins: [collector],
    ids: IdScheme.incrementing(),
  );
  final result = await const SerialHost().run(plan);
  expect(result.success, isTrue, reason: '${result.testCases}');
  return [for (final e in collector.envelopes) ?e.attachment];
}

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('cucumber_attach_');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  File file(String name, List<int> bytes) =>
      File(p.join(directory.path, name))..writeAsBytesSync(bytes);

  group('attachFile', () {
    test('attaches the bytes Base64-encoded, with the file name', () async {
      final png = file('shot.PNG', [0x89, 0x50, 0x4e, 0x47, 0, 255]);
      final attached = await attachments(() => attachFile(png.path));
      final attachment = attached.single;
      expect(base64Decode(attachment.body), [0x89, 0x50, 0x4e, 0x47, 0, 255]);
      expect(
        attachment.contentEncoding,
        messages.AttachmentContentEncoding.base64,
      );
      expect(attachment.mediaType, 'image/png');
      expect(attachment.fileName, 'shot.PNG');
      expect(attachment.testStepId, isNotNull);
      expect(attachment.testCaseStartedId, isNotNull);
    });

    test('takes a media type and a file name', () async {
      final log = file('out.log', utf8.encode('héllo'));
      final attached = await attachments(
        () => attachFile(
          log.path,
          mediaType: 'text/x.custom',
          fileName: 'renamed.txt',
        ),
      );
      expect(utf8.decode(base64Decode(attached.single.body)), 'héllo');
      expect(attached.single.mediaType, 'text/x.custom');
      expect(attached.single.fileName, 'renamed.txt');
    });

    test('defaults to application/octet-stream', () async {
      final data = file('data.bin', [1, 2, 3]);
      final attached = await attachments(() => attachFile(data.path));
      expect(attached.single.mediaType, 'application/octet-stream');
    });

    test('works in test-run hooks', () async {
      final json = file('run.json', utf8.encode('{}'));
      final attached = await attachments(
        () => attachFile(json.path),
        inBeforeAll: true,
      );
      expect(attached.single.mediaType, 'application/json');
      expect(attached.single.testRunHookStartedId, isNotNull);
      expect(attached.single.testStepId, isNull);
    });

    test('fails the step when the file cannot be read', () async {
      final collector = CollectingPlugin();
      final missing = p.join(directory.path, 'missing.png');
      final plan = SuitePlan.create(
        features: const [
          FeatureSource('features/a.feature', '''
Feature: f
  Scenario: s
    Given a step
'''),
        ],
        glue: [Given('a step', () => attachFile(missing))],
        plugins: [collector],
      );
      final result = await const SerialHost().run(plan);
      final step = result.testCases.single.steps.single;
      expect(step.status, Status.failed);
      expect(step.error, isA<FileSystemException>());
    });

    test('throws outside a scenario or test-run hook', () {
      final text = file('a.txt', [65]);
      expect(() => attachFile(text.path), throwsStateError);
    });
  });

  test('mediaTypeOfPath knows common extensions, ignoring case', () {
    expect(mediaTypeOfPath('a/b/screenshot.png'), 'image/png');
    expect(mediaTypeOfPath('photo.JPG'), 'image/jpeg');
    expect(mediaTypeOfPath('report.html'), 'text/html');
    expect(mediaTypeOfPath('messages.ndjson'), 'application/x-ndjson');
    expect(mediaTypeOfPath('video.webm'), 'video/webm');
    expect(mediaTypeOfPath('notes'), isNull);
    expect(mediaTypeOfPath('archive.tar.unknown'), isNull);
  });
}
