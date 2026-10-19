import 'package:cucumber/cucumber.dart';
import 'package:cucumber/src/options.dart' show andTags;
import 'package:test/test.dart';

class _World {}

void main() {
  group('CucumberOptions', () {
    test('copies lists and maps into unmodifiable ones', () {
      final features = ['features/'];
      final parameters = <String, Object?>{'a': 1};
      final options = CucumberOptions(
        features: features,
        worldParameters: parameters,
      );
      features.add('more/');
      parameters['b'] = 2;
      expect(options.features, ['features/']);
      expect(options.worldParameters, {'a': 1});
      expect(() => options.features!.add('x'), throwsUnsupportedError);
      expect(() => options.worldParameters!['x'] = 1, throwsUnsupportedError);
    });

    test('merge: values set in the other options win', () {
      final glue = <Glue>[Given('a step', () {})];
      final base = CucumberOptions(
        glue: glue,
        world: _World.new,
        features: ['features/'],
        names: ['a'],
        retry: 1,
        order: 'reverse',
        dryRun: false,
        plugins: ['message:a.ndjson'],
        suiteName: 'base',
        profile: 'ci',
        mapTags: true,
        scenarioTimeout: const Timeout(Duration(seconds: 5)),
      );
      final merged = base.merge(
        CucumberOptions(
          features: ['other/'],
          retry: 2,
          dryRun: true,
          plugins: ['message:b.ndjson'],
          mapTags: false,
        ),
      );
      expect(merged.glue, glue);
      expect(merged.world, same(base.world));
      expect(merged.features, ['other/'], reason: 'lists are replaced');
      expect(merged.names, ['a']);
      expect(merged.retry, 2);
      expect(merged.order, 'reverse');
      expect(merged.dryRun, isTrue);
      expect(merged.plugins, ['message:b.ndjson']);
      expect(merged.suiteName, 'base');
      expect(merged.profile, 'ci');
      expect(merged.mapTags, isFalse);
      expect(merged.scenarioTimeout, const Timeout(Duration(seconds: 5)));
    });

    test('merge: unset values do not override', () {
      final base = CucumberOptions(retry: 3, features: ['x/'], tags: '@a');
      final merged = base.merge(CucumberOptions());
      expect(merged.retry, 3);
      expect(merged.features, ['x/']);
      expect(merged.tags, '@a');
    });

    test('merge: tags are combined with and', () {
      final merged = CucumberOptions(
        tags: '@a or @b',
      ).merge(CucumberOptions(tags: 'not @wip'));
      expect(merged.tags, '(@a or @b) and (not @wip)');
    });

    test('merge: world parameters are merged recursively', () {
      final merged =
          CucumberOptions(
            worldParameters: {
              'url': 'http://a',
              'db': {'host': 'a', 'port': 1},
              'list': [1, 2],
            },
          ).merge(
            CucumberOptions(
              worldParameters: {
                'db': {'port': 2},
                'list': [3],
                'extra': true,
              },
            ),
          );
      expect(merged.worldParameters, {
        'url': 'http://a',
        'db': {'host': 'a', 'port': 2},
        'list': [3],
        'extra': true,
      });
    });

    test('toString lists the fields that are set', () {
      expect(
        CucumberOptions(retry: 1, tags: '@a').toString(),
        'CucumberOptions(tags: @a, retry: 1)',
      );
    });
  });

  group('andTags', () {
    test('ignores missing and blank expressions', () {
      expect(andTags(null, null), isNull);
      expect(andTags('  ', null), isNull);
      expect(andTags('@a', null), '@a');
      expect(andTags(null, '@b'), '@b');
      expect(andTags('', '@b'), '@b');
      expect(andTags('@a', '@b'), '(@a) and (@b)');
    });
  });
}
