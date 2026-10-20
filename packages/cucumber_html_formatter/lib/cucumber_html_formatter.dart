/// Writes Cucumber Messages as a standalone HTML report.
///
/// [MessagesToHtmlWriter] streams the messages of a run into the report
/// template of [`@cucumber/html-formatter`][upstream], whose prebuilt assets
/// (template, script, style sheet and icon) this package embeds:
///
/// ```dart
/// final sink = File('build/cucumber/report.html').openWrite();
/// final writer = MessagesToHtmlWriter(sink);
/// envelopes.forEach(writer.write);
/// writer.close();
/// await sink.close();
/// ```
///
/// This package is a Dart wrapper of cucumber/html-formatter, like its Java,
/// Ruby and .NET wrappers. The assets are synced from the pinned npm release
/// ([htmlFormatterVersion]) by `tool/sync.dart` (ADR-0005).
///
/// [upstream]: https://github.com/cucumber/html-formatter
library;

export 'src/assets.g.dart'
    show
        htmlFormatterVersion,
        iconUrl,
        indexMustache,
        mainCss,
        mainJs,
        mainJsLicense;
export 'src/messages_to_html_writer.dart';
