import 'dart:convert';

import 'package:cucumber_ci_environment/cucumber_ci_environment.dart';
import 'package:cucumber_ci_environment/src/evaluate_variable_expression.dart';
import 'package:cucumber_ci_environment/src/remove_user_info_from_url.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:test/test.dart';

void main() {
  // Ported from evaluateVariableExpressionTest.ts and VariableExpressionTest.java.
  group('evaluateVariableExpression', () {
    test('returns null when a variable is undefined', () {
      expect(evaluateVariableExpression(r'hello-${SOME_VAR}', {}), isNull);
    });

    test('returns null for a null expression', () {
      expect(evaluateVariableExpression(null, {'A': 'b'}), isNull);
    });

    test('gets a value without replacement', () {
      expect(
        evaluateVariableExpression(r'${SOME_VAR}', {'SOME_VAR': 'some_value'}),
        'some_value',
      );
    });

    test('does not evaluate values', () {
      expect(
        evaluateVariableExpression(r'${SOME_VAR}', {
          'SOME_VAR': r'${SOME_VAR}',
        }),
        r'${SOME_VAR}',
      );
    });

    test('captures a group', () {
      expect(
        evaluateVariableExpression(r'${SOME_REF/refs\/heads\/(.*)/\1}', {
          'SOME_REF': 'refs/heads/main',
        }),
        'main',
      );
    });

    test('returns null when the pattern does not match', () {
      expect(
        evaluateVariableExpression(r'${SOME_REF/refs\/tags\/(.*)/\1}', {
          'SOME_REF': 'refs/heads/main',
        }),
        isNull,
      );
    });

    test('returns null for an invalid pattern', () {
      expect(
        evaluateVariableExpression(r'${SOME_REF/(/\1}', {'SOME_REF': 'x'}),
        isNull,
      );
    });

    test('works with a star wildcard in the variable name', () {
      expect(
        evaluateVariableExpression(r'${GO_SCM_*_PR_BRANCH/.*:(.*)/\1}', {
          'GO_SCM_MY_MATERIAL_PR_BRANCH': 'ashwankthkumar:feature-1',
        }),
        'feature-1',
      );
    });

    test('matches the whole name with a star wildcard', () {
      expect(
        evaluateVariableExpression(r'${GO_SCM_*_PR_BRANCH}', {
          'X_GO_SCM_MY_MATERIAL_PR_BRANCH_Y': 'nope',
        }),
        isNull,
      );
    });

    test('evaluates a complex expression', () {
      expect(
        evaluateVariableExpression(
          r'hello-${VAR1}-${VAR2/(.*) (.*)/\2-\1}-world',
          {'VAR1': 'amazing', 'VAR2': 'gorgeous beautiful'},
        ),
        'hello-amazing-beautiful-gorgeous-world',
      );
    });

    test('does not evaluate values in a complex expression', () {
      expect(
        evaluateVariableExpression(
          r'hello-${VAR1}-${VAR2/(.*) (.*)/\2-\1}-world',
          {'VAR1': r'${VAR1}', 'VAR2': r'${VAR2a} ${VAR2b}'},
        ),
        r'hello-${VAR1}-${VAR2b}-${VAR2a}-world',
      );
    });
  });

  // Ported from removeUserInfoFromUrlTest.ts.
  group('removeUserInfoFromUrl', () {
    test('returns an empty string for an empty string', () {
      expect(removeUserInfoFromUrl(''), '');
    });

    test('leaves values that are not URLs intact', () {
      expect(removeUserInfoFromUrl('pretty safe'), 'pretty safe');
      expect(
        removeUserInfoFromUrl('git@github.com:owner/repo.git'),
        'git@github.com:owner/repo.git',
      );
    });

    test('leaves URLs without credentials intact', () {
      expect(
        removeUserInfoFromUrl('https://example.com/git/repo.git'),
        'https://example.com/git/repo.git',
      );
    });

    test('removes a user name', () {
      expect(
        removeUserInfoFromUrl('http://aslak@example.com/git/repo.git'),
        'http://example.com/git/repo.git',
      );
    });

    test('removes a user name and password', () {
      expect(
        removeUserInfoFromUrl('ssh://login:password@example.com/git/repo.git'),
        'ssh://example.com/git/repo.git',
      );
    });
  });

  group('detectCiEnvironment', () {
    const gitHub = {
      'GITHUB_SERVER_URL': 'https://github.com',
      'GITHUB_REPOSITORY': 'owner/repo',
      'GITHUB_RUN_ID': '42',
      'GITHUB_SHA': 'merge-commit',
      'GITHUB_HEAD_REF': 'feature',
    };

    test('detects nothing outside CI', () {
      expect(detectCiEnvironment({}), isNull);
      expect(detectCiEnvironment({'PATH': '/usr/bin', 'HOME': '/'}), isNull);
    });

    test('omits an empty branch', () {
      final ci = detectCiEnvironment({
        ...gitHub,
        'GITHUB_HEAD_REF': '',
        'GITHUB_EVENT_NAME': 'push',
      });
      expect(
        ci,
        const messages.Ci(
          name: 'GitHub Actions',
          url: 'https://github.com/owner/repo/actions/runs/42',
          buildNumber: '42',
          git: messages.Git(
            remote: 'https://github.com/owner/repo.git',
            revision: 'merge-commit',
          ),
        ),
      );
    });

    test('reads the head commit of a pull request from the event', () {
      final paths = <String>[];
      final ci = detectCiEnvironment(
        {
          ...gitHub,
          'GITHUB_EVENT_NAME': 'pull_request',
          'GITHUB_EVENT_PATH': '/event.json',
        },
        readFile: (path) {
          paths.add(path);
          return jsonEncode({
            'pull_request': {
              'head': {'sha': 'head-commit'},
            },
          });
        },
      );
      expect(paths, ['/event.json']);
      expect(ci?.git?.revision, 'head-commit');
      expect(ci?.git?.branch, 'feature');
    });

    test('falls back to GITHUB_SHA when the event cannot be used', () {
      for (final event in [null, 'not json', '{}', '{"pull_request":{}}']) {
        final ci = detectCiEnvironment({
          ...gitHub,
          'GITHUB_EVENT_NAME': 'pull_request',
          'GITHUB_EVENT_PATH': '/event.json',
        }, readFile: (_) => event);
        expect(ci?.git?.revision, 'merge-commit', reason: '$event');
      }
      final withoutPath = detectCiEnvironment({
        ...gitHub,
        'GITHUB_EVENT_NAME': 'pull_request',
      }, readFile: (_) => fail('must not read'));
      expect(withoutPath?.git?.revision, 'merge-commit');
    });

    test('falls back to GITHUB_SHA when the event file does not exist', () {
      final ci = detectCiEnvironment({
        ...gitHub,
        'GITHUB_EVENT_NAME': 'pull_request',
        'GITHUB_EVENT_PATH': 'does/not/exist.json',
      });
      expect(ci?.git?.revision, 'merge-commit');
    });
  });
}
