import 'dart:io';

import 'package:cucumber_core/engine.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('cucumberCoreVersion matches the package version', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
    expect(cucumberCoreVersion, pubspec['version']);
  });
}
