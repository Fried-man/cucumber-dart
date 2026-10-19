import 'package:cucumber_messages/cucumber_messages.dart' as messages;

/// The shape of a capture group in a regular expression: its source and the
/// capture groups nested in it.
///
/// Groups nested in non-capturing groups and lookarounds are attached to the
/// nearest enclosing capture group, as in the JavaScript `TreeRegexp` of
/// cucumber-expressions.
final class GroupShape {
  GroupShape._(this.source, this.children);

  /// The pattern between the group's parentheses.
  final String source;

  /// The capture groups nested in this one, in order.
  final List<GroupShape> children;
}

/// A matched capture group with its offset in the matched text.
final class MatchedGroup {
  /// Creates a matched group.
  const MatchedGroup(this.value, this.start, this.children);

  /// The captured text, or `null` when the group did not participate.
  final String? value;

  /// The offset of [value] in the matched text, or `null` when the group did
  /// not participate (or its offset cannot be determined).
  final int? start;

  /// The nested capture groups.
  final List<MatchedGroup> children;

  /// The end offset (exclusive), when known.
  int? get end {
    final v = value;
    final s = start;
    return v == null || s == null ? null : s + v.length;
  }

  /// The values passed to a parameter type transformer: the values of the
  /// children, or `[value]` when there are none.
  List<String?> get values =>
      children.isEmpty ? [value] : [for (final child in children) child.value];

  /// This group as a Cucumber Messages `Group`.
  messages.Group toMessage() => messages.Group(
    value: value,
    start: value == null ? null : start,
    children: children.isEmpty
        ? null
        : [for (final child in children) child.toMessage()],
  );

  @override
  String toString() => 'MatchedGroup($value@$start, $children)';
}

/// A regular expression that reports the start offset of every capture group.
///
/// Dart's `RegExpMatch` only exposes the offsets of the whole match. To find
/// nested group offsets, the pattern is rewritten so that every piece of text
/// between groups is itself captured; a group's start is then the sum of the
/// lengths of the captures before it (design §11.1):
///
/// - Quantified groups capture their last iteration, so their start is derived
///   from the end of a capture around the whole quantified term.
/// - Alternatives are measured independently; only the one that participated
///   has non-null captures.
/// - Numbered back-references are renumbered.
/// - Lookaround contents are measured from the current position (lookahead) or
///   backwards from it (lookbehind).
///
/// If the pattern cannot be rewritten, groups other than the root get a `null`
/// start.
final class TreeRegexp {
  /// Analyses [regexp].
  factory TreeRegexp(RegExp regexp) {
    final _Alternation ast;
    final List<_GroupNode> capturing;
    try {
      final parser = _Parser(regexp.pattern);
      ast = parser.parse();
      capturing = parser.capturingGroups;
    } on FormatException {
      return TreeRegexp._fallback(regexp);
    }
    final root = GroupShape._(regexp.pattern, _shapes(ast));
    try {
      final emitter = _Emitter();
      final layout = emitter.emitAlternation(ast);
      final rewritten = RegExp(
        emitter.render(),
        multiLine: regexp.isMultiLine,
        caseSensitive: regexp.isCaseSensitive,
        unicode: regexp.isUnicode,
        dotAll: regexp.isDotAll,
      );
      return TreeRegexp._(regexp, root, rewritten, layout, [
        for (final group in capturing) emitter.indexOf[group]!,
      ], ast);
    } on FormatException {
      return TreeRegexp._(regexp, root, null, null, const [], ast);
    }
  }

  TreeRegexp._(
    this.regexp,
    this.root,
    this._rewritten,
    this._layout,
    this._newIndexes,
    this._ast,
  );

  TreeRegexp._fallback(this.regexp)
    : root = GroupShape._(regexp.pattern, const []),
      _rewritten = null,
      _layout = null,
      _newIndexes = const [],
      _ast = null;

  /// The original regular expression.
  final RegExp regexp;

  /// The tree of capture groups. Its children are the top-level groups.
  final GroupShape root;

  final RegExp? _rewritten;
  final _LAlternation? _layout;

  /// New group index of each original capture group, by original number - 1.
  final List<int> _newIndexes;
  final _Alternation? _ast;

