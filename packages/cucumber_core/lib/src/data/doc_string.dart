import 'package:meta/meta.dart';

import 'table_converter.dart';

/// A doc string: a multi-line step argument with an optional media type
/// (design §4.6).
final class DocString {
  /// Creates a doc string with [content] and an optional [mediaType].
  DocString(this.content, {this.mediaType}) : _converter = null;

  /// Creates a doc string that converts with [converter].
  @internal
  DocString.withConverter(
    this.content,
    TableConverter converter, {
    this.mediaType,
  }) : _converter = converter;

  /// The text between the delimiters.
  final String content;

  /// The media type written after the opening delimiter, such as
  /// `application/json`, if any.
  final String? mediaType;

  final TableConverter? _converter;

  /// The content converted to `T` with a registered `DocStringType<T>`: the one
  /// for this doc string's media type, otherwise the only one for `T`.
  /// `String` and `DocString` need no registration.
  T convert<T>() => (_converter ?? TableConverter.builtIn).docString<T>(this);

  @override
  bool operator ==(Object other) =>
      other is DocString &&
      other.content == content &&
      other.mediaType == mediaType;

  @override
  int get hashCode => Object.hash(content, mediaType);

  @override
  String toString() => content;
}
