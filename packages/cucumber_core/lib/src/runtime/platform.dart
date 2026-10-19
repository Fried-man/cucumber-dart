import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import '../version.dart';

/// Platform facts that a host injects into the engine.
///
/// The core is pure Dart (ADR-0004), so it cannot read the environment, the
/// operating system or files itself. Hosts such as `package:cucumber`
/// subclass this to supply them. The defaults describe an unknown platform
/// with the system clock.
class CucumberPlatform {
  /// Creates a platform with the default facts.
  const CucumberPlatform();

  /// The current wall-clock time, used for message timestamps.
  DateTime now() => DateTime.now();

  /// A started stopwatch, used to measure durations.
  Stopwatch startStopwatch() => Stopwatch()..start();

  /// Environment variables, when the platform has them.
  Map<String, String> get environment => const {};

  /// The language runtime, reported in `meta.runtime`.
  messages.Product get runtime => const messages.Product(name: 'Dart');

  /// The operating system, reported in `meta.os`.
  messages.Product get os => const messages.Product(name: 'unknown');

  /// The CPU architecture, reported in `meta.cpu`.
  messages.Product get cpu => const messages.Product(name: 'unknown');

  /// The CI environment, reported in `meta.ci`, when running on CI.
  messages.Ci? get ci => null;

  /// The `meta` message describing this platform and implementation.
  messages.Meta meta() => messages.Meta(
    protocolVersion: protocolVersion,
    implementation: const messages.Product(
      name: implementationName,
      version: cucumberCoreVersion,
    ),
    runtime: runtime,
    os: os,
    cpu: cpu,
    ci: ci,
  );
}
