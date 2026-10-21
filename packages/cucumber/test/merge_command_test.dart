import 'dart:convert';
import 'dart:io';

import 'package:cucumber/cucumber.dart';
import 'package:cucumber/src/merge_command.dart';
import 'package:cucumber_core/engine.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/dart_test_runner.dart' show ofType, readHtmlReport, readNdjson;

const _cart = 'Feature: Cart\n  Scenario: add\n    Given a step passes\n';
const _search = 'Feature: Search\n  Scenario: find\n    Given a step passes\n';
const _fail = 'Feature: Fail\n  Scenario: fail\n    Given a step fails\n';

final _glue = <Glue>[
  Given('a step passes', () {}),
  Given('a step fails', () => throw StateError('boom')),
];

/// The messages of running [source] (at [uri]) through the [SerialHost].
Future<List<messages.Envelope>> _run(String uri, String source) async {
  final collector = CollectingPlugin();
  final plan = SuitePlan.create(
    features: [FeatureSource(uri, source)],
    glue: _glue,
    plugins: [collector],
  );
  await const SerialHost().run(plan);
  return collector.envelopes;
}

String _ndjson(Iterable<messages.Envelope> envelopes) =>
    [for (final e in envelopes) '${messages.envelopeToJsonString(e)}\n'].join();

