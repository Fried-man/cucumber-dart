// Lists the compatibility kit samples and the files of each one.
//
//   dart run example/cucumber_compatibility_kit_example.dart
//
// A harness finds the samples the same way: it resolves this package's
// library and reads the `features/` directory next to `lib/`.
import 'dart:io';
import 'dart:isolate';

import 'package:cucumber_compatibility_kit/cucumber_compatibility_kit.dart';

/// The `features/` directory of this package, or `null` when package URIs
/// cannot be resolved (for example, in a compiled executable).
Future<Directory?> findSamples() async {
  final library = await Isolate.resolvePackageUri(
    Uri.parse(
      'package:cucumber_compatibility_kit/cucumber_compatibility_kit.dart',
    ),
  );
  return library == null
      ? null
      : Directory.fromUri(library.resolve('../features/'));
}

Future<void> main() async {
  final features = await findSamples();
  if (features == null) {
    stderr.writeln('Cannot resolve package:cucumber_compatibility_kit.');
    exitCode = 1;
    return;
  }
  final samples = features.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  print(
    '@cucumber/compatibility-kit $compatibilityKitVersion: '
    '${samples.length} samples',
  );
  for (final sample in samples) {
    final files = [
      for (final file in sample.listSync().whereType<File>())
        file.uri.pathSegments.last,
    ]..sort();
    print(
      '${sample.uri.pathSegments.lastWhere((s) => s.isNotEmpty)}: '
      '${files.join(', ')}',
    );
  }
}
