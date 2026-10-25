# cucumber_compatibility_kit

The samples of the [Cucumber Compatibility Kit][upstream] (CCK) as a Dart package. Cucumber implementations run
each sample's feature with equivalent step definitions and compare the Cucumber Messages they emit with the
sample's expected messages.

`features/<sample>/` holds, synced byte for byte from the npm package `@cucumber/compatibility-kit`
(`compatibilityKitVersion`, 31.0.0):

- the Gherkin source: `<sample>.feature`, or `<sample>.feature.md` for Markdown;
- the expected messages: `<sample>.ndjson`;
- the reference step definitions in TypeScript: `<sample>.ts`;
- assets used by the steps (images, a PDF) and, for some samples, the runner arguments: `<sample>.arguments.txt`.

A harness finds the samples through this package's library URI:

```dart
import 'dart:io';
import 'dart:isolate';

Future<Directory> compatibilityKitSamples() async {
  final library = await Isolate.resolvePackageUri(
    Uri.parse(
      'package:cucumber_compatibility_kit/cucumber_compatibility_kit.dart',
    ),
  );
  return Directory.fromUri(library!.resolve('../features/'));
}
```

[`example/cucumber_compatibility_kit_example.dart`](https://github.com/Fried-man/cucumber-dart/blob/main/packages/cucumber_compatibility_kit/example/cucumber_compatibility_kit_example.dart) lists the
samples and their files.

## Status

This is the in-repository precursor of a `compatibility-kit/dart` package. [`cucumber_core`][cucumber_core] passes
47 of the 49 samples through its engine, and [`cucumber`][cucumber] passes the same 47 through `dart test`. The
[compatibility report][compatibility] lists every sample, its result through each host and the reasons for the
skips. This package is meant to be contributed to cucumber/compatibility-kit and published from there, so it is not
published from this repository (`publish_to: none`, [ADR-0005][adr-0005]).

`tool/sync.dart` downloads the pinned npm tarball, verifies its published integrity hash and writes the samples to
`features/`. `dart run tool/sync.dart --check` fails when they drift.

[upstream]: https://github.com/cucumber/compatibility-kit
[cucumber_core]: https://github.com/Fried-man/cucumber-dart/tree/main/packages/cucumber_core
[cucumber]: https://github.com/Fried-man/cucumber-dart/tree/main/packages/cucumber
[compatibility]: https://github.com/Fried-man/cucumber-dart/blob/main/docs/compatibility.md
[adr-0005]: https://github.com/Fried-man/cucumber-dart/blob/main/docs/decisions/0005-monorepo-and-in-repo-ports.md
