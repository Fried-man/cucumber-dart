/// Samples from the Cucumber Compatibility Kit (CCK).
///
/// The `features/` directory of this package holds the samples of
/// `@cucumber/compatibility-kit`, synced byte-for-byte from the pinned npm
/// tarball by `tool/sync.dart`. Each sample directory contains a `.feature`
/// (or `.feature.md`) source, the expected Cucumber Messages (`.ndjson`), the
/// reference TypeScript step definitions (`.ts`), optional assets and an
/// optional `.arguments.txt`.
///
/// This package is the in-repo precursor of an upstream
/// `compatibility-kit/dart` package. See
/// `docs/decisions/0019-compatibility-kit-conformance.md`.
library;

/// The `@cucumber/compatibility-kit` version whose samples are in `features/`.
const String compatibilityKitVersion = '31.0.0';
