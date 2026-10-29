import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// [path] without comments, blank lines and the `exclude` of this package.
List<String> rules(String path) => [
  for (final line in File(path).readAsLinesSync())
    if (line.trim().isNotEmpty &&
        !line.trimLeft().startsWith('#') &&
        line.trim() != 'exclude:' &&
        !line.contains('packages/cucumber_flutter/'))
      line,
];

void main() {
  test('the analysis options are those of the repository', () {
    // The repository's options exclude this package, which needs
    // `flutter pub get`, so it has a copy of its own.
    expect(
      rules('analysis_options.yaml'),
      rules(p.join('..', '..', 'analysis_options.yaml')),
    );
  });
}
