// Prints the CI server, build and Git details detected from the environment
// variables of this process.
//
//   dart run example/cucumber_ci_environment_example.dart
import 'dart:io';

import 'package:cucumber_ci_environment/cucumber_ci_environment.dart';

/// Describes the CI environment detected from [environment].
String describeCiEnvironment(Map<String, String> environment) {
  final ci = detectCiEnvironment(environment);
  if (ci == null) return 'No CI server detected.';
  final description = StringBuffer('${ci.name}: ${ci.url}');
  if (ci.buildNumber case final buildNumber?) {
    description.write(' (build $buildNumber)');
  }
  if (ci.git case final git?) {
    final ref = git.tag ?? git.branch ?? 'a detached HEAD';
    description.write('\n${git.remote} at ${git.revision}, $ref');
  }
  return description.toString();
}

void main() => print(describeCiEnvironment(Platform.environment));
