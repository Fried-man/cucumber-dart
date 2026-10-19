import 'dart:io';

import 'package:cucumber/cucumber.dart';
import 'package:cucumber/src/discovery.dart';
import 'package:cucumber/src/suite.dart' show findPackageRoot;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  void write(String path, [String contents = 'Feature: f\n']) {
    File(p.joinAll([root.path, ...path.split('/')]))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('cucumber_discovery_');
    write('features/b.feature', 'Feature: b\n');
    write('features/a.feature', '\uFEFFFeature: a\n');
    write('features/nested/c.feature');
    write('features/nested/notes.txt', 'not a feature');
    write('features/.hidden/d.feature');
    write('other/e.feature');
    write('other/deep/f.feature');
  });
  tearDown(() => root.deleteSync(recursive: true));

  DiscoveredFeatures discover(List<String> locations) =>
      discoverFeatures(locations, packageRoot: root.path);

  List<String> uris(List<String> locations) => [
    for (final source in discover(locations).sources) source.uri,
  ];

  test('a directory selects its feature files recursively, sorted', () {
    expect(uris(['features/']), [
      'features/a.feature',
      'features/b.feature',
      'features/nested/c.feature',
    ]);
    expect(uris(['features']), uris(['features/']));
  });

  test('reads the files, without a byte order mark', () {
    final sources = discover([
      'features/a.feature',
      'features/b.feature',
    ]).sources;
    expect(sources.first.data, 'Feature: a\n');
    expect(sources.last.data, 'Feature: b\n');
  });

  test('a file selects itself', () {
    expect(uris(['other/e.feature']), ['other/e.feature']);
  });

  test('a glob selects matching feature files, sorted', () {
    expect(uris(['**/e.feature', 'other/**.feature']), [
      'other/e.feature',
      'other/deep/f.feature',
    ]);
    expect(uris(['features/*.feature']), [
      'features/a.feature',
      'features/b.feature',
    ]);
    expect(uris(['nothing/*.feature']), isEmpty);
  });

  test('keeps the order of the locations and drops duplicates', () {
    expect(uris(['other/e.feature', 'features/', 'features/b.feature']), [
      'other/e.feature',
      'features/a.feature',
      'features/b.feature',
      'features/nested/c.feature',
    ]);
  });

  test('path:line selects lines', () {
    final found = discover([
      'features/a.feature:3',
      'features/a.feature:7:9',
      'other/e.feature',
    ]);
    expect(found.lines, {
      'features/a.feature': {3, 7, 9},
    });
  });

  test('a file selected as a whole ignores its line selections', () {
    expect(discover(['features/a.feature:3', 'features/']).lines, isEmpty);
  });

  test('accepts absolute paths', () {
    final path = p.join(root.path, 'other', 'e.feature');
    final found = discover(['$path:4']);
    expect(found.sources.single.uri, 'other/e.feature');
    expect(found.lines, {
      'other/e.feature': {4},
    });
  });

  test('URIs outside the package root are relative to it', () {
    final inner = p.join(root.path, 'features');
    final found = discoverFeatures(['../other/e.feature'], packageRoot: inner);
    expect(found.sources.single.uri, '../other/e.feature');
  });

  test('rejects missing paths and invalid lines', () {
    Matcher rejects(Object message) => throwsA(
      isA<CucumberConfigurationException>().having(
        (e) => e.message,
        'message',
        message,
      ),
    );

    expect(() => discover(['missing/']), rejects(contains('does not exist')));
    expect(() => discover(['features/:3']), rejects(contains('directory')));
    expect(() => discover(['features/*.feature:3']), rejects(contains('glob')));
    expect(() => discover(['features/a.feature:0']), rejects(contains('line')));
    expect(() => discover(['  ']), rejects(contains('Empty')));
  });

  group('FeatureLocation.parse', () {
    test('splits off lines', () {
      final location = FeatureLocation.parse('features/a.feature:3:12');
      expect(location.path, 'features/a.feature');
      expect(location.lines, [3, 12]);
      expect(location.toString(), 'features/a.feature:3:12');
    });

    test('keeps Windows drive letters', () {
      expect(FeatureLocation.parse(r'C:\x\a.feature').path, r'C:\x\a.feature');
      final location = FeatureLocation.parse(r'C:\x\a.feature:5');
      expect(location.path, r'C:\x\a.feature');
      expect(location.lines, [5]);
    });

    test('recognises globs', () {
      expect(FeatureLocation.parse('features/**').isGlob, isTrue);
      expect(FeatureLocation.parse('features/{a,b}.feature').isGlob, isTrue);
      expect(FeatureLocation.parse('features/a.feature').isGlob, isFalse);
    });
  });

  test('findPackageRoot finds the closest pubspec.yaml', () {
    write('pubspec.yaml', 'name: x\n');
    expect(
      findPackageRoot(p.join(root.path, 'features', 'nested')),
      p.normalize(root.path),
    );
  });
}
