/// A private port of the JavaScript implementation of
/// [cucumber/tag-expressions](https://github.com/cucumber/tag-expressions)
/// (ADR-0007).
///
/// It is tested against the upstream shared test data and will be replaced by
/// an official Dart package when one exists. It is not exported.
library;

/// Thrown when a tag expression cannot be parsed.
final class TagExpressionException implements Exception {
  /// Creates an exception with the upstream error [message].
  TagExpressionException(this.message);

  /// The error message, identical to the upstream implementations'.
  final String message;

  @override
  String toString() => message;
}

/// A parsed tag expression.
sealed class TagExpression {
  const TagExpression();

  /// Parses the infix boolean expression [infix] with Dijkstra's shunting-yard
  /// algorithm.
  ///
  /// An empty (or blank) expression matches everything.
  ///
  /// Throws a [TagExpressionException] for invalid expressions.
  static TagExpression parse(String infix) => _Parser(infix).parse();

  /// Whether this expression is true when exactly [tags] are present.
  bool evaluate(Iterable<String> tags);

  /// The canonical, fully parenthesised form of this expression.
  @override
  String toString();
}

const Map<String, int> _precedence = {
  '(': -2,
  ')': -1,
  'or': 0,
  'and': 1,
  'not': 2,
};

const Map<String, String> _associativity = {
  'or': 'left',
  'and': 'left',
  'not': 'right',
};

enum _TokenType { operand, operator }

final class _Parser {
  _Parser(this.infix);

  final String infix;

  TagExpression parse() {
    final tokens = _tokenize(infix);
    if (tokens.isEmpty) return const _True();

    final expressions = <TagExpression>[];
    final operators = <String>[];
    var expected = _TokenType.operand;

    for (final token in tokens) {
      if (_isUnary(token)) {
        _check(expected, _TokenType.operand);
        operators.add(token);
        expected = _TokenType.operand;
      } else if (_isBinary(token)) {
        _check(expected, _TokenType.operator);
        while (operators.isNotEmpty &&
            _isOperator(operators.last) &&
            ((_associativity[token] == 'left' &&
                    _precedence[token]! <= _precedence[operators.last]!) ||
                (_associativity[token] == 'right' &&
                    _precedence[token]! < _precedence[operators.last]!))) {
          _pushExpression(operators.removeLast(), expressions);
        }
        operators.add(token);
        expected = _TokenType.operand;
      } else if (token == '(') {
        _check(expected, _TokenType.operand);
        operators.add(token);
        expected = _TokenType.operand;
      } else if (token == ')') {
        _check(expected, _TokenType.operator);
        while (operators.isNotEmpty && operators.last != '(') {
          _pushExpression(operators.removeLast(), expressions);
        }
        if (operators.isEmpty) {
          throw _syntaxError('Unmatched ).');
        }
        if (operators.last == '(') {
          operators.removeLast();
        }
        expected = _TokenType.operator;
      } else {
        _check(expected, _TokenType.operand);
        _pushExpression(token, expressions);
        expected = _TokenType.operator;
      }
    }

    while (operators.isNotEmpty) {
      if (operators.last == '(') {
        throw _syntaxError('Unmatched (.');
      }
      _pushExpression(operators.removeLast(), expressions);
    }

    return expressions.removeLast();
  }

  void _check(_TokenType expected, _TokenType actual) {
    if (expected != actual) {
      throw _syntaxError('Expected ${expected.name}.');
    }
  }

  void _pushExpression(String token, List<TagExpression> stack) {
    switch (token) {
      case 'and':
        final right = _popOperand(stack);
        stack.add(_And(_popOperand(stack), right));
      case 'or':
        final right = _popOperand(stack);
        stack.add(_Or(_popOperand(stack), right));
      case 'not':
        stack.add(_Not(_popOperand(stack)));
      default:
        stack.add(_Literal(token));
    }
  }

  TagExpression _popOperand(List<TagExpression> stack) {
    if (stack.isEmpty) throw _syntaxError('Expected operand.');
    return stack.removeLast();
  }

  TagExpressionException _syntaxError(String problem) => TagExpressionException(
    'Tag expression "$infix" could not be parsed because of syntax error: '
    '$problem',
  );

  List<String> _tokenize(String expression) {
    final tokens = <String>[];
    var escaped = false;
    final token = StringBuffer();
    for (var i = 0; i < expression.length; i++) {
      final c = expression[i];
      if (escaped) {
        if (c == '(' || c == ')' || c == r'\' || _isWhitespace(c)) {
          token.write(c);
          escaped = false;
        } else {
          throw TagExpressionException(
            'Tag expression "$expression" could not be parsed because of '
            'syntax error: Illegal escape before "$c".',
          );
        }
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '(' || c == ')' || _isWhitespace(c)) {
        if (token.isNotEmpty) {
          tokens.add(token.toString());
          token.clear();
        }
        if (!_isWhitespace(c)) tokens.add(c);
      } else {
        token.write(c);
      }
    }
    if (token.isNotEmpty) tokens.add(token.toString());
    return tokens;
  }
}

final RegExp _whitespace = RegExp(r'\s');

bool _isWhitespace(String c) => _whitespace.hasMatch(c);

bool _isUnary(String token) => token == 'not';

bool _isBinary(String token) => token == 'or' || token == 'and';

bool _isOperator(String token) => _associativity.containsKey(token);

final class _Literal extends TagExpression {
  const _Literal(this.value);

  final String value;

  @override
  bool evaluate(Iterable<String> tags) => tags.contains(value);

  @override
  String toString() => value
      .replaceAll(r'\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)')
      .replaceAll(_whitespace, r'\ ');
}

final class _Or extends TagExpression {
  const _Or(this.left, this.right);

  final TagExpression left;
  final TagExpression right;

  @override
  bool evaluate(Iterable<String> tags) =>
      left.evaluate(tags) || right.evaluate(tags);

  @override
  String toString() => '( $left or $right )';
}

final class _And extends TagExpression {
  const _And(this.left, this.right);

  final TagExpression left;
  final TagExpression right;

  @override
  bool evaluate(Iterable<String> tags) =>
      left.evaluate(tags) && right.evaluate(tags);

  @override
  String toString() => '( $left and $right )';
}

final class _Not extends TagExpression {
  const _Not(this.expression);

  final TagExpression expression;

  @override
  bool evaluate(Iterable<String> tags) => !expression.evaluate(tags);

  @override
  String toString() {
    // Binary operators already parenthesise themselves.
    if (expression is _And || expression is _Or) return 'not $expression';
    return 'not ( $expression )';
  }
}

final class _True extends TagExpression {
  const _True();

  @override
  bool evaluate(Iterable<String> tags) => true;

  @override
  String toString() => '';
}