void main() {
  late Directory root;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cucumber_merge_command_');
    out = StringBuffer();
    err = StringBuffer();
  });
  tearDown(() => root.deleteSync(recursive: true));

  String path(String relative) =>
      p.joinAll([root.path, ...relative.split('/')]);

  /// Writes the part [file] (relative to the root) with [envelopes], and a
  /// manifest naming the suite [suiteId] if it is given.
  void writePart(
    String file,
    Iterable<messages.Envelope> envelopes, {
    String? suiteId,
  }) {
    File(path(file))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(_ndjson(envelopes));
    if (suiteId != null) {
      File('${p.withoutExtension(path(file))}.json').writeAsStringSync(
        jsonEncode({
          'suiteId': suiteId,
          'outputs': ['message:/elsewhere.ndjson'],
        }),
      );
    }
  }

  Future<int> merge(List<String> arguments) => runMergeCommand(
    arguments,
    out: out,
    err: err,
    workingDirectory: root.path,
  );

  group('parseMergeArguments', () {
    MergeArguments parse(List<String> arguments) =>
        parseMergeArguments(arguments, workingDirectory: root.path);

    test('takes the inputs and the outputs, relative to the working '
        'directory', () {
      final parsed = parse([
        'shard-1',
        '-p',
        'message:out/merged.ndjson',
        'shard-2/part.ndjson',
        '--plugin=html: out/report.html ',
        '--plugin',
        'summary',
        '-p',
        'message:out/../out/merged.ndjson',
      ]);
      expect(parsed.inputs, ['shard-1', 'shard-2/part.ndjson']);
      expect(parsed.outputs.map((o) => '$o'), [
        'message:${path('out/merged.ndjson')}',
        'html:${path('out/report.html')}',
      ]);
      expect(parsed.summary, isTrue);
      expect(parsed.help, isFalse);
    });

    test('prints the summary by default, and only when asked for with '
        'other outputs', () {
      expect(parse(['parts']).summary, isTrue);
      expect(parse(['parts']).outputs, isEmpty);
      expect(parse(['parts', '-p', 'html:a.html']).summary, isFalse);
    });

    test('takes absolute output paths as they are', () {
      final absolute = path('reports/merged.ndjson');
      expect(
        parse(['parts', '-p', 'message:$absolute']).outputs.single.path,
        absolute,
      );
    });

    test('--help needs no inputs', () {
      expect(parse(['--help']).help, isTrue);
      expect(parse(['parts', '-h']).help, isTrue);
    });

    test('takes inputs that look like options after --', () {
      expect(parse(['--', '-p']).inputs, ['-p']);
    });

    for (final (arguments, message) in [
      (<String>[], 'No inputs.'),
      (['-p', 'summary'], 'No inputs.'),
      (['parts', '--output', 'x'], 'Could not find an option named'),
      (['parts', '-p'], 'Missing argument for "-p"'),
      (['parts', '-p', 'junit:out.xml'], 'Unknown plugin "junit:out.xml"'),
      (['parts', '-p', 'message:'], 'needs an output file: message:<path>'),
      (['parts', '-p', 'html: '], 'needs an output file: html:<path>'),
      (['parts', '-p', 'summary:x'], 'takes no argument'),
      (['parts', ''], 'Empty input.'),
    ]) {
      test('rejects ${jsonEncode(arguments)}', () {
        expect(
          () => parse(arguments),
          throwsA(
            isA<MergeUsageException>().having(
              (e) => e.message,
              'message',
              contains(message),
            ),
          ),
        );
      });
    }
  });

  group('findReportPartFiles', () {
    late List<messages.Envelope> cart;

    setUpAll(() async {
      cart = await _run('features/cart.feature', _cart);
    });

    List<ReportPartFile> find(List<String> inputs) =>
        findReportPartFiles(inputs, workingDirectory: root.path);

    test('takes the suite ID from the manifest, or else the file name, and '
        'lists a directory by suite ID', () {
      writePart('run/b.ndjson', cart, suiteId: 'checkout/b_test');
      writePart('run/checkout%2Fa_test.ndjson', cart);
      writePart('run/z.ndjson', cart, suiteId: 'a');
      writePart('run/100%.ndjson', cart);
      File(path('run/other.json')).writeAsStringSync('{}');
      File(path('run/c.ndjson.123.tmp')).writeAsStringSync('');
      Directory(path('run/nested')).createSync();
      writePart('run/nested/ignored.ndjson', cart);

      expect(find(['run']), [
        ReportPartFile('100%', path('run/100%.ndjson')),
        ReportPartFile('a', path('run/z.ndjson')),
        ReportPartFile('checkout/a_test', path('run/checkout%2Fa_test.ndjson')),
        ReportPartFile('checkout/b_test', path('run/b.ndjson')),
      ]);
    });

    test('takes part files, with their manifests, in the order given, each '
        'file once', () {
      writePart('run/b.ndjson', cart, suiteId: 'beta');
      writePart('run/a.ndjson', cart);
      expect(find(['run/b.ndjson', 'run', path('run/a.ndjson')]), [
        ReportPartFile('beta', path('run/b.ndjson')),
        ReportPartFile('a', path('run/a.ndjson')),
      ]);
    });

    test('expands globs', () {
      writePart('shards/2/parts/run/x.ndjson', cart);
      writePart('shards/1/parts/run/x.ndjson', cart);
      writePart('shards/1/parts/run/y.ndjson', cart);
      writePart('shards/1/other.json', cart);
      expect(find(['shards/*/parts/*']), [
        ReportPartFile('x', path('shards/1/parts/run/x.ndjson')),
        ReportPartFile('y', path('shards/1/parts/run/y.ndjson')),
        ReportPartFile('x', path('shards/2/parts/run/x.ndjson')),
      ]);
      expect(find(['shards/2/**.ndjson']), [
        ReportPartFile('x', path('shards/2/parts/run/x.ndjson')),
      ]);
    });

    test('explains inputs that are not report parts', () {
      writePart('parts/1234/a.ndjson', cart);
      writePart('parts/5678/a.ndjson', cart);
      File(path('manifest.json')).writeAsStringSync('{}');
      Directory(path('empty')).createSync();

      void rejects(String input, Object message) => expect(
        () => find([input]),
        throwsA(
          isA<MergeUsageException>().having(
            (e) => e.message,
            'message',
            message,
          ),
        ),
        reason: input,
      );

      rejects('missing', 'Input "missing" not found.');
      rejects(
        'message:out.ndjson',
        'Input "message:out.ndjson" not found. To write the merged report, '
            'use --plugin message:out.ndjson.',
      );
      rejects('summary', contains('use --plugin summary'));
      rejects('manifest.json', contains('is not a report part'));
      rejects('empty', 'No report parts (*.ndjson) in directory "empty".');
      rejects(
        'parts',
        allOf(
          startsWith('No report parts (*.ndjson) in directory "parts".'),
          contains('build/.cucumber/parts/<runId>/'),
          contains('the directories 1234, 5678.'),
        ),
      );
      rejects(
        'nothing/*',
        'No report part directories or .ndjson files match '
            '"nothing/*".',
      );
    });
  });

  test('disambiguateSuiteIds keeps the first and numbers the others', () {
    expect(disambiguateSuiteIds(['a', 'b', 'a', 'a#2', 'a', 'b']), [
      'a',
      'b',
      'a#3',
      'a#2',
      'a#4',
      'b#2',
    ]);
    expect(disambiguateSuiteIds(const []), isEmpty);
  });

  group('runMergeCommand', () {
    late List<messages.Envelope> cart;
    late List<messages.Envelope> search;
    late List<messages.Envelope> fail;

    setUpAll(() async {
      cart = await _run('features/cart.feature', _cart);
      search = await _run('features/search.feature', _search);
      fail = await _run('features/fail.feature', _fail);
    });

    List<String> pickleNames(List<Map<String, Object?>> envelopes) => [
      for (final pickle in ofType(envelopes, 'pickle'))
        pickle['name']! as String,
    ];

    List<Object?> workerIds(List<Map<String, Object?>> envelopes) => [
      for (final started in ofType(envelopes, 'testCaseStarted'))
        started['workerId'],
    ];

    test('merges the parts of two shards, with a repeated suite ID, into '
        'NDJSON and HTML', () async {
      // Both shards ran a suite named cart_test.
      writePart('shard-1/cart_test.ndjson', cart, suiteId: 'cart_test');
      writePart('shard-1/search_test.ndjson', search);
      writePart('shard-2/cart_test.ndjson', cart, suiteId: 'cart_test');

      final code = await merge([
        'shard-1',
        'shard-2',
        '-p',
        'message:merged/messages.ndjson',
        '-p',
        'html:merged/report.html',
      ]);

      expect(code, mergeExitSuccess, reason: '$err');
      expect(out.toString(), isEmpty, reason: 'no summary was asked for');
      expect(
        err.toString(),
        'Note: Suite ID "cart_test" is used by several report parts: '
        '"${path('shard-2/cart_test.ndjson')}" is merged as "cart_test#2".\n',
      );
      final merged = readNdjson(path('merged/messages.ndjson'));
      expect(pickleNames(merged), ['add', 'find'], reason: 'de-duplicated');
      expect(workerIds(merged), ['cart_test', 'search_test', 'cart_test#2']);
      expect(ofType(merged, 'testRunStarted'), hasLength(1));
      expect(merged.last['testRunFinished'], containsPair('success', true));
      expect(readHtmlReport(path('merged/report.html')), merged);
      expect(
        Directory(path('merged')).listSync().map((f) => p.basename(f.path)),
        unorderedEquals(['messages.ndjson', 'report.html']),
      );
    });

    test('exits with 1 when a part failed, and prints the merged '
        'summary', () async {
      writePart('shard-1/cart_test.ndjson', cart);
      writePart('shard-2/fail_test.ndjson', fail);
      final code = await merge([
        'shard-1',
        'shard-2/fail_test.ndjson',
        '-p',
        'summary',
        '-p',
        'message:merged.ndjson',
      ]);
      expect(code, mergeExitFailure, reason: '$err');
      expect(err.toString(), isEmpty);
      expect(
        out.toString(),
        allOf(
          startsWith(
            'Failures:\n\n'
            '1) Scenario: Fail - fail # features/fail.feature:2\n',
          ),
          contains('Bad state: boom'),
          contains('\n2 scenarios (1 failed, 1 passed)\n'),
          contains('\n2 steps (1 failed, 1 passed)\n'),
          matches(RegExp(r'\n\d+m\d\d\.\d{3}s \(executing steps: ')),
        ),
      );
      expect(
        readNdjson(path('merged.ndjson')).last['testRunFinished'],
        containsPair('success', false),
      );
    });

    test('prints the summary by default', () async {
      writePart('run/cart_test.ndjson', cart);
      writePart('run/search_test.ndjson', search);
      expect(await merge(['run']), mergeExitSuccess, reason: '$err');
      expect(out.toString(), startsWith('2 scenarios (2 passed)\n'));
      expect(out.toString(), endsWith(')\n'), reason: 'ends with the duration');
      expect(
        formatSummaryOf(
          mergeReportParts([
            ReportPart('cart_test', cart),
            ReportPart('search_test', search),
          ]),
        ),
        out.toString().trimRight(),
        reason: 'the summary of the merged messages',
      );
    });

    test('exits with 1 when no part finished', () async {
      final unfinished = cart.where((e) => e.testRunFinished == null);
      // Cut in the middle of the last line, as a part still being written.
      File(path('run/cart_test.ndjson'))
        ..parent.createSync()
        ..writeAsStringSync('${_ndjson(unfinished)}{"testRunFin');
      expect(
        await merge(['run', '-p', 'message:merged.ndjson']),
        mergeExitFailure,
      );
      expect(
        err.toString(),
        'Warning: No report part finished, so the merged test run did not '
        'finish.\n',
      );
      expect(
        ofType(readNdjson(path('merged.ndjson')), 'testRunFinished'),
        isEmpty,
      );
    });

    test('skips empty parts with a warning', () async {
      writePart('run/cart_test.ndjson', cart);
      writePart('run/empty.ndjson', const []);
      expect(await merge(['run']), mergeExitSuccess);
      expect(
        err.toString(),
        'Warning: Skipped report part "${path('run/empty.ndjson')}": it has '
        'no messages.\n',
      );
    });

    test('prints the usage for --help', () async {
      expect(await merge(['--help']), mergeExitSuccess);
      expect(
        out.toString(),
        allOf(
          contains('Usage: dart run cucumber:merge [options] <input>...'),
          contains('-p, --plugin=<spec>'),
          contains('message:<path>'),
          contains('Exit codes:'),
        ),
      );
      expect(err.toString(), isEmpty);
    });

    for (final (name, setUpInputs, arguments, message) in [
      ('a usage error', () {}, ['--bogus'], 'Could not find an option named'),
      ('no inputs', () {}, <String>[], 'No inputs.'),
      ('a missing input', () {}, ['missing'], 'Input "missing" not found.'),
      (
        'a part that is not JSON',
        () => File(path('bad.ndjson')).writeAsStringSync('{}\nnot json\n'),
        ['bad.ndjson'],
        'is not NDJSON Cucumber Messages: Failed to parse Envelope on line '
            '2: Unexpected character',
      ),
      (
        'a part that is not Cucumber Messages',
        () => File(path('bad.ndjson')).writeAsStringSync('{"meta": 1}\n'),
        ['bad.ndjson'],
        'is not NDJSON Cucumber Messages: Failed to parse Envelope on line '
            '1: ',
      ),
      (
        'only empty parts',
        () => File(path('empty.ndjson')).writeAsStringSync(''),
        ['empty.ndjson'],
        'No messages in the report parts.',
      ),
      (
        'an output that cannot be written',
        () {
          writePart('run/cart_test.ndjson', cart);
          Directory(path('taken.ndjson')).createSync();
        },
        ['run', '-p', 'message:taken.ndjson'],
        // The path is absolute: "<root>/taken.ndjson".
        '${p.separator}taken.ndjson": ',
      ),
    ]) {
      test('exits with 2 for $name', () async {
        setUpInputs();
        expect(await merge(arguments), mergeExitUsage);
        expect(out.toString(), isEmpty);
        final lines = const LineSplitter().convert(err.toString());
        expect(
          lines.where((l) => l.startsWith('Error: ')).single,
          contains(message),
        );
        expect(lines.last, 'Run "dart run cucumber:merge --help" for usage.');
      });
    }

    test('leaves no temporary file when an output cannot be written', () async {
      writePart('run/cart_test.ndjson', cart);
      Directory(path('taken.ndjson')).createSync();
      await merge(['run', '-p', 'message:taken.ndjson']);
      expect(
        root.listSync().map((e) => p.basename(e.path)),
        unorderedEquals(['run', 'taken.ndjson']),
      );
    });
  });
}
