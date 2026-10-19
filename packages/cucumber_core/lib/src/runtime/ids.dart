import 'dart:convert';
import 'dart:math';

/// Generates message IDs.
abstract interface class IdGenerator {
  /// Returns a new ID.
  String newId();
}

/// Generates `'0'`, `'1'`, `'2'`, … as the Cucumber Compatibility Kit does.
final class IncrementingIdGenerator implements IdGenerator {
  /// Creates a generator whose first ID is [start].
  IncrementingIdGenerator([int start = 0]) : _next = start;

  int _next;

  @override
  String newId() => '${_next++}';
}

/// Generates random version 4 UUIDs.
final class UuidIdGenerator implements IdGenerator {
  /// Creates a generator drawing from [random], which defaults to a
  /// cryptographically secure source when available.
  UuidIdGenerator([Random? random]) : _random = random ?? _defaultRandom();

  final Random _random;

  static Random _defaultRandom() {
    try {
      return Random.secure();
    } on UnsupportedError {
      return Random();
    }
  }

  @override
  String newId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
    return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
        '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
        '${hex.sublist(10).join()}';
  }
}

/// Decides how message IDs are allocated (design §7.2, ADR-0018).
///
/// - Static messages from feature files (Gherkin documents and pickles) use the
///   generator returned by [forSource].
/// - Glue messages (parameter types, step definitions, hooks) use [forGlue].
/// - Everything else (test run, test cases, test steps, …) uses [newId].
abstract interface class IdScheme {
  /// One incrementing counter shared by every message, as in the CCK. Use it
  /// for deterministic tests.
  factory IdScheme.incrementing() = _IncrementingIdScheme;

  /// Deterministic IDs for static messages and UUIDs for dynamic ones.
  ///
  /// - Feature files: `<fnv64(uri)>-<n>`, with a counter per file.
  /// - Glue: `<fnv64(key)>-g<index>`, where the key combines the glue's source
  ///   reference and pattern.
  ///
  /// The same feature file or glue therefore gets the same IDs in every
  /// isolate, which lets report parts be merged by ID.
  factory IdScheme.deterministic({Random? random}) = _DeterministicIdScheme;

  /// Returns the generator for the Gherkin document and pickles of [uri].
  IdGenerator forSource(String uri);

  /// Returns the ID of the glue value at definition [index], identified by
  /// [key] (its source reference and pattern).
  String forGlue(int index, String key);

  /// Returns a new ID for a dynamic message.
  String newId();
}

final class _IncrementingIdScheme implements IdScheme {
  final IncrementingIdGenerator _generator = IncrementingIdGenerator();

  @override
  IdGenerator forSource(String uri) => _generator;

  @override
  String forGlue(int index, String key) => _generator.newId();

  @override
  String newId() => _generator.newId();
}

final class _DeterministicIdScheme implements IdScheme {
  _DeterministicIdScheme({Random? random}) : _uuids = UuidIdGenerator(random);

  final UuidIdGenerator _uuids;

  @override
  IdGenerator forSource(String uri) => _PrefixedIdGenerator('${fnv64(uri)}-');

  @override
  String forGlue(int index, String key) => '${fnv64(key)}-g$index';

  @override
  String newId() => _uuids.newId();
}

final class _PrefixedIdGenerator implements IdGenerator {
  _PrefixedIdGenerator(this._prefix);

  final String _prefix;
  int _next = 0;

  @override
  String newId() => '$_prefix${_next++}';
}

const int _two32 = 0x100000000;

/// The 64-bit FNV-1a hash of the UTF-8 bytes of [input], as 16 lowercase hex
/// digits.
///
/// Implemented with 32-bit halves so it gives the same result when compiled to
/// JavaScript.
String fnv64(String input) {
  // Offset basis 0xcbf29ce484222325.
  var hi = 0xcbf29ce4;
  var lo = 0x84222325;
  for (final byte in utf8.encode(input)) {
    lo = (lo ^ byte) % _two32;
    // Multiply by the FNV prime 0x100000001b3 = 2^40 + 0x1b3, modulo 2^64.
    final loProduct = lo * 0x1b3;
    final carry = loProduct ~/ _two32;
    final newLo = loProduct % _two32;
    final newHi = (hi * 0x1b3 + carry + (lo % 0x1000000) * 0x100) % _two32;
    hi = newHi;
    lo = newLo;
  }
  return '${hi.toRadixString(16).padLeft(8, '0')}'
      '${lo.toRadixString(16).padLeft(8, '0')}';
}
