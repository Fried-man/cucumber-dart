/// Matches a variable reference `${NAME}` or `${NAME/pattern/replacement}`.
///
/// A `/` preceded by a backslash belongs to the variable name.
final RegExp _variablePattern = RegExp(r'\$\{(.*?)(?:(?<!\\)/(.*)/(.*))?\}');

/// Evaluates a variable [expression] of a CI environment template against
/// [env], or returns `null` when a variable is not set or a pattern does not
/// match.
///
/// Each `${NAME}` in [expression] is replaced with the value of the
/// environment variable `NAME`. The form `${NAME/pattern/replacement}`, like
/// the `s` command of sed, searches the value for the regular expression
/// `pattern` (in which `\/` stands for `/`) and is replaced with
/// `replacement`, in which `\1`, `\2`, ... stand for the captured groups.
///
/// A `*` in `NAME` matches any characters, so `${GO_SCM_*_PR_BRANCH}` reads
/// the first variable whose whole name matches (GoCD names variables after
/// its materials).
String? evaluateVariableExpression(
  String? expression,
  Map<String, String> env,
) {
  if (expression == null) {
    return null;
  }
  final result = StringBuffer();
  var end = 0;
  for (final match in _variablePattern.allMatches(expression)) {
    result.write(expression.substring(end, match.start));
    end = match.end;

    final variable = match[1]!;
    final value = _valueOf(variable, env);
    if (value == null) {
      return null;
    }
    final pattern = match[2];
    if (pattern == null || pattern.isEmpty) {
      result.write(value);
      continue;
    }
    final RegExp regExp;
    try {
      regExp = RegExp(pattern.replaceAll(r'\/', '/'));
    } on FormatException {
      return null;
    }
    final valueMatch = regExp.firstMatch(value);
    if (valueMatch == null) {
      return null;
    }
    var replacement = match[3]!;
    // Highest group first, so that `\1` does not replace the start of `\10`.
    for (var group = valueMatch.groupCount; group >= 1; group--) {
      replacement = replacement.replaceAll('\\$group', valueMatch[group] ?? '');
    }
    result.write(replacement);
  }
  result.write(expression.substring(end));
  return result.toString();
}

String? _valueOf(String variable, Map<String, String> env) {
  if (variable.contains('*')) {
    final name = RegExp(
      '^${variable.split('*').map(RegExp.escape).join('.*')}\$',
    );
    for (final MapEntry(:key, :value) in env.entries) {
      if (name.hasMatch(key)) {
        return value;
      }
    }
  }
  return env[variable];
}
