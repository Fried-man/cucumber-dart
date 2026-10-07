import 'dart:io';

/// Resolves the directory that holds the shared conformance test data.
///
/// Mirrors the other language implementations: honours the
/// `CUCUMBER_EXPRESSIONS_TEST_DATA_DIR` environment variable and falls back to
/// the `testdata` directory at the repository root.
///
/// cucumber-dart vendors this package together with its test data, so an
/// in-package `testdata` directory is preferred when present.
String get testDataDir =>
    Platform.environment['CUCUMBER_EXPRESSIONS_TEST_DATA_DIR'] ??
    (Directory('testdata').existsSync() ? 'testdata' : '../testdata');

/// Lists the `*.yaml` files in [dir] sorted by path for deterministic runs.
List<File> yamlFilesIn(String dir) {
  final directory = Directory(dir);
  final files = directory
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.yaml'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}
