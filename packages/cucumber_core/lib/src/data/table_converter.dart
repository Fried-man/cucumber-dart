import '../glue/function_shapes.g.dart';
import 'data_table.dart';
import 'doc_string.dart';

/// Thrown when a data table or doc string cannot be converted to the
/// requested type.
final class ConversionException implements Exception {
  /// Creates an exception with [message].
  ConversionException(this.message, [this.cause]);

  /// What went wrong.
  final String message;

  /// The error thrown by a transformer, if any.
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message\nCaused by: $cause';
}

/// Whether `R` is `T` or `T?` (ignoring nullability).
bool isSameType<T, R>() => <T>[] is List<R> && <R>[] is List<T?>;

/// Whether `T` is untyped: `dynamic`, `Object` or `Object?`.
bool isUntyped<T>() => <Object>[] is List<T>;

/// A possible conversion of a data table to an argument of type [X].
final class TableCandidate<X> {
  /// Creates a candidate producing an `X` with [convert].
  TableCandidate(this.convert);

  /// Converts the table.
  final X Function(DataTable table) convert;

  /// Whether parameter [index] of [f] (called with [arity] arguments) accepts
  /// an `X`.
  bool acceptedAt(Function f, int index, int arity) =>
      acceptsAt<X>(f, index, arity);

  /// Whether `X` is `R` (ignoring nullability).
  bool produces<R>() => isSameType<X, R>();
}

/// How a `DataTableType<T>` converts tables (design §4.6, ADR-0011).
sealed class DataTableTypeSpec<T> {
  DataTableTypeSpec(this.replaceWithEmptyString);

  /// A marker that converts to the empty string, such as `'[blank]'`.
  final String? replaceWithEmptyString;

  /// The produced type.
  Type get type => T;

  /// Whether this type produces `R` (or `R?`).
  bool produces<R>() => isSameType<T, R>();

  /// The conversions this type offers to step parameters, in priority order.
  List<TableCandidate<Object?>> get candidates;

  String _replace(String cell) => cell == replaceWithEmptyString ? '' : cell;

  R _call<R>(R Function() transform, String what) {
    try {
      return transform();
    } on ConversionException {
      rethrow;
    } on Object catch (e) {
      throw ConversionException("Can't convert $what to $T", e);
    }
  }
}

/// A `DataTableType<T>.entry`: each data row, keyed by the header row, is one
/// `T`.
final class EntryTypeSpec<T> extends DataTableTypeSpec<T> {
  /// Creates an entry type.
  EntryTypeSpec(this.transform, String? replaceWithEmptyString)
    : super(replaceWithEmptyString);

  /// Converts one entry.
  final T Function(Map<String, String> entry) transform;

  /// Converts every data row of [table].
  List<R> toList<R>(DataTable table) {
    final out = <R>[];
    if (table.isEmpty) return out;
    final header = [for (final cell in table.row(0)) _replace(cell)];
    for (var r = 1; r < table.height; r++) {
      final row = table.row(r);
      final entry = <String, String>{
        for (var c = 0; c < header.length; c++) header[c]: _replace(row[c]),
      };
      out.add(_call(() => transform(entry), 'entry $entry') as R);
    }
    return out;
  }

  @override
  List<TableCandidate<Object?>> get candidates => [
    TableCandidate<List<T>>((table) => toList<T>(table)),
  ];
}

/// A `DataTableType<T>.row`: each row is one `T`.
final class RowTypeSpec<T> extends DataTableTypeSpec<T> {
  /// Creates a row type.
  RowTypeSpec(this.transform, String? replaceWithEmptyString)
    : super(replaceWithEmptyString);

  /// Converts one row.
  final T Function(List<String> row) transform;

  /// Converts every row of [table].
  List<R> toList<R>(DataTable table) => [
    for (final row in table.raw)
      _call(
            () => transform([for (final cell in row) _replace(cell)]),
            'row $row',
          )
          as R,
  ];

  @override
  List<TableCandidate<Object?>> get candidates => [
    TableCandidate<List<T>>((table) => toList<T>(table)),
  ];
}

/// A `DataTableType<T>.cell`, or a built-in cell type: each cell is one `T`.
final class CellTypeSpec<T> extends DataTableTypeSpec<T> {
  /// Creates a cell type.
  CellTypeSpec(this.transform, String? replaceWithEmptyString)
    : super(replaceWithEmptyString);

  /// Converts one cell.
  final T Function(String cell) transform;

  /// Converts [cell] to `R`, which must be `T` or `T?`. An empty cell becomes
  /// `null` when `R` is nullable.
  R convert<R>(String cell) {
    if (cell.isEmpty && null is R) return null as R;
    final value = _replace(cell);
    return _call(() => transform(value), 'cell "$cell"') as R;
  }

  @override
  List<TableCandidate<Object?>> get candidates => [
    ...cellCandidates<T>(),
    ...mapCandidates<String, T>(),
  ];
}

