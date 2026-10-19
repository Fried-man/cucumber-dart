/// Thrown by `DataTable.diff` when two tables differ.
final class TableDiffException implements Exception {
  /// Creates an exception with the formatted [diff].
  TableDiffException(this.diff);

  /// The tables, row by row: `-` marks rows only in the expected table and
  /// `+` rows only in the actual table.
  final String diff;

  @override
  String toString() => 'Tables were not identical:\n$diff';
}

/// Formats [rows] as a Gherkin table, one row per line.
String formatTable(List<List<String>> rows, {List<String>? prefixes}) {
  final widths = <int>[];
  for (final row in rows) {
    for (var c = 0; c < row.length; c++) {
      final length = _escape(row[c]).length;
      if (c >= widths.length) {
        widths.add(length);
      } else if (length > widths[c]) {
        widths[c] = length;
      }
    }
  }
  final lines = <String>[];
  for (var r = 0; r < rows.length; r++) {
    final cells = [
      for (var c = 0; c < rows[r].length; c++)
        _escape(rows[r][c]).padRight(widths[c]),
    ];
    lines.add('${prefixes?[r] ?? ''}| ${cells.join(' | ')} |');
  }
  return lines.join('\n');
}

String _escape(String cell) =>
    cell.replaceAll(r'\', r'\\').replaceAll('|', r'\|').replaceAll('\n', r'\n');

bool _rowEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Diffs [expected] against [actual] row by row (longest common subsequence).
///
/// Returns `null` when they are equal, otherwise the formatted diff.
String? diffTables(List<List<String>> expected, List<List<String>> actual) {
  final n = expected.length;
  final m = actual.length;
  var equal = n == m;
  for (var i = 0; equal && i < n; i++) {
    equal = _rowEquals(expected[i], actual[i]);
  }
  if (equal) return null;

  // lcs[i][j]: length of the LCS of expected[i..] and actual[j..].
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = _rowEquals(expected[i], actual[j])
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final rows = <List<String>>[];
  final prefixes = <String>[];
  var i = 0;
  var j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && _rowEquals(expected[i], actual[j])) {
      rows.add(expected[i++]);
      prefixes.add('    ');
      j++;
    } else if (i < n && (j >= m || lcs[i + 1][j] >= lcs[i][j + 1])) {
      rows.add(expected[i++]);
      prefixes.add('  - ');
    } else {
      rows.add(actual[j++]);
      prefixes.add('  + ');
    }
  }
  return formatTable(rows, prefixes: prefixes);
}
