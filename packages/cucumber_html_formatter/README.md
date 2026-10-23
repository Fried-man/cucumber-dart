# cucumber_html_formatter

Writes [Cucumber Messages][messages] as a standalone HTML report. Like the Java, Ruby and .NET wrappers of
[cucumber/html-formatter][upstream], it embeds the prebuilt assets of the npm package `@cucumber/html-formatter`
(template, script, style sheet and icon) and streams the messages into the template.

```dart
import 'dart:io';

import 'package:cucumber_html_formatter/cucumber_html_formatter.dart';
import 'package:cucumber_messages/cucumber_messages.dart';

Future<void> writeReport(Iterable<Envelope> envelopes) async {
  final sink = File('build/cucumber/report.html').openWrite();
  final writer = MessagesToHtmlWriter(sink, title: 'My run');
  envelopes.forEach(writer.write);
  writer.close();
  await sink.close();
}
```

`MessagesToHtmlWriter` writes to any `StringSink`, which its owner closes. `customCss` and `customScript` extend
the report, and `css`, `script` and `icon` replace the defaults.
[`example/cucumber_html_formatter_example.dart`](example/cucumber_html_formatter_example.dart) converts an NDJSON
file into a report.

## Status

This is an in-repository wrapper used by [`cucumber`][cucumber] (Cucumber for Dart) for its `html:` output. It is
meant to be contributed to cucumber/html-formatter and published from there, so it is not published from this
repository (`publish_to: none`, [ADR-0005][adr-0005]). Its version follows the npm release whose assets it embeds
(24.2.0).

- **Assets.** `tool/sync.dart` downloads the pinned npm tarball, verifies its published integrity hash, and
  generates `lib/src/assets.g.dart` with the assets as Dart string literals and their SHA-256 digests.
  `dart run tool/sync.dart --check` fails when the generated file drifts.
- **Tests** check that the assets are embedded losslessly, the exact output against the template, the escaping of
  `<`, an empty run, and the report of every compatibility kit sample.
- **API.** It follows Java's `MessagesToHtmlWriter`: `write(envelope)` writes the head of the template with the
  first message, `close()` writes the tail (and the head of an empty run), and writing after `close()` throws.

The embedded script bundles third-party code; its license notices are in `mainJsLicense` (see `LICENSE`).

[upstream]: https://github.com/cucumber/html-formatter
[messages]: https://github.com/cucumber/messages
[cucumber]: https://github.com/Fried-man/cucumber-dart/tree/main/packages/cucumber
[adr-0005]: https://github.com/Fried-man/cucumber-dart/blob/main/docs/decisions/0005-monorepo-and-in-repo-ports.md