/// A `DataTableType<T>.table`: the whole table is one `T`.
final class TableTypeSpec<T> extends DataTableTypeSpec<T> {
  /// Creates a table type.
  TableTypeSpec(this.transform) : super(null);

  /// Converts the table.
  final T Function(DataTable table) transform;

  /// Converts [table].
  R convert<R>(DataTable table) =>
      _call(() => transform(table), 'the table') as R;

  @override
  List<TableCandidate<Object?>> get candidates => [
    TableCandidate<T>((table) => convert<T>(table)),
  ];
}

/// How a `DocStringType<T>` converts doc strings.
final class DocStringTypeSpec<T> {
  /// Creates a doc string type for [contentType] (any when `null`).
  DocStringTypeSpec(this.transform, this.contentType);

  /// Converts the content.
  final T Function(String content) transform;

  /// The media type this type is for, or `null` for any.
  final String? contentType;

  /// The produced type.
  Type get type => T;

  /// Whether this type produces `R` (or `R?`).
  bool produces<R>() => isSameType<T, R>();

  /// Whether parameter [index] of [f] (called with [arity] arguments) accepts
  /// a `T`.
  bool acceptedAt(Function f, int index, int arity) =>
      acceptsAt<T>(f, index, arity);

  /// Converts [docString].
  R convert<R>(DocString docString) {
    try {
      return transform(docString.content) as R;
    } on Object catch (e) {
      throw ConversionException("Can't convert the doc string to $T", e);
    }
  }
}

/// Conversions for a cell type `B`, nullable variants first so that a
/// `List<int?>` parameter is not given a `List<int>`.
List<TableCandidate<Object?>> cellCandidates<B>() => [
  TableCandidate<List<List<B?>>>((t) => t.asLists<B?>()),
  TableCandidate<List<List<B>>>((t) => t.asLists<B>()),
  TableCandidate<List<B?>>((t) => _singleColumn(t).asList<B?>()),
  TableCandidate<List<B>>((t) => _singleColumn(t).asList<B>()),
];

/// Map conversions with keys `K` and values `V`.
List<TableCandidate<Object?>> mapCandidates<K, V>() => [
  TableCandidate<Map<K, V?>>((t) => t.asMap<K, V?>()),
  TableCandidate<Map<K, V>>((t) => t.asMap<K, V>()),
  TableCandidate<List<Map<K, V?>>>((t) => t.asMaps<K, V?>()),
  TableCandidate<List<Map<K, V>>>((t) => t.asMaps<K, V>()),
];

DataTable _singleColumn(DataTable table) {
  if (table.width > 1) {
    throw ConversionException(
      "Can't convert a table with ${table.width} columns to a list of cells. "
      'Use a List<List<T>> parameter, or register a DataTableType.entry or '
      'DataTableType.row.',
    );
  }
  return table;
}

bool _parseBool(String s) => switch (s.toLowerCase()) {
  'true' => true,
  'false' => false,
  _ => throw FormatException('Not a bool', s),
};

/// The built-in cell types. `num` comes before `int` and `double` so that a
/// `List<num>` parameter is not converted with `int.parse`.
final List<CellTypeSpec<Object?>> builtInCellTypes = [
  CellTypeSpec<num>(num.parse, null),
  CellTypeSpec<String>((s) => s, null),
  CellTypeSpec<int>(int.parse, null),
  CellTypeSpec<double>(double.parse, null),
  CellTypeSpec<bool>(_parseBool, null),
  CellTypeSpec<BigInt>(BigInt.parse, null),
];

List<TableCandidate<Object?>> _mapsWithKey<K>() => [
  ...mapCandidates<K, num>(),
  ...mapCandidates<K, String>(),
  ...mapCandidates<K, int>(),
  ...mapCandidates<K, double>(),
  ...mapCandidates<K, bool>(),
  ...mapCandidates<K, BigInt>(),
];

final List<TableCandidate<Object?>> _builtInCandidates = [
  ...cellCandidates<num>(),
  ...cellCandidates<String>(),
  ...cellCandidates<int>(),
  ...cellCandidates<double>(),
  ...cellCandidates<bool>(),
  ...cellCandidates<BigInt>(),
  ..._mapsWithKey<String>(),
  ..._mapsWithKey<int>(),
  ..._mapsWithKey<num>(),
  ..._mapsWithKey<double>(),
  ..._mapsWithKey<bool>(),
  ..._mapsWithKey<BigInt>(),
];

/// Converts data tables and doc strings using the registered
/// `DataTableType`s and `DocStringType`s, and the built-in cell types.
final class TableConverter {
  /// Creates a converter with the given registered types.
  TableConverter({
    List<DataTableTypeSpec<Object?>> tableTypes = const [],
    List<DocStringTypeSpec<Object?>> docStringTypes = const [],
  }) : tableTypes = List.unmodifiable(tableTypes),
       docStringTypes = List.unmodifiable(docStringTypes);

  /// The converter for tables and doc strings built by users: built-in types
  /// only.
  static final TableConverter builtIn = TableConverter();

  /// The registered data table types, in registration order.
  final List<DataTableTypeSpec<Object?>> tableTypes;