  /// Matches [text], returning the root group (the whole match) with every
  /// capture group nested in it, or `null` when [text] does not match.
  MatchedGroup? match(String text) {
    final rewritten = _rewritten;
    final layout = _layout;
    final ast = _ast;
    if (rewritten == null || layout == null || ast == null) {
      final match = regexp.firstMatch(text);
      if (match == null) return null;
      var next = 1;
      MatchedGroup build(GroupShape shape) {
        final index = next++;
        return MatchedGroup(match.group(index), null, [
          for (final child in shape.children) build(child),
        ]);
      }

      return MatchedGroup(match.group(0), match.start, [
        for (final child in root.children) build(child),
      ]);
    }

    final match = rewritten.firstMatch(text);
    if (match == null) return null;
    final starts = <_GroupNode, int>{};
    _walkAlternation(layout, match.start, match, starts);
    MatchedGroup build(_GroupNode node) {
      final value = match.group(_newIndexes[node.number! - 1]);
      return MatchedGroup(value, value == null ? null : starts[node], [
        for (final child in _capturingChildren(node.body)) build(child),
      ]);
    }

    return MatchedGroup(match.group(0), match.start, [
      for (final child in _capturingChildren(ast)) build(child),
    ]);
  }
}

List<GroupShape> _shapes(_Alternation alternation) => [
  for (final group in _capturingChildren(alternation))
    GroupShape._(group.source, _shapes(group.body)),
];

/// The capture groups nested directly in [alternation], looking through
/// non-capturing groups and lookarounds.
List<_GroupNode> _capturingChildren(_Alternation alternation) {
  final result = <_GroupNode>[];
  void visit(_Alternation alt) {
    for (final sequence in alt.alternatives) {
      for (final term in sequence.terms) {
        final node = term.node;
        if (node is _GroupNode) {
          if (node.isCapturing) {
            result.add(node);
          } else {
            visit(node.body);
          }
        }
      }
    }
  }

  visit(alternation);
  return result;
}

int _length(RegExpMatch match, int index) => match.group(index)?.length ?? 0;

