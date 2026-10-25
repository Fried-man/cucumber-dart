// The compatibility kit samples that test/compatibility_host_test.dart skips
// on top of the engine's (skippedSamples in
// packages/cucumber_core/test/compatibility/cck.dart), with the reason.
// docs/compatibility.md lists both, and test/compatibility_report_test.dart
// keeps it in step with them.

/// Samples that pass through the `SerialHost` but cannot through `dart test`.
const Map<String, String> skippedThroughDartTest = {};
