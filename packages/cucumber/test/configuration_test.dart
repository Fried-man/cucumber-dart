import 'dart:io';

import 'package:cucumber/cucumber.dart';
import 'package:cucumber/src/configuration.dart';
import 'package:cucumber_core/engine.dart' show PickleOrder, RandomOrder;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cucumber_config_');
  });
  tearDown(() => root.deleteSync(recursive: true));

  void writeConfig(String yaml, [String name = 'cucumber.yaml']) =>
      File(p.join(root.path, name)).writeAsStringSync(yaml);

  ResolvedConfiguration resolve(
    CucumberOptions code, [
    Map<String, String> environment = const {},
  ]) => resolveConfiguration(
    code,
    packageRoot: root.path,
    environment: environment,
  );

  Matcher throwsConfig(Object message) => throwsA(
    isA<CucumberConfigurationException>().having(
      (e) => e.message,
      'message',
      message,
    ),
  );

  group('defaults', () {
    test('apply when nothing is set', () {
      final config = resolve(CucumberOptions());
      expect(config.features, ['features/']);
      expect(config.tags, isNull);
      expect(config.names, isEmpty);
      expect(config.retry, 0);
      expect(config.order, PickleOrder.defined);
      expect(config.dryRun, isFalse);
      expect(config.worldParameters, isEmpty);
      expect(config.plugins, isEmpty);
      expect(config.profiles, isEmpty);
      expect(config.mapTags, isTrue);
      expect(config.scenarioTimeout, isNull);
    });

    test('are overridden by code', () {
      final config = resolve(
        CucumberOptions(
          features: ['specs/'],
          tags: '@a',
          names: ['x'],
          retry: 2,
          order: 'random:42',
          dryRun: true,
          worldParameters: {'a': 1},
          plugins: ['message:out.ndjson'],
          mapTags: false,
          scenarioTimeout: const Timeout(Duration(seconds: 3)),
        ),
      );
      expect(config.features, ['specs/']);
      expect(config.tags, '@a');
      expect(config.names, ['x']);
      expect(config.retry, 2);
      expect(
        config.order,
        isA<RandomOrder>().having((o) => o.seed, 'seed', 42),
      );
      expect(config.dryRun, isTrue);
      expect(config.worldParameters, {'a': 1});
      expect(config.plugins, ['message:out.ndjson']);
      expect(config.mapTags, isFalse);
      expect(config.scenarioTimeout, const Timeout(Duration(seconds: 3)));

      final run = config.toRunOptions(
        lines: {
          'a.feature': {3},
        },
      );
      expect(run.tags, '@a');
      expect(run.retry, 2);
      expect(run.dryRun, isTrue);
      expect(run.lines, {
        'a.feature': {3},
      });
    });
  });

  group('cucumber.yaml', () {
    test('the default profile applies when no profile is named', () {
      writeConfig('''
default:
  features: [specs/]
  tags: not @wip
  retry: 1
ci:
  retry: 3
''');
      final config = resolve(CucumberOptions(retry: 0, tags: '@fast'));
      expect(config.profiles, ['default']);
      expect(config.features, ['specs/']);
      expect(config.retry, 1, reason: 'profiles override code');
      expect(config.tags, '(@fast) and (not @wip)');
    });

    test('profiles named in code apply in order', () {
      writeConfig('''
default:
  retry: 9
ci:
  retry: 2
  tags: not @slow
  plugins: message:ci.ndjson
nightly:
  tags: '@nightly'
  order: reverse
''');
      final config = resolve(CucumberOptions(profile: 'ci, nightly'));
      expect(config.profiles, ['ci', 'nightly']);
      expect(config.retry, 2, reason: 'default is not applied');
      expect(config.tags, '(not @slow) and (@nightly)');
      expect(config.plugins, ['message:ci.ndjson']);
      expect(config.order, PickleOrder.reverse);
    });

    test('CUCUMBER_PROFILE wins over the profile in code', () {
      writeConfig('''
a:
  retry: 1
b:
  retry: 2
''');
      expect(
        resolve(CucumberOptions(profile: 'a'), {'CUCUMBER_PROFILE': 'b'}).retry,
        2,
      );
      expect(
        resolve(CucumberOptions(profile: 'a'), {'CUCUMBER_PROFILE': ' '}).retry,
        1,
        reason: 'blank variables are ignored',
      );
    });

    test('reads every option', () {
      writeConfig('''
default:
  features:
    - a/
    - b.feature:3
  tags: '@x'
  names: [one, two]
  retry: 4
  order: random
  dryRun: true
  worldParameters:
    url: http://localhost
    nested: {list: [1, 2]}
  plugins: [message:out.ndjson]
  suiteName: suite
  mapTags: false
  scenarioTimeout: 2m
''');
      final config = resolve(CucumberOptions());
      expect(config.features, ['a/', 'b.feature:3']);
      expect(config.tags, '@x');
      expect(config.names, ['one', 'two']);
      expect(config.retry, 4);
      expect(config.order, isA<RandomOrder>());
      expect(config.dryRun, isTrue);
      expect(config.worldParameters, {
        'url': 'http://localhost',
        'nested': {
          'list': [1, 2],
        },
      });
      expect(config.worldParameters['nested'], isA<Map<String, Object?>>());
      expect(config.plugins, ['message:out.ndjson']);
      expect(config.suiteName, 'suite');
      expect(config.mapTags, isFalse);
      expect(config.scenarioTimeout, const Timeout(Duration(minutes: 2)));
    });

    test('cucumber.yml is also read', () {
      writeConfig('default:\n  retry: 5\n', 'cucumber.yml');
      expect(resolve(CucumberOptions()).retry, 5);
    });

    test('an empty file or profile is fine', () {
      writeConfig('');
      expect(resolve(CucumberOptions()).profiles, isEmpty);
      writeConfig('default:\n');
      expect(resolve(CucumberOptions()).profiles, ['default']);
    });

    test('rejects unknown profiles', () {
      writeConfig('default:\n  retry: 1\nci:\n  retry: 2\n');
      expect(
        () => resolve(CucumberOptions(profile: 'nope')),
        throwsConfig(
          allOf(
            contains('Profile "nope" is not defined in cucumber.yaml'),
            contains('default, ci'),
          ),
        ),
      );
    });

    test('rejects a profile when there is no file', () {
      expect(
        () => resolve(CucumberOptions(), {'CUCUMBER_PROFILE': 'ci'}),
        throwsConfig(contains('requested by CUCUMBER_PROFILE')),
      );
    });

    test('rejects invalid files and options', () {
      void rejects(String yaml, Object message) {
        writeConfig(yaml);
        expect(() => resolve(CucumberOptions()), throwsConfig(message));
      }

      rejects('default: [', contains('not valid YAML'));
      rejects('- a', contains('must map profile names to options'));
      rejects('default: 3', contains('must be a map of options'));
      rejects('default:\n  glue: x', contains('can only be set in code'));
      rejects('default:\n  world: x', contains('can only be set in code'));
      rejects('default:\n  profile: x', contains('cannot select'));
      rejects('default:\n  retyr: 1', contains('unknown option'));
      rejects('default:\n  retry: x', contains('retry: expected an integer'));
      rejects('default:\n  dryRun: 1', contains('expected true or false'));
      rejects('default:\n  features: {a: 1}', contains('list of strings'));
      rejects('default:\n  names: [1]', contains('expected strings'));
      rejects('default:\n  worldParameters: 1', contains('expected a map'));
      rejects('default:\n  scenarioTimeout: soon', contains('duration'));
      rejects('default:\n  order: sideways', contains('Invalid order'));
      rejects('default:\n  retry: -1', contains('must not be negative'));
    });
  });

  group('CUCUMBER_* environment variables', () {
    test('override code and profiles', () {
      writeConfig('''
default:
  features: [specs/]
  tags: not @wip
  plugins: [message:yaml.ndjson]
  worldParameters: {a: yaml, b: yaml}
''');
      final config = resolve(
        CucumberOptions(
          tags: '@fast',
          retry: 1,
          worldParameters: {'a': 'code', 'c': 'code'},
        ),
        {
          'CUCUMBER_FEATURES': 'x/, y.feature:3:7 ,',
          'CUCUMBER_FILTER_TAGS': 'not @slow',
          'CUCUMBER_FILTER_NAME': r'^Pay, (with|without)',
          'CUCUMBER_PLUGIN': 'message:a.ndjson,message:b.ndjson',
          'CUCUMBER_EXECUTION_DRY_RUN': 'TRUE',
          'CUCUMBER_EXECUTION_ORDER': 'random:7',
          'CUCUMBER_EXECUTION_RETRY': '3',
          'CUCUMBER_WORLD_PARAMETERS': '{"b": "env", "d": [1]}',
          'UNRELATED': 'x',
        },
      );
      expect(config.features, ['x/', 'y.feature:3:7']);
      expect(config.tags, '((@fast) and (not @wip)) and (not @slow)');
      expect(config.names, [r'^Pay, (with|without)']);
      expect(config.plugins, ['message:a.ndjson', 'message:b.ndjson']);
      expect(config.dryRun, isTrue);
      expect(config.order, isA<RandomOrder>().having((o) => o.seed, 'seed', 7));
      expect(config.retry, 3);
      expect(config.worldParameters, {
        'a': 'yaml',
        'c': 'code',
        'b': 'env',
        'd': [1],
      });
    });

    test('replace plugin specifications but keep plugin instances', () {
      writeConfig('default:\n  plugins: [message:yaml.ndjson]\n');
      final custom = CollectingPlugin();
      final code = CucumberOptions(plugins: ['message:code.ndjson', custom]);
      expect(resolve(code).plugins, [custom, 'message:yaml.ndjson']);
      expect(resolve(code, {'CUCUMBER_PLUGIN': 'message:env.ndjson'}).plugins, [
        custom,
        'message:env.ndjson',
      ]);
      File(p.join(root.path, 'cucumber.yaml')).deleteSync();
      expect(resolve(code).plugins, ['message:code.ndjson', custom]);
    });

    test('blank variables are ignored', () {
      final config = resolve(CucumberOptions(retry: 2, tags: '@a'), {
        'CUCUMBER_EXECUTION_RETRY': '',
        'CUCUMBER_FILTER_TAGS': '  ',
        'CUCUMBER_FEATURES': '',
      });
      expect(config.retry, 2);
      expect(config.tags, '@a');
      expect(config.features, ['features/']);
    });

    test('reject invalid values', () {
      void rejects(String name, String value, Object message) => expect(
        () => resolve(CucumberOptions(), {name: value}),
        throwsConfig(message),
        reason: '$name=$value',
      );

      rejects('CUCUMBER_EXECUTION_DRY_RUN', 'yes', contains('true or false'));
      rejects('CUCUMBER_EXECUTION_RETRY', 'two', contains('integer'));
      rejects('CUCUMBER_EXECUTION_RETRY', '-1', contains('negative'));
      rejects('CUCUMBER_EXECUTION_ORDER', 'random:x', contains('order'));
      rejects('CUCUMBER_WORLD_PARAMETERS', '{', contains('not valid JSON'));
      rejects('CUCUMBER_WORLD_PARAMETERS', '[1]', contains('JSON object'));
    });
  });

  test('ConfigurationFile lists its profiles', () {
    final file = ConfigurationFile.parse('a:\nb:\n  retry: 1\n');
    expect(file.profileNames, ['a', 'b']);
    expect(file.hasProfile('b'), isTrue);
    expect(file.profile('b').retry, 1);
    expect(file.profile('a').retry, isNull);
  });
}
