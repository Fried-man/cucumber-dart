import 'package:meta/meta.dart';

import 'table_converter.dart';
import 'table_diff.dart';

/// A data table: a step argument made of rows of string cells (design §4.6).
///
/// Tables passed to steps convert with the suite's `DataTableType`s; tables
/// built with [DataTable.new] only convert to the built-in cell types
/// (`String`, `int`, `double`, `num`, `bool` and `BigInt`).
///
/// Methods called without type arguments return strings. Typed conversions to
/// a nullable type turn empty cells into `null`.
final class DataTable {
  /// Creates a table from [rows]. Every row must have the same length.
  DataTable(List<List<String>> rows) : this.withConverter(rows, null);

  /// Creates a table that converts with [converter] (the built-in types when
  /// `null`).
  @internal
  DataTable.withConverter(List<List<String>> rows, TableConverter? converter)
    : _rows = List.unmodifiable([
        for (final row in rows) List<String>.unmodifiable(row),
      ]),
      _converter = converter ?? TableConverter.builtIn {
    if (_rows.isNotEmpty) {
      final width = _rows.first.length;
      for (var i = 1; i < _rows.length; i++) {
        if (_rows[i].length != width) {
          throw ArgumentError.value(
            rows,
            'rows',
            'Row $i has ${_rows[i].length} cells, but row 0 has $width',
          );
        }
      }
    }
  }

  final List<List<String>> _rows;
  final TableConverter _converter;

  /// The rows of string cells, unmodifiable. Empty cells are `''`.
  List<List<String>> get raw => _rows;

  /// The number of columns.
  int get width => _rows.isEmpty ? 0 : _rows.first.length;

  /// The number of rows.
  int get height => _rows.length;

  /// Whether the table has no rows.
  bool get isEmpty => _rows.isEmpty;

  /// The cell at [row] and [column] (both 0-based).
  String cell(int row, int column) => _rows[row][column];

  /// The row at [index].
  List<String> row(int index) => _rows[index];

  /// The column at [index].
  List<String> column(int index) =>
      List.unmodifiable([for (final row in _rows) row[index]]);

  /// The rows from [from] (inclusive) to [to] (exclusive, default: the end).
  DataTable rows(int from, [int? to]) =>
      DataTable.withConverter(_rows.sublist(from, to), _converter);

  /// The columns from [from] (inclusive) to [to] (exclusive, default: the
  /// end).
  DataTable columns(int from, [int? to]) => DataTable.withConverter([
    for (final row in _rows) row.sublist(from, to),
  ], _converter);

  /// The table with rows and columns swapped.
  DataTable transpose() => DataTable.withConverter([
    for (var c = 0; c < width; c++) [for (final row in _rows) row[c]],
  ], _converter);

  /// The table as a list of `T`.
  ///
  /// With a registered `DataTableType<T>.entry` (one item per data row, keyed
  /// by the header) or `.row` (one item per row), that type is used.
  /// Otherwise every cell is converted, in row-major order. Without a type
  /// argument, the cells are returned as strings.
  @optionalTypeArgs
  List<T> asList<T>() => _converter.list<T>(this);

  /// Every row, with each cell converted to `T`.
  @optionalTypeArgs
  List<List<T>> asLists<T>() => [
    for (final row in _rows) [for (final cell in row) _converter.cell<T>(cell)],
  ];

  /// One map per data row, keyed by the header row.
  @optionalTypeArgs
  List<Map<K, V>> asMaps<K, V>() {
    if (_rows.isEmpty) return [];
    final keys = [for (final cell in _rows.first) _converter.cell<K>(cell)];
    return [
      for (var r = 1; r < _rows.length; r++)
        <K, V>{
          for (var c = 0; c < keys.length; c++)
            keys[c]: _converter.cell<V>(_rows[r][c]),
        },
    ];
  }

  /// A map from the first column to the second. The table must have two
  /// columns.
  @optionalTypeArgs
  Map<K, V> asMap<K, V>() {
    if (_rows.isNotEmpty && width != 2) {
      throw ConversionException(
        "Can't convert a table with $width columns to a map; it needs 2.",
      );
    }
    final map = <K, V>{};
    for (final row in _rows) {
      final key = _converter.cell<K>(row[0]);
      if (map.containsKey(key)) {
        throw ConversionException(
          "Can't convert the table to a map: duplicate key \"${row[0]}\".",
        );
      }
      map[key] = _converter.cell<V>(row[1]);
    }
    return map;
  }

  /// The table converted to `T` with a registered `DataTableType<T>.table`,
  /// or with any other conversion that produces exactly `T` (for example
  /// `List<Person>` with an entry type for `Person`).
  T convert<T>() => _converter.table<T>(this);

  /// Compares this (actual) table with [expected], a [DataTable] or a list of
  /// rows, and throws a [TableDiffException] describing the differences.
  void diff(Object expected) {
    final other = switch (expected) {
      final DataTable table => table.raw,
      final List<List<String>> rows => rows,
      final List<Object?> rows => [
        for (final row in rows)
          if (row is List<Object?>)
            [for (final cell in row) '${cell ?? ''}']
          else
            throw ArgumentError.value(expected, 'expected', 'Not a table'),
      ],
      _ => throw ArgumentError.value(expected, 'expected', 'Not a table'),
    };
    final diff = diffTables(other, _rows);
    if (diff != null) throw TableDiffException(diff);
  }

  @override
  bool operator ==(Object other) {
    if (other is! DataTable || other.height != height) return false;
    for (var r = 0; r < height; r++) {
      final a = _rows[r];
      final b = other._rows[r];
      if (a.length != b.length) return false;
      for (var c = 0; c < a.length; c++) {
        if (a[c] != b[c]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hashAll([for (final row in _rows) Object.hashAll(row)]);

  @override
  String toString() => formatTable(_rows);
}
