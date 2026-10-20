import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:cucumber/cucumber.dart';
import 'package:cucumber/src/configuration.dart';
import 'package:cucumber/src/platform.dart';
import 'package:cucumber/src/plugins.dart';
import 'package:cucumber_core/engine.dart';
import 'package:cucumber_html_formatter/cucumber_html_formatter.dart'
    show mainJs;
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cucumber_plugins_');
  });
  tearDown(() => root.deleteSync(recursive: true));

  group('createPlugins', () {
    test('creates NDJSON plugins relative to the package root', () {
      final custom = CollectingPlugin();
      final plugins = createPlugins([
        'message:build/out.ndjson',
        ' message: other.ndjson ',
        custom,
      ], packageRoot: root.path);
      expect(plugins, hasLength(3));
      expect(
        (plugins[0] as NdjsonPlugin).path,
        p.join(root.path, 'build', 'out.ndjson'),
      );
      expect(
        (plugins[1] as NdjsonPlugin).path,
        p.join(root.path, 'other.ndjson'),
      );
      expect(plugins[2], same(custom));
    });

    test('creates HTML plugins relative to the package root', () {
      final plugins = createPlugins([
        'html:build/report.html',
        ' html: ../other.html ',
      ], packageRoot: root.path);
      expect(plugins, everyElement(isA<HtmlPlugin>()));
      expect(
        (plugins[0] as HtmlPlugin).path,
        p.join(root.path, 'build', 'report.html'),
      );
      expect(
        (plugins[1] as HtmlPlugin).path,
        p.normalize(p.join(root.path, '..', 'other.html')),
      );
      expect(
        plugins[0].toString(),
        'html:${p.join(root.path, 'build', 'report.html')}',
      );
    });

    test('takes html from code, cucumber.yaml and CUCUMBER_PLUGIN', () {
      List<String> plugins(
        CucumberOptions code, [
        Map<String, String> environment = const {},
      ]) => [
        for (final plugin in createPlugins(
          resolveConfiguration(
            code,
            packageRoot: root.path,
            environment: environment,
          ).plugins,
          packageRoot: root.path,
        ))
          '$plugin',
      ];
      String html(String file) => 'html:${p.join(root.path, file)}';

      expect(plugins(CucumberOptions(plugins: ['html:code.html'])), [
        html('code.html'),
      ]);
      File(
        p.join(root.path, 'cucumber.yaml'),
      ).writeAsStringSync('default:\n  plugins:\n    - html:yaml.html\n');
      expect(plugins(CucumberOptions()), [html('yaml.html')]);
      expect(
        plugins(CucumberOptions(), {
          'CUCUMBER_PLUGIN': 'html:env.html,summary',
        }),
        [html('env.html'), 'summary'],
      );
    });

    test('creates the summary plugin', () {
      final plugins = createPlugins([
        'summary',
        ' summary ',
      ], packageRoot: root.path);
      expect(plugins, everyElement(isA<SummaryPlugin>()));
      expect(plugins, hasLength(2));
    });

    test('takes summary from code, cucumber.yaml and CUCUMBER_PLUGIN', () {
      List<Plugin> plugins(
        CucumberOptions code, [
        Map<String, String> environment = const {},
      ]) => createPlugins(
        resolveConfiguration(
          code,
          packageRoot: root.path,
          environment: environment,
        ).plugins,
        packageRoot: root.path,
      );
      String describe(List<Plugin> plugins) => plugins.join(', ');

      expect(
        describe(plugins(CucumberOptions(plugins: ['summary']))),
        'summary',
      );
      File(
        p.join(root.path, 'cucumber.yaml'),
      ).writeAsStringSync('default:\n  plugins:\n    - summary\n');
      expect(describe(plugins(CucumberOptions())), 'summary');
      expect(
        describe(
          plugins(CucumberOptions(), {
            'CUCUMBER_PLUGIN': 'summary,message:out.ndjson',
          }),
        ),
        'summary, message:${p.join(root.path, 'out.ndjson')}',
      );
    });

    test('rejects unknown plugins', () {
      Matcher rejects(Object message) => throwsA(
        isA<CucumberConfigurationException>().having(
          (e) => e.message,
          'message',
          message,
        ),
      );
      List<Plugin> create(Object spec) =>
          createPlugins([spec], packageRoot: root.path);

      expect(() => create('message'), rejects(contains('needs an output')));
      expect(() => create('message:'), rejects(contains('needs an output')));
      expect(
        () => create('html'),
        rejects(contains('needs an output file: html:<path>')),
      );
      expect(() => create('html: '), rejects(contains('needs an output')));
      expect(() => create('summary:x'), rejects(contains('no argument')));
      expect(
        () => create('junit:r.xml'),
        rejects(
          allOf(
            contains('Unknown plugin'),
            contains('message:<path>, html:<path>, summary'),
          ),
        ),
      );
      expect(() => create(42), rejects(contains('int')));
    });
  });

  group('NdjsonPlugin', () {
    test('writes one message per line', () async {
      final path = p.join(root.path, 'deep', 'dir', 'messages.ndjson');
      final plan = SuitePlan.create(
        features: [
          const FeatureSource(
            'features/a.feature',
            'Feature: a\n  Scenario: s\n    Given a step\n',
          ),
        ],
        glue: [Given('a step', () {})],
        plugins: [NdjsonPlugin(path)],
      );
      expect(File(path).existsSync(), isFalse);
      await const SerialHost().run(plan);
      final types = [
        for (final line in File(path).readAsLinesSync())
          (jsonDecode(line) as Map<String, Object?>).keys.single,
      ];
      expect(types.first, 'meta');
      expect(types, contains('testCase'));
      expect(types.last, 'testRunFinished');
    });

    test('writes nothing when the run never starts', () async {
      final path = p.join(root.path, 'messages.ndjson');
      final plan = SuitePlan.create(
        features: const [],
        glue: const [],
        plugins: [NdjsonPlugin(path)],
      );
      await plan.finish();
      expect(File(path).existsSync(), isFalse);
    });
  });

  group('HtmlPlugin', () {
    test('writes the messages into the HTML report', () async {
      final path = p.join(root.path, 'deep', 'dir', 'report.html');
      final collector = CollectingPlugin();
      final plugin = HtmlPlugin(path);
      final plan = SuitePlan.create(
        features: [
          const FeatureSource(
            'features/a.feature',
            'Feature: a\n  Scenario: <b>s</b>\n    Given a step\n',
          ),
        ],
        glue: [Given('a step', () {})],
        plugins: [plugin, collector],
      );
      expect(File(path).existsSync(), isFalse);
      await const SerialHost().run(plan);

      final html = File(path).readAsStringSync();
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('<title>Cucumber</title>'));
      expect(html, contains(mainJs));
      expect(html, endsWith('</html>\n'));

      const start = 'window.CUCUMBER_MESSAGES = [';
      final messagesText = html.substring(
        html.indexOf(start) + start.length,
        html.indexOf('];\n</script>'),
      );
      expect(messagesText, contains(r'\x3Cb>s\x3C/b>'));
      expect(messagesText, isNot(contains('<')));
      final embedded =
          jsonDecode('[${messagesText.replaceAll(r'\x3C', r'\u003C')}]')
              as List<Object?>;
      expect(embedded, [
        for (final envelope in collector.envelopes)
          jsonDecode(messages.envelopeToJsonString(envelope)),
      ]);

      await plugin.close();
      expect(File(path).readAsStringSync(), html, reason: 'closed once');
    });

    test('writes nothing when the run never starts', () async {
      final path = p.join(root.path, 'report.html');
      final plan = SuitePlan.create(
        features: const [
          FeatureSource('features/a.feature', 'Feature: a\n  Scenario: s\n'),
        ],
        glue: const [],
        plugins: [HtmlPlugin(path)],
      );
      await plan.finish();
      expect(File(path).existsSync(), isFalse);
    });
  });

  group('IoCucumberPlatform', () {
    test('describes the Dart VM in meta', () {
      final meta = IoCucumberPlatform().meta();
      expect(meta.runtime.name, 'Dart');
      expect(meta.runtime.version, matches(RegExp(r'^\d+\.\d+\.\d+')));
      expect(meta.os.name, Platform.operatingSystem);
      expect(meta.os.version, Platform.operatingSystemVersion);
      expect(meta.cpu.name, isNot(contains('_')));
      expect(meta.implementation.name, 'cucumber-dart');
      expect(meta.protocolVersion, protocolVersion);
    });

    test('detects the CI environment for meta.ci', () {
      final ci = IoCucumberPlatform(
        environment: {
          'GITHUB_SERVER_URL': 'https://github.com',
          'GITHUB_REPOSITORY': 'owner/repo',
          'GITHUB_RUN_ID': '42',
          'GITHUB_SHA': 'cafebabe',
          'GITHUB_EVENT_NAME': 'push',
          'GITHUB_REF': 'refs/tags/v1.0.0',
        },
      ).meta().ci;
      expect(ci?.toJson(), {
        'name': 'GitHub Actions',
        'url': 'https://github.com/owner/repo/actions/runs/42',
        'buildNumber': '42',
        'git': {
          'remote': 'https://github.com/owner/repo.git',
          'revision': 'cafebabe',
          'tag': 'v1.0.0',
        },
      });
      expect(IoCucumberPlatform(environment: const {}).meta().ci, isNull);
    });

    test('reads the environment', () {
      expect(IoCucumberPlatform(environment: {'A': 'b'}).environment, {
        'A': 'b',
      });
      expect(IoCucumberPlatform().environment, Platform.environment);
    });

    test('dartVersion takes the version number', () {
      expect(
        dartVersion('3.8.0 (stable) (Tue May 26 2026) on "linux_x64"'),
        '3.8.0',
      );
      expect(dartVersion('3.9.0-1.0.dev'), '3.9.0-1.0.dev');
    });

    test('cpuArchitecture takes the architecture of the ABI', () {
      expect(cpuArchitecture(Abi.linuxX64), 'x64');
      expect(cpuArchitecture(Abi.macosArm64), 'arm64');
      expect(cpuArchitecture(Abi.windowsIA32), 'ia32');
    });
  });
}
