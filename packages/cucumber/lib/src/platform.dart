import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:cucumber_ci_environment/cucumber_ci_environment.dart';
import 'package:cucumber_core/engine.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;

/// The platform facts of the Dart VM, read from `dart:io` (design §7.3).
///
/// - `meta.runtime`: `Dart` and the SDK version;
/// - `meta.os`: the operating system and its version;
/// - `meta.cpu`: the CPU architecture, such as `x64` or `arm64`;
/// - `meta.ci`: the CI server, build and Git details detected from the
///   environment by `cucumber_ci_environment`, when running on CI.
final class IoCucumberPlatform extends CucumberPlatform {
  /// Creates the platform. [environment] defaults to the process
  /// environment.
  IoCucumberPlatform({Map<String, String>? environment})
    : _environment = environment;

  final Map<String, String>? _environment;

  @override
  Map<String, String> get environment => _environment ?? Platform.environment;

  @override
  messages.Product get runtime =>
      messages.Product(name: 'Dart', version: dartVersion(Platform.version));

  @override
  messages.Product get os => messages.Product(
    name: Platform.operatingSystem,
    version: Platform.operatingSystemVersion,
  );

  @override
  messages.Product get cpu => messages.Product(name: cpuArchitecture());

  @override
  messages.Ci? get ci => detectCiEnvironment(environment);
}

/// The version number at the start of [platformVersion], which looks like
/// `3.8.0 (stable) (…) on "linux_x64"`.
String dartVersion(String platformVersion) {
  final version = platformVersion.trim().split(RegExp(r'\s+')).first;
  return version.isEmpty ? platformVersion : version;
}

/// The CPU architecture of the running VM, such as `x64`, `arm64`, `ia32` or
/// `riscv64`.
String cpuArchitecture([Abi? abi]) {
  final name = (abi ?? Abi.current()).toString();
  final separator = name.indexOf('_');
  return separator < 0 ? name : name.substring(separator + 1);
}
