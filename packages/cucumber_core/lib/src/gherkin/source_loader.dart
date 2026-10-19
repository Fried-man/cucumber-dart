import 'package:cucumber_gherkin/cucumber_gherkin.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import '../runtime/ids.dart';
import 'gherkin_index.dart';

/// The contents of a feature file, supplied by the host.
final class FeatureSource {
  /// Creates a source with [uri] (relative to the package root, with forward
  /// slashes) and its contents [data].
  const FeatureSource(this.uri, this.data);

  /// The URI reported in messages, such as `features/belly.feature`.
  final String uri;

  /// The Gherkin text.
  final String data;
}

/// A parsed feature file.
final class LoadedFeature {
  LoadedFeature._({
    required this.uri,
    required this.envelopes,
    required this.document,
    required this.index,
    required this.pickles,
    required this.parseErrors,
  });

  /// The feature file URI.
  final String uri;

  /// The messages for this file: `source`, then `gherkinDocument` or
  /// `parseError`s, then `pickle`s.
  final List<messages.Envelope> envelopes;

  /// The Gherkin document, unless parsing failed.
  final messages.GherkinDocument? document;

  /// An index of the document's AST nodes, unless parsing failed.
  final GherkinIndex? index;

  /// The pickles (executable scenarios), in document order.
  final List<messages.Pickle> pickles;

  /// The parse errors, if parsing failed.
  final List<messages.ParseError> parseErrors;

  /// Whether parsing failed.
  bool get hasParseErrors => parseErrors.isNotEmpty;
}

/// Parses feature files with `package:cucumber_gherkin` (design §3.3).
final class SourceLoader {
  /// Creates a loader allocating AST and pickle IDs from [ids].
  const SourceLoader(this.ids);

  /// The ID scheme.
  final IdScheme ids;

  /// Parses [source].
  LoadedFeature load(FeatureSource source) {
    final envelopes = generateMessages(
      source.data,
      source.uri,
      GherkinOptions(idGenerator: ids.forSource(source.uri).newId),
    );
    messages.GherkinDocument? document;
    final pickles = <messages.Pickle>[];
    final parseErrors = <messages.ParseError>[];
    for (final envelope in envelopes) {
      if (envelope.gherkinDocument case final doc?) document = doc;
      if (envelope.pickle case final pickle?) pickles.add(pickle);
      if (envelope.parseError case final error?) parseErrors.add(error);
    }
    return LoadedFeature._(
      uri: source.uri,
      envelopes: List.unmodifiable(envelopes),
      document: document,
      index: document == null ? null : GherkinIndex(document),
      pickles: List.unmodifiable(pickles),
      parseErrors: List.unmodifiable(parseErrors),
    );
  }

  /// Parses every source, in order.
  List<LoadedFeature> loadAll(Iterable<FeatureSource> sources) => [
    for (final source in sources) load(source),
  ];
}
