// Runs the language-neutral acceptance test data of cucumber/ci-environment
// (testdata/src/*.txt and the expected *.txt.json), synced by tool/sync.dart.
import 'dart:convert';
import 'dart:io';

import 'package:cucumber_ci_environment/cucumber_ci_environment.dart';
import 'package:test/test.dart';

void main() {
  final testdata = Directory('testdata/src');
  final environments =
      testdata
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.txt'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('the test data is synced', () {
    expect(environments, hasLength(greaterThanOrEqualTo(20)));
  });

  for (final file in environments) {
    final name = file.uri.pathSegments.last.replaceAll('.txt', '');
    test('detects $name', () {
      final env = _parseEnvironment(file.readAsStringSync());
      final expected = jsonDecode(File('${file.path}.json').readAsStringSync());

      expect(detectCiEnvironment(env)?.toJson(), expected);
    });
  }
}

/// Parses `NAME=value` lines.
///
/// Upstream runs these tests from a language directory next to `testdata/`,
/// so relative paths in the data start with `../testdata/`. `test/` stands
/// in for that directory here.
Map<String, String> _parseEnvironment(String text) {
  final env = <String, String>{};
  for (final line in const LineSplitter().convert(text)) {
    if (line.isEmpty) {
      continue;
    }
    final equals = line.indexOf('=');
    final name = equals < 0 ? line : line.substring(0, equals);
    var value = equals < 0 ? '' : line.substring(equals + 1);
    if (name == 'GITHUB_EVENT_PATH') {
      value = File.fromUri(Directory('test').absolute.uri.resolve(value)).path;
    }
    env[name] = value;
  }
  return env;
}