void _walkAlternation(
  _LAlternation alternation,
  int position,
  RegExpMatch match,
  Map<_GroupNode, int> starts,
) {
  for (final sequence in alternation.sequences) {
    var p = position;
    for (final item in sequence) {
      switch (item) {
        case _LRun(:final measure):
          p += _length(match, measure);
        case _LGroup(:final node, :final index, :final body):
          final value = match.group(index);
          if (value != null) {
            starts[node] = p;
            _walkAlternation(body, p, match, starts);
            p += value.length;
          }
        case _LMeasured(:final measure, :final body):
          final value = match.group(measure);
          if (value != null) {
            _walkAlternation(body, p, match, starts);
            p += value.length;
          }
        case _LQuantified(
          :final measure,
          :final inner,
          :final node,
          :final body,
        ):
          final outer = match.group(measure);
          if (outer != null) {
            final last = match.group(inner);
            if (last != null) {
              final start = p + outer.length - last.length;
              if (node != null) starts[node] = start;
              _walkAlternation(body, start, match, starts);
            }
            p += outer.length;
          }
        case _LLookaround(:final measure, :final behind, :final body):
          final value = match.group(measure);
          if (value != null) {
            _walkAlternation(
              body,
              behind ? p - value.length : p,
              match,
              starts,
            );
          }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

final class _Alternation {
  _Alternation(this.alternatives);

  final List<_Sequence> alternatives;

  bool get hasCapture => alternatives.any((s) => s.hasCapture);
}

final class _Sequence {
  _Sequence(this.terms);

  final List<_Term> terms;

  bool get hasCapture => terms.any((t) => t.hasCapture);
}

final class _Term {
  _Term(this.node, this.quantifier);

  final Object node; // _Atom or _GroupNode
  final String quantifier;

  bool get hasCapture {
    final n = node;
    return n is _GroupNode && (n.isCapturing || n.body.hasCapture);
  }
}

final class _Atom {
  _Atom(this.source, [this.backreference]);

  final String source;

  /// The group number of a numbered back-reference.
  final int? backreference;
}

enum _GroupKind {
  capturing,
  named,
  nonCapturing,
  lookahead,
  negativeLookahead,
  lookbehind,
  negativeLookbehind,
}

final class _GroupNode {
  _GroupNode(this.kind, this.prefix, this.number);

  final _GroupKind kind;

  /// The text after `(`: `''`, `'?:'`, `'?='`, `'?<name>'`, …
  final String prefix;

  /// The original group number, for capture groups.
  final int? number;
  late final _Alternation body;
  late final String source;

  bool get isCapturing =>
      kind == _GroupKind.capturing || kind == _GroupKind.named;

  bool get isLookaround =>
      kind == _GroupKind.lookahead ||
      kind == _GroupKind.negativeLookahead ||
      kind == _GroupKind.lookbehind ||
      kind == _GroupKind.negativeLookbehind;

  bool get isLookbehind =>
      kind == _GroupKind.lookbehind || kind == _GroupKind.negativeLookbehind;
}

final RegExp _braceQuantifier = RegExp(r'\{\d+(?:,\d*)?\}');

final class _Parser {
  _Parser(this.pattern);

  final String pattern;
  int _pos = 0;
  final List<_GroupNode> capturingGroups = [];

  _Alternation parse() {
    final result = _alternation();
    if (_pos != pattern.length) {
      throw FormatException('Unmatched )', pattern, _pos);
    }
    return result;
  }

  _Alternation _alternation() {
    final alternatives = [_sequence()];
    while (_pos < pattern.length && pattern[_pos] == '|') {
      _pos++;
      alternatives.add(_sequence());
    }
    return _Alternation(alternatives);
  }

  _Sequence _sequence() {
    final terms = <_Term>[];
    while (_pos < pattern.length) {
      final c = pattern[_pos];
      if (c == '|' || c == ')') break;
      final node = _node();
      terms.add(_Term(node, _quantifier()));
    }
    return _Sequence(terms);
  }

  Object _node() {
    final start = _pos;
    final c = pattern[_pos];
    if (c == '(') return _group();
    if (c == '[') {
      _pos++;
      if (_pos < pattern.length && pattern[_pos] == '^') _pos++;
      while (_pos < pattern.length && pattern[_pos] != ']') {
        if (pattern[_pos] == r'\') _pos++;
        _pos++;
      }
      if (_pos >= pattern.length) {
        throw FormatException('Unterminated character class', pattern, start);
      }
      _pos++;
      return _Atom(pattern.substring(start, _pos));
    }
    if (c == r'\') return _escape();
    _pos++;
    return _Atom(c);
  }

  _Atom _escape() {
    final start = _pos;
    _pos++;
    if (_pos >= pattern.length) {
      throw FormatException('Trailing backslash', pattern, start);
    }
    final c = pattern[_pos];
    final code = c.codeUnitAt(0);
    if (code >= 0x31 && code <= 0x39) {
      // \1 .. \99: a back-reference.
      while (_pos < pattern.length &&
          pattern.codeUnitAt(_pos) >= 0x30 &&
          pattern.codeUnitAt(_pos) <= 0x39) {
        _pos++;
      }
      final source = pattern.substring(start, _pos);
      return _Atom(source, int.parse(source.substring(1)));
    }
    _pos++;
    if ((c == 'k' && _peek('<')) ||
        ((c == 'u' || c == 'p' || c == 'P') && _peek('{'))) {
      final close = c == 'k' ? '>' : '}';
      final end = pattern.indexOf(close, _pos);
      if (end < 0) throw FormatException('Unterminated escape', pattern, start);
      _pos = end + 1;
    }
    return _Atom(pattern.substring(start, _pos));
  }

  bool _peek(String s) => pattern.startsWith(s, _pos);

  _GroupNode _group() {
    final open = _pos;
    _pos++;
    final _GroupKind kind;
    var prefix = '';
    if (_peek('?:')) {
      kind = _GroupKind.nonCapturing;
      prefix = '?:';
    } else if (_peek('?=')) {
      kind = _GroupKind.lookahead;
      prefix = '?=';
    } else if (_peek('?!')) {
      kind = _GroupKind.negativeLookahead;
      prefix = '?!';
    } else if (_peek('?<=')) {
      kind = _GroupKind.lookbehind;
      prefix = '?<=';
    } else if (_peek('?<!')) {
      kind = _GroupKind.negativeLookbehind;
      prefix = '?<!';
    } else if (_peek('?<')) {
      final end = pattern.indexOf('>', _pos);
      if (end < 0) throw FormatException('Unterminated group name', pattern);
      kind = _GroupKind.named;
      prefix = pattern.substring(_pos, end + 1);
    } else if (_peek('?')) {
      throw FormatException('Unsupported group', pattern, _pos);
    } else {
      kind = _GroupKind.capturing;
    }
    _pos += prefix.length;
    final capturing = kind == _GroupKind.capturing || kind == _GroupKind.named;
    final node = _GroupNode(
      kind,
      prefix,
      capturing ? capturingGroups.length + 1 : null,
    );
    if (capturing) capturingGroups.add(node);
    node.body = _alternation();
    if (_pos >= pattern.length || pattern[_pos] != ')') {
      throw FormatException('Unmatched (', pattern, open);
    }
    node.source = pattern.substring(open + 1, _pos);
    _pos++;
    return node;
  }

  String _quantifier() {
    if (_pos >= pattern.length) return '';
    final start = _pos;
    final c = pattern[_pos];
    if (c == '*' || c == '+' || c == '?') {
      _pos++;
    } else if (c == '{') {
      final match = _braceQuantifier.matchAsPrefix(pattern, _pos);
      if (match == null) return '';
      _pos = match.end;
    } else {
      return '';
    }
    if (_pos < pattern.length && pattern[_pos] == '?') _pos++;
    return pattern.substring(start, _pos);
  }
}

// ---------------------------------------------------------------------------
// Rewriting
// ---------------------------------------------------------------------------

final class _LAlternation {
  _LAlternation(this.sequences);

  final List<List<_LItem>> sequences;
}

sealed class _LItem {}

/// Text without capture groups, captured as [measure].
final class _LRun extends _LItem {
  _LRun(this.measure);

  final int measure;
}

/// An unquantified capture group.
final class _LGroup extends _LItem {
  _LGroup(this.node, this.index, this.body);

  final _GroupNode node;
  final int index;
  final _LAlternation body;
}

/// An unquantified non-capturing group containing captures, turned into a
/// capture [measure].
final class _LMeasured extends _LItem {
  _LMeasured(this.measure, this.body);

  final int measure;
  final _LAlternation body;
}

/// A quantified group containing captures: [measure] captures the whole
/// quantified term, [inner] its last iteration.
final class _LQuantified extends _LItem {
  _LQuantified(this.measure, this.inner, this.node, this.body);

  final int measure;
  final int inner;
  final _GroupNode? node;
  final _LAlternation body;
}

/// A lookaround containing captures; [measure] captures its contents.
final class _LLookaround extends _LItem {
  _LLookaround(this.measure, this.behind, this.body);

  final int measure;
  final bool behind;
  final _LAlternation body;
}

final class _Backreference {
  _Backreference(this.number, this.source);

  final int number;
  final String source;
}

final class _Emitter {
  final List<Object> _pieces = []; // String or _Backreference
  int _nextIndex = 1;
  final Map<_GroupNode, int> indexOf = {};

  int _open([String prefix = '']) {
    _pieces.add('($prefix');
    return _nextIndex++;
  }

  void _close([String suffix = '']) => _pieces.add(')$suffix');

  String render() {
    final byNumber = {
      for (final entry in indexOf.entries) entry.key.number!: entry.value,
    };
    return [
      for (final piece in _pieces)
        if (piece is _Backreference)
          byNumber.containsKey(piece.number)
              ? '\\${byNumber[piece.number]}'
              : piece.source
        else
          piece as String,
    ].join();
  }

  _LAlternation emitAlternation(_Alternation alternation) {
    final sequences = <List<_LItem>>[];
    for (var i = 0; i < alternation.alternatives.length; i++) {
      if (i > 0) _pieces.add('|');
      sequences.add(_emitSequence(alternation.alternatives[i]));
    }
    return _LAlternation(sequences);
  }

  List<_LItem> _emitSequence(_Sequence sequence) {
    final items = <_LItem>[];
    final run = <Object>[];

    void flush() {
      if (run.isEmpty) return;
      final measure = _open();
      _pieces.addAll(run);
      _close();
      items.add(_LRun(measure));
      run.clear();
    }

    for (final term in sequence.terms) {
      if (!term.hasCapture) {
        _verbatim(term.node, run);
        run.add(term.quantifier);
        continue;
      }
      flush();
      final node = term.node as _GroupNode;
      if (node.isLookaround) {
        _pieces.add('(${node.prefix}');
        final measure = _open();
        final body = emitAlternation(node.body);
        _close();
        _close(term.quantifier);
        items.add(_LLookaround(measure, node.isLookbehind, body));
      } else if (term.quantifier.isEmpty) {
        if (node.isCapturing) {
          final index = _open(node.prefix);
          indexOf[node] = index;
          final body = emitAlternation(node.body);
          _close();
          items.add(_LGroup(node, index, body));
        } else {
          final measure = _open();
          final body = emitAlternation(node.body);
          _close();
          items.add(_LMeasured(measure, body));
        }
      } else {
        final measure = _open();
        final inner = _open(node.isCapturing ? node.prefix : '');
        if (node.isCapturing) indexOf[node] = inner;
        final body = emitAlternation(node.body);
        _close(term.quantifier);
        _close();
        items.add(
          _LQuantified(measure, inner, node.isCapturing ? node : null, body),
        );
      }
    }
    flush();
    return items;
  }

  /// Appends [node] (which contains no capture groups) to [out] unchanged,
  /// except for back-references, which are renumbered when rendered.
  void _verbatim(Object node, List<Object> out) {
    if (node is _Atom) {
      final backreference = node.backreference;
      out.add(
        backreference == null
            ? node.source
            : _Backreference(backreference, node.source),
      );
      return;
    }
    final group = node as _GroupNode;
    out.add('(${group.prefix}');
    for (var i = 0; i < group.body.alternatives.length; i++) {
      if (i > 0) out.add('|');
      for (final term in group.body.alternatives[i].terms) {
        _verbatim(term.node, out);
        out.add(term.quantifier);
      }
    }
    out.add(')');
  }
}
