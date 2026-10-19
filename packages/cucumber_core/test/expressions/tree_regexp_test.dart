import 'package:cucumber_core/src/expressions/tree_regexp.dart';
import 'package:test/test.dart';

/// Formats a group tree as `value@start[children]` for compact assertions.
String _format(MatchedGroup group) {
  final children = group.children.isEmpty
      ? ''
      : '[${group.children.map(_format).join(', ')}]';
  final value = group.value == null ? '-' : '${group.value}@${group.start}';
  return '$value$children';
}

String? _match(String pattern, String text) {
  final group = TreeRegexp(RegExp(pattern)).match(text);
  return group == null ? null : _format(group);
}

/// Checks every reported offset against the value it claims to locate.
void _expectConsistent(String pattern, String text) {
  final group = TreeRegexp(RegExp(pattern)).match(text)!;
  void check(MatchedGroup g) {
    if (g.value != null && g.start != null) {
      expect(
        text.substring(g.start!, g.end),
        g.value,
        reason: '$pattern on "$text"',
      );
    }
    g.children.forEach(check);
  }

  check(group);
}

void main() {
  test('reports offsets of top-level groups', () {
    expect(
      _match(r'^a (.*?) with (.*?)$', 'a step with multiple definitions'),
      'a step with multiple definitions@0'
      '[step@2, multiple definitions@12]',
    );
  });

  test('reports offsets of nested groups (CCK parameter-types)', () {
    expect(
      _match(
        r'^(([A-Z]{3})-([A-Z]{3})) has been delayed$',
        'LHR-CDG has been '
            'delayed',
      ),
      'LHR-CDG has been delayed@0[LHR-CDG@0[LHR@0, CDG@4]]',
    );
  });

  test('non-participating groups have no value or start', () {
    expect(
      _match(r'^a (.*?)(?: and a (.*?))?(?: and a (.*?))?$', 'a cucumber'),
      'a cucumber@0[cucumber@2, -, -]',
    );
    expect(
      _match(
        r'^a (.*?)(?: and a (.*?))?(?: and a (.*?))?$',
        'a cucumber and a zucchini and a gourd',
      ),
      'a cucumber and a zucchini and a gourd@0'
      '[cucumber@2, zucchini@17, gourd@32]',
    );
  });

  test('handles the built-in string parameter type (CCK attachments)', () {
    const string = r'''("([^"\\]*(\\.[^"\\]*)*)"|'([^'\\]*(\\.[^'\\]*)*)')''';
    expect(
      _match('^the string $string is logged\$', 'the string "hello" is logged'),
      'the string "hello" is logged@0[“hello”@11[hello@12[-], -[-]]]'
          .replaceAll('“', '"')
          .replaceAll('”', '"'),
    );
    expect(
      _match('^x $string\$', "x 'it\\'s'"),
      "x 'it\\'s'@0['it\\'s'@2[-[-], it\\'s@3[\\'s@5]]]",
    );
  });

  test('quantified groups report their last iteration', () {
    expect(_match(r'^(ab)+$', 'ababab'), 'ababab@0[ab@4]');
    expect(_match(r'^(?:x(\d))*y$', 'x1x2x3y'), 'x1x2x3y@0[3@5]');
    expect(_match(r'^a(b)?c$', 'ac'), 'ac@0[-]');
    expect(_match(r'^((a)|(b))+$', 'aab'), 'aab@0[b@2[-, b@2]]');
  });

  test('alternation', () {
    expect(_match(r'^(?:(a+)|x(b+))c$', 'xbbc'), 'xbbc@0[-, bb@1]');
    expect(
      _match(r'^I have (\d+|many) cukes$', 'I have 42 cukes'),
      'I have 42 cukes@0[42@7]',
    );
  });

  test('renumbers back-references', () {
    expect(_match(r'^(\w)x\1(y)$', 'axay'), 'axay@0[a@0, y@3]');
    expect(_match(r'''^(?<q>["'])(.*)\k<q>$''', '"hi"'), '"hi"@0["@0, hi@1]');
  });

  test('lookarounds', () {
    expect(_match(r'^(?=(\d+))\d+ (x)$', '12 x'), '12 x@0[12@0, x@3]');
    expect(_match(r'^ab(?<=(b))(c)$', 'abc'), 'abc@0[b@1, c@2]');
  });

  test('unanchored matches start where the match starts', () {
    expect(_match(r'(b)(c)', 'abcd'), 'bc@1[b@1, c@2]');
  });

  test('character classes and escapes are not groups', () {
    expect(_match(r'^\((\d)\)[()](x)$', '(1)(x'), '(1)(x@0[1@1, x@4]');
    expect(_match(r'^a{2}(b){1,2}$', 'aabb'), 'aabb@0[b@3]');
  });

  test('exposes the group tree', () {
    final tree = TreeRegexp(RegExp(r'^(a(b))(?:(c))(?=(d))$'));
    expect(tree.root.children.map((g) => g.source), ['a(b)', 'c', 'd']);
    expect(tree.root.children.first.children.single.source, 'b');
  });

  test('offsets are consistent with values', () {
    const cases = {
      r'^(\d+) (?:cukes?|(cucumbers)) in my (belly|(stomach))$':
          '12 cucumbers in my stomach',
      r'^((?:a|b)+)(c*)((d)(e)?)+$': 'ababccdde',
      r'(x)?(y)(z)?': '--yz--',
      r'^([a-z]+)@(([a-z]+)\.)+([a-z]{2,})$': 'me@mail.example.com',
    };
    cases.forEach(_expectConsistent);
  });

  test('returns null when there is no match', () {
    expect(_match(r'^a$', 'b'), isNull);
  });
}
