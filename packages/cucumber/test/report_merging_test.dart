import 'dart:convert';
import 'dart:io';

import 'package:cucumber/cucumber.dart';
import 'package:cucumber/src/plugins.dart';
import 'package:cucumber/src/report_merging.dart';
import 'package:cucumber_core/engine.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:path/path.dart' as p;
import 'package:stack_trace/stack_trace.dart';
import 'package:test/test.dart';

import 'support/dart_test_runner.dart' show readHtmlReport, readNdjson;

const _cart = 'Feature: Cart\n  Scenario: add\n    Given a step passes\n';
const _search = 'Feature: Search\n  Scenario: find\n    Given a step passes\n';
const _fail = 'Feature: Fail\n  Scenario: fail\n    Given a step fails\n';

final _glue = <Glue>[
  Given('a step passes', () {}),
  Given('a step fails', () => throw StateError('boom')),
];

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cucumber_report_merging_');
  });
  tearDown(() => root.deleteSync(recursive: true));

  String path(String relative) =>
      p.joinAll([root.path, ...relative.split('/')]);

  ReportMerging merging(String suiteId, {String runId = 'run'}) =>
      ReportMerging(
        outputDirectory: path('build'),
        runId: runId,
        suiteId: suiteId,
      );

  /// Runs [source] as the suite [suiteId] of [runId] with the plugin
  /// specifications [specs], as `dart test` does.
  Future<List<Plugin>> runSuite(
    String suiteId,
    String uri,
    String source, {
    List<Object> specs = const [
      'message:build/cucumber/messages.ndjson',
      'html:build/cucumber/report.html',
    ],
    String runId = 'run',
  }) async {
    final plugins = createPlugins(
      specs,
      packageRoot: root.path,
      merging: merging(suiteId, runId: runId),
    );
    final plan = SuitePlan.create(
      features: [FeatureSource(uri, source)],
      glue: _glue,
      plugins: plugins,
    );
    await const SerialHost().run(plan);
    return plugins;
  }

  List<String> pickleNames(List<Map<String, Object?>> envelopes) => [
    for (final e in envelopes)
      if (e['pickle'] case final Map<String, Object?> pickle)
        pickle['name']! as String,
  ];

  List<Object?> workerIds(List<Map<String, Object?>> envelopes) => [
    for (final e in envelopes)
      if (e['testCaseStarted'] case final Map<String, Object?> started)
        started['workerId'],
  ];

  group('MergedReportPlugin', () {
    test('writes a part and rewrites the outputs from every part of the '
        'run', () async {
      await runSuite('cart', 'features/cart.feature', _cart);
      final ndjson = path('build/cucumber/messages.ndjson');
      final html = path('build/cucumber/report.html');
      expect(pickleNames(readNdjson(ndjson)), ['add']);

      await runSuite('search', 'features/search.feature', _search);
      final merged = readNdjson(ndjson);
      expect(pickleNames(merged), ['add', 'find']);
      expect(workerIds(merged), ['cart', 'search']);
      expect(readHtmlReport(html), merged);
      expect(
        [for (final e in merged) e.keys.single].where(
          (t) => t == 'testRunStarted' || t == 'testRunFinished' || t == 'meta',
        ),
        ['meta', 'testRunStarted', 'testRunFinished'],
      );

      final parts = path('build/.cucumber/parts/run');
      expect(
        Directory(parts).listSync().map((f) => p.basename(f.path)).toList()
          ..sort(),
        ['cart.json', 'cart.ndjson', 'search.json', 'search.ndjson'],
      );
      expect(jsonDecode(File(p.join(parts, 'cart.json')).readAsStringSync()), {
        'suiteId': 'cart',
        'outputs': [
          'message:${p.canonicalize(ndjson)}',
          'html:${p.canonicalize(html)}',
        ],
      });
      expect(
        pickleNames(readNdjson(p.join(parts, 'cart.ndjson'))),
        ['add'],
        reason: 'the part holds only its suite',
      );
      expect(File(path('build/.cucumber/merge.lock')).existsSync(), isTrue);
    });

    test('succeeds only if every suite succeeded', () async {
      await runSuite('cart', 'features/cart.feature', _cart);
      Object? success() =>
          (readNdjson(
                path('build/cucumber/messages.ndjson'),
              ).last['testRunFinished']!
              as Map<String, Object?>)['success'];
      expect(success(), isTrue);
      await runSuite('fail', 'features/fail.feature', _fail);
      expect(success(), isFalse);
    });

    test('merges each output from the suites that configure it', () async {
      await runSuite('cart', 'features/cart.feature', _cart);
      await runSuite(
        'search',
        'features/search.feature',
        _search,
        specs: ['message:build/cucumber/other.ndjson'],
      );
      await runSuite(
        'fail',
        'features/fail.feature',
        _fail,
        specs: [
          'message:build/cucumber/messages.ndjson',
          'message:build/cucumber/other.ndjson',
        ],
      );
      expect(pickleNames(readNdjson(path('build/cucumber/messages.ndjson'))), [
        'add',
        'fail',
      ]);
      expect(pickleNames(readNdjson(path('build/cucumber/other.ndjson'))), [
        'fail',
        'find',
      ]);
      expect(pickleNames(readHtmlReport(path('build/cucumber/report.html'))), [
        'add',
      ]);
    });

    test('does not merge parts of other runs', () async {
      await runSuite('cart', 'features/cart.feature', _cart, runId: 'one');
      await runSuite('search', 'features/search.feature', _search);
      expect(pickleNames(readNdjson(path('build/cucumber/messages.ndjson'))), [
        'find',
      ]);
      expect(Directory(path('build/.cucumber/parts/one')).existsSync(), isTrue);
    });

    test('gives a part whose suite ID is taken the next free ID', () async {
      final first = await runSuite('cart', 'features/cart.feature', _cart);
      final second = await runSuite('cart', 'features/search.feature', _search);
      expect((first.single as MergedReportPlugin).suiteId, 'cart');
      expect((second.single as MergedReportPlugin).suiteId, 'cart#2');
      final merged = readNdjson(path('build/cucumber/messages.ndjson'));
      expect(workerIds(merged), ['cart', 'cart#2']);
      expect(
        File(path('build/.cucumber/parts/run/cart%232.ndjson')).existsSync(),
        isTrue,
      );
    });

    test('a suite that never starts writes and merges nothing', () async {
      final plugins = createPlugins(
        ['message:build/cucumber/messages.ndjson'],
        packageRoot: root.path,
        merging: merging('cart'),
      );
      final plan = SuitePlan.create(
        features: const [FeatureSource('features/cart.feature', _cart)],
        glue: _glue,
        plugins: plugins,
      );
      await plan.finish();
      expect(Directory(path('build')).existsSync(), isFalse);
    });

    test('merges a part that is still being written as unfinished', () async {
      await runSuite('cart', 'features/cart.feature', _cart);
      // Another suite has started: its manifest exists and its part ends in
      // the middle of a line.
      final collector = CollectingPlugin();
      final plan = SuitePlan.create(
        features: const [FeatureSource('features/search.feature', _search)],
        glue: _glue,
        plugins: [collector],
      );
      await plan.start();
      final layout = merging('search');
      final lines = [
        for (final e in collector.envelopes) messages.envelopeToJsonString(e),
      ];
      File(
        layout.partPath('search'),
      ).writeAsStringSync('${lines.join('\n')}\n{"testCase":');
      File(layout.manifestPath('search')).writeAsStringSync(
        jsonEncode({
          'suiteId': 'search',
          'outputs': [
            ReportOutput(
              ReportFormat.message,
              path('build/cucumber/messages.ndjson'),
            ).key,
          ],
        }),
      );
      expect(readReportPart(layout.partPath('search')), collector.envelopes);

      await runSuite('fail', 'features/fail.feature', _fail);
      final merged = readNdjson(path('build/cucumber/messages.ndjson'));
      expect(pickleNames(merged), ['add', 'fail', 'find']);
      final finished = merged.last['testRunFinished']! as Map<String, Object?>;
      expect(finished['success'], isFalse);
      expect(finished['message'], contains('"search" did not finish'));
    });
  });

  group('pruneReportParts', () {
    final old = DateTime.now().subtract(const Duration(hours: 2));

    /// Creates the file [relative] (below `build/.cucumber/parts/`),
    /// modified at [modified] (default: now).
    String file(String relative, {DateTime? modified}) {
      final file = File(path('build/.cucumber/parts/$relative'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{}\n');
      if (modified != null) file.setLastModifiedSync(modified);
      return file.path;
    }

    String run(String runId) => path('build/.cucumber/parts/$runId');

    test('deletes the runs that have not changed for an hour, except the '
        'current one', () {
      file('current/cart.ndjson', modified: old);
      file('stale/cart.ndjson', modified: old);
      file('stale/cart.json', modified: old);
      // In progress: a suite is still writing its part.
      file('running/cart.ndjson', modified: old);
      file('running/search.ndjson');
      file('recent/cart.ndjson', modified: DateTime.now());
      // Just created by a suite that has not created its part yet.
      Directory(run('starting')).createSync();
      file('stray.ndjson', modified: old);

      final deleted = pruneReportParts(merging('cart', runId: 'current'));

      expect(deleted, [run('stale')]);
      expect(
        Directory(
          path('build/.cucumber/parts'),
        ).listSync().map((e) => p.basename(e.path)),
        unorderedEquals([
          'current',
          'running',
          'recent',
          'starting',
          'stray.ndjson',
        ]),
      );
    });

    test('compares the current run by its directory name', () {
      file('${fileNameOf('ci/42')}/cart.ndjson', modified: old);
      expect(pruneReportParts(merging('cart', runId: 'ci/42')), isEmpty);
    });

    test('takes the retention and the time', () {
      file('a/cart.ndjson', modified: old);
      final layout = merging('cart', runId: 'current');
      expect(
        pruneReportParts(layout, retention: const Duration(hours: 3)),
        isEmpty,
      );
      expect(
        pruneReportParts(layout, now: old.add(const Duration(minutes: 59))),
        isEmpty,
      );
      expect(
        pruneReportParts(layout, now: old.add(const Duration(minutes: 61))),
        [run('a')],
      );
    });

    test('does nothing without parts', () {
      expect(pruneReportParts(merging('cart')), isEmpty);
    });

    test('never throws, and keeps what it cannot delete', () {
      final part = file('locked/cart.ndjson', modified: old);
      final handle = File(part).openSync(mode: FileMode.append);
      if (!Platform.isWindows) {
        // Read-only: its entries cannot be deleted (except by root).
        Process.runSync('chmod', ['555', run('locked')]);
      }
      try {
        final deleted = pruneReportParts(merging('cart', runId: 'current'));
        expect(
          Directory(run('locked')).existsSync(),
          !deleted.contains(run('locked')),
        );
      } finally {
        handle.closeSync();
        if (!Platform.isWindows) {
          Process.runSync('chmod', ['755', run('locked')]);
        }
      }
    });

    test('runs after the automatic merge', () async {
      file('stale/cart.ndjson', modified: old);
      file('recent/cart.ndjson');
      await runSuite('cart', 'features/cart.feature', _cart);
      expect(
        Directory(
          path('build/.cucumber/parts'),
        ).listSync().map((e) => p.basename(e.path)),
        unorderedEquals(['run', 'recent']),
      );
      expect(pickleNames(readNdjson(path('build/cucumber/messages.ndjson'))), [
        'add',
      ]);
    });
  });

  group('createPlugins with merging', () {
    test('turns message: and html: into the outputs of one merged report '
        'plugin, added last', () {
      final custom = CollectingPlugin();
      final direct = NdjsonPlugin(path('direct.ndjson'));
      final plugins = createPlugins(
        [
          'message:build/a.ndjson',
          'summary',
          custom,
          'html:build/a.html',
          direct,
          'message: build/a.ndjson ',
        ],
        packageRoot: root.path,
        merging: merging('cart'),
      );
      expect(plugins, hasLength(4));
      expect(plugins[0], isA<SummaryPlugin>());
      expect(plugins[1], same(custom));
      expect(plugins[2], same(direct), reason: 'instances are not merged');
      final merged = plugins[3] as MergedReportPlugin;
      expect(merged.outputs.map((o) => '$o'), [
        'message:${path('build/a.ndjson')}',
        'html:${path('build/a.html')}',
      ]);
    });

    test('adds no merged report plugin without outputs', () {
      expect(
        createPlugins(
          ['summary'],
          packageRoot: root.path,
          merging: merging('cart'),
        ),
        [isA<SummaryPlugin>()],
      );
    });
  });

  group('report part files', () {
    test('readReportPart leaves out an incomplete last line', () {
      final file = File(path('part.ndjson'));
      expect(readReportPart(file.path), isEmpty, reason: 'missing');
      const meta = messages.Envelope(
        meta: messages.Meta(
          protocolVersion: '1',
          implementation: messages.Product(name: 'x'),
          runtime: messages.Product(name: 'x'),
          os: messages.Product(name: 'x'),
          cpu: messages.Product(name: 'x'),
        ),
      );
      final line = messages.envelopeToJsonString(meta);
      file.writeAsStringSync(line);
      expect(readReportPart(file.path), isEmpty);
      // A multi-byte character cut in the middle.
      file.writeAsBytesSync([
        ...utf8.encode('$line\n\n'),
        ...utf8.encode('{"x": "é').take(8),
      ]);
      expect(readReportPart(file.path), [meta]);
    });

    test('fileNameOf keeps portable characters and encodes the rest', () {
      expect(fileNameOf('cucumber_test'), 'cucumber_test');
      expect(fileNameOf('checkout/cart_test'), 'checkout%2Fcart_test');
      expect(fileNameOf('a.b-c'), 'a.b-c');
      expect(fileNameOf('.hidden'), '%2Ehidden');
      expect(fileNameOf('a b#2*'), 'a%20b%232%2A');
      expect(fileNameOf('é'), '%C3%A9');
      expect(fileNameOf(''), '%');
    });

    test('ReportMerging lays out the parts below .cucumber', () {
      final layout = ReportMerging(
        outputDirectory: path('build'),
        runId: '1234',
        suiteId: 'checkout/cart_test',
      );
      expect(layout.lockPath, path('build/.cucumber/merge.lock'));
      expect(layout.partsDirectory, path('build/.cucumber/parts/1234'));
      expect(
        layout.partPath(layout.suiteId),
        path('build/.cucumber/parts/1234/checkout%2Fcart_test.ndjson'),
      );
      expect(
        layout.manifestPath(layout.suiteId),
        path('build/.cucumber/parts/1234/checkout%2Fcart_test.json'),
      );
    });
  });

  group('run and suite IDs', () {
    test('resolveRunId takes CUCUMBER_RUN_ID, else the process ID', () {
      expect(resolveRunId({'CUCUMBER_RUN_ID': ' ci-42 '}), 'ci-42');
      expect(resolveRunId({'CUCUMBER_RUN_ID': ' '}, processId: 7), '7');
      expect(resolveRunId(const {}, processId: 7), '7');
      expect(resolveRunId(const {}), '$pid');
    });

    test('testFileSuiteId names the test file whose main declares the '
        'suite', () {
      final packageRoot = p.join(root.path, 'pkg');
      Uri file(String relative) =>
          p.toUri(p.join(packageRoot, p.joinAll(relative.split('/'))));
      Trace trace(List<(Uri, String)> frames) =>
          Trace([for (final (uri, member) in frames) Frame(uri, 1, 1, member)]);
      final declare = (
        Uri.parse('package:cucumber/src/suite.dart'),
        'CucumberSuite.declare',
      );
      final runner = (
        Uri.parse('package:test_api/src/backend/declarer.dart'),
        'Declarer.declare',
      );

      expect(
        testFileSuiteId(
          packageRoot,
          trace: trace([
            declare,
            (file('test/cucumber_test.dart'), 'main'),
            runner,
          ]),
        ),
        'cucumber_test',
      );
      expect(
        testFileSuiteId(
          packageRoot,
          trace: trace([
            declare,
            (file('test/support/suites.dart'), 'runShop'),
            (file('test/checkout/cart_test.dart'), 'main.<fn>'),
            (Uri.parse('package:test_core/src/scaffolding.dart'), 'group'),
            (file('test/checkout/cart_test.dart'), 'main'),
            runner,
          ]),
        ),
        'checkout/cart_test',
      );
      expect(
        testFileSuiteId(
          packageRoot,
          trace: trace([declare, (file('tool/run.dart'), 'main')]),
        ),
        'tool/run',
      );
      expect(
        testFileSuiteId(
          packageRoot,
          trace: trace([declare, (file('test/helper.dart'), 'helper')]),
        ),
        'helper',
        reason: 'without main, the outermost file',
      );
      expect(testFileSuiteId(packageRoot, trace: trace([declare])), 'suite');
    });
  });
}
