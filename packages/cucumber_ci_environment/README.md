# cucumber_ci_environment

A Dart port of [cucumber/ci-environment][upstream]. It detects the CI server, the build and its Git details from
the environment variables of a run. The result is the `Ci` message that Cucumber implementations report in
`meta.ci` of [Cucumber Messages][messages].

```dart
import 'dart:io';

import 'package:cucumber_ci_environment/cucumber_ci_environment.dart';

void main() {
  final ci = detectCiEnvironment(Platform.environment);
  print(ci?.toJson() ?? 'No CI server detected');
}
```

`detectCiEnvironment` returns the CI server's name, the build URL and, when the variables are set, the build
number and the Git remote (without credentials), revision, branch and tag. For GitHub Actions pull requests, the
revision is the pull request's head commit, read from the event payload at `GITHUB_EVENT_PATH`. Pass `readFile` to
read it some other way, for example where there is no file system.

See [`example/cucumber_ci_environment_example.dart`](https://github.com/Fried-man/cucumber-dart/blob/main/packages/cucumber_ci_environment/example/cucumber_ci_environment_example.dart).

## Status

This is an in-repository port used by [`cucumber`][cucumber] (Cucumber for Dart). It is meant to be contributed to
cucumber/ci-environment and published from there, so it is not published from this repository (`publish_to: none`,
[ADR-0005][adr-0005]). Its version follows the upstream release whose data it uses (15.0.0).

- **Data.** `tool/sync.dart` downloads the pinned upstream release, checks the digest of the files it uses, and
  writes the CI environment templates (`CiEnvironments.json`) to `lib/src/ci_environments.g.dart` and the
  acceptance test data to `testdata/`. `dart run tool/sync.dart --check` fails when they drift.
- **Conformance.** The tests run every upstream `testdata/src/*.txt` environment against its expected `.txt.json`.
- **Differences.** It follows the JavaScript implementation, except that a GitHub pull request event payload that
  cannot be read falls back to `GITHUB_SHA` instead of throwing, as the Java implementation does.

[upstream]: https://github.com/cucumber/ci-environment
[messages]: https://github.com/cucumber/messages
[cucumber]: https://github.com/Fried-man/cucumber-dart/tree/main/packages/cucumber
[adr-0005]: https://github.com/Fried-man/cucumber-dart/blob/main/docs/decisions/0005-monorepo-and-in-repo-ports.md
