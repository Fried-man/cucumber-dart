/// Samples from the Cucumber Compatibility Kit (CCK).
///
/// The `features/` directory of this package holds the samples of
/// `@cucumber/compatibility-kit`, synced byte-for-byte from the pinned npm
/// tarball by `tool/sync.dart`. Each sample directory contains a `.feature`
/// (or `.feature.md`) source, the expected Cucumber Messages (`.ndjson`), the
/// reference TypeScript step definitions (`.ts`), optional assets and an
/// optional `.arguments.txt`.
///
/// A harness finds the samples through this library's package URI:
///
/// ```dart
/// import 'dart:io';
/// import 'dart:isolate';
///
/// import 'package:cucumber_compatibility_kit/cucumber_compatibility_kit.dart';
///
/// Future<void> main() async {
///   final library = await Isolate.resolvePackageUri(
///     Uri.parse(
///       'package:cucumber_compatibility_kit/cucumber_compatibility_kit.dart',
///     ),
///   );
///   final features = Directory.fromUri(library!.resolve('../features/'));
///   print('$compatibilityKitVersion: ${features.listSync().length} samples');
/// }
/// ```
///
/// This package is the in-repo precursor of an upstream
/// `compatibility-kit/dart` package
/// ([ADR-0019](https://github.com/Fried-man/cucumber-dart/blob/main/docs/decisions/0019-compatibility-kit-conformance.md)).
library;

/// The `@cucumber/compatibility-kit` version whose samples are in `features/`.
const String compatibilityKitVersion = '31.0.0';
