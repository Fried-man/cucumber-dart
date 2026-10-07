# ADR-0004: Pure Dart first, Flutter-ready core

- **Status:** Accepted
- **Date:** 2026-10-06
- **Design:** §3.1, §12

## Context

The most popular Dart BDD tool, `bdd_widget_test`, targets Flutter widget tests. `flutter_gherkin`'s
`integration_test` line stalled because:

- it declared tests asynchronously, after an `await`;
- its code generator bypassed `build_runner`;
- it had to get results off the device.

Getting the engine semantics right (the CCK) does not depend on Flutter.

## Decision

- **Core restrictions.** `cucumber_core` uses no `dart:io`, Flutter, `dart:mirrors` or `package:test`. Hosts inject
  the environment, files, the clock and meta information.
- **v1 targets `dart test`** through `package:cucumber`.
- **Next: `cucumber_flutter`.** It will provide `testWidgets` with a `WidgetTester` in the World. Widget tests run on
  the host VM, so they can read feature files from disk.
- **Then: on-device `integration_test`.** Feature sources will be embedded by a builder, so declaration stays
  synchronous. Configuration comes from `--dart-define`, and messages are sent back to the host.

## Consequences

- The core engine is reusable by every host, including web and a future CLI.
- On-device runs need code generation for feature sources, and a transport for results.