  /// The registered doc string types, in registration order.
  final List<DocStringTypeSpec<Object?>> docStringTypes;

  late final List<TableCandidate<Object?>> _candidates = [
    TableCandidate<DataTable>((t) => t),
    TableCandidate<List<List<String>>>((t) => t.raw),
    for (final type in tableTypes) ...type.candidates,
    ..._builtInCandidates,
  ];

  CellTypeSpec<Object?>? _cellType<R>() {
    for (final type in tableTypes) {
      if (type is CellTypeSpec<Object?> && type.produces<R>()) return type;
    }
    for (final type in builtInCellTypes) {
      if (type.produces<R>()) return type;
    }
    return null;
  }

  /// Converts one [cell] to `R`.
  R cell<R>(String cell) {
    if (isUntyped<R>()) return cell as R;
    final type = _cellType<R>();
    if (type != null) return type.convert<R>(cell);
    if ('' is R) return cell as R;
    throw ConversionException(
      "Can't convert a data table cell to $R. "
      'Register a DataTableType<$R>.cell.',
    );
  }

  /// Converts [table] to a `List<R>`: with a registered entry or row type for
  /// `R`, otherwise cell by cell (row-major).
  List<R> list<R>(DataTable table) {
    if (!isUntyped<R>()) {
      for (final type in tableTypes) {
        if (!type.produces<R>()) continue;
        switch (type) {
          case EntryTypeSpec<Object?>():
            return type.toList<R>(table);
          case RowTypeSpec<Object?>():
            return type.toList<R>(table);
          case CellTypeSpec<Object?>() || TableTypeSpec<Object?>():
            break;
        }
      }
    }
    return [
      for (final row in table.raw)
        for (final value in row) cell<R>(value),
    ];
  }

  /// Converts [table] to `R` with a registered table type, or with any other
  /// conversion that produces exactly `R`.
  R table<R>(DataTable table) {
    for (final type in tableTypes) {
      if (type is TableTypeSpec<Object?> && type.produces<R>()) {
        return type.convert<R>(table);
      }
    }
    for (final candidate in _candidates) {
      if (candidate.produces<R>()) return candidate.convert(table) as R;
    }
    throw ConversionException(
      "Can't convert a data table to $R. Register a DataTableType<$R>.",
    );
  }

  /// Converts [table] for parameter [index] of [body] (called with [arity]
  /// arguments): the first conversion the parameter accepts wins (design
  /// §4.5).
  Object? tableArgument(Function body, int index, int arity, DataTable table) {
    for (final candidate in _candidates) {
      if (candidate.acceptedAt(body, index, arity)) {
        return candidate.convert(table);
      }
    }
    throw ConversionException(
      "Can't convert the data table for parameter ${index + 1}. Declare it as "
      'DataTable, List<List<String>>, or a type with a registered '
      'DataTableType.',
    );
  }

  /// Converts [docString] to `R`.
  R docString<R>(DocString docString) {
    if (isSameType<DocString, R>()) return docString as R;
    if (isSameType<String, R>() || isUntyped<R>()) {
      return docString.content as R;
    }
    final type = _docStringType(
      docString,
      docStringTypes.where((t) => t.produces<R>()).toList(),
      '$R',
    );
    if (type != null) return type.convert<R>(docString);
    throw ConversionException(
      "Can't convert a doc string to $R. Register a DocStringType<$R>.",
    );
  }

  /// Converts [docString] for parameter [index] of [body] (called with
  /// [arity] arguments).
  Object? docStringArgument(
    Function body,
    int index,
    int arity,
    DocString docString,
  ) {
    if (acceptsAt<DocString>(body, index, arity)) return docString;
    if (acceptsAt<String>(body, index, arity)) return docString.content;
    final accepted = [
      for (final type in docStringTypes)
        if (type.acceptedAt(body, index, arity)) type,
    ];
    if (accepted.isNotEmpty) {
      final byType = accepted
          .where((t) => t.type == accepted.first.type)
          .toList();
      final type = _docStringType(docString, byType, '${byType.first.type}');
      if (type != null) return type.convert<Object?>(docString);
    }
    throw ConversionException(
      "Can't convert the doc string for parameter ${index + 1}. Declare it as "
      'DocString, String, or a type with a registered DocStringType.',
    );
  }

  DocStringTypeSpec<Object?>? _docStringType(
    DocString docString,
    List<DocStringTypeSpec<Object?>> types,
    String typeName,
  ) {
    if (types.isEmpty) return null;
    for (final type in types) {
      if (type.contentType != null && type.contentType == docString.mediaType) {
        return type;
      }
    }
    if (types.length == 1) return types.single;
    final anyContent = types.where((t) => t.contentType == null).toList();
    if (anyContent.length == 1) return anyContent.single;
    throw ConversionException(
      'Several DocStringType<$typeName>s match a doc string with content type '
      '"${docString.mediaType ?? ''}": '
      '${types.map((t) => t.contentType ?? '(any)').join(', ')}.',
    );
  }
}
