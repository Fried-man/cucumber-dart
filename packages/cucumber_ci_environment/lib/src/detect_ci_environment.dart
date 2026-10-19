import 'dart:convert';

import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import 'ci_environments.g.dart';
import 'evaluate_variable_expression.dart';
import 'read_file.dart' if (dart.library.io) 'read_file_io.dart';
import 'remove_user_info_from_url.dart';

/// Reads the text file at a path, or returns `null` when it cannot be read.
typedef ReadTextFile = String? Function(String path);

/// The CI environment templates, in detection order.
final List<messages.Ci> _templates = [
  for (final template in jsonDecode(ciEnvironmentsJson) as List<Object?>)
    messages.Ci.fromJson(template! as Map<String, Object?>),
];

/// Detects the CI server from the environment variables in [env].
///
/// Returns `null` when no supported CI server is detected. Otherwise returns
/// its name, the URL of the build and, when the variables are set, the build
/// number and the Git remote, revision, branch and tag. Credentials are
/// removed from the Git remote.
///
/// For GitHub Actions pull requests, the revision is the head commit of the
/// pull request, read from the event payload at `GITHUB_EVENT_PATH` with
/// [readFile]. It defaults to reading the file system, where there is one.
messages.Ci? detectCiEnvironment(
  Map<String, String> env, {
  ReadTextFile? readFile,
}) {
  for (final template in _templates) {
    final detected = _detect(template, env, readFile ?? readTextFile);
    if (detected != null) {
      return detected;
    }
  }
  return null;
}

messages.Ci? _detect(
  messages.Ci template,
  Map<String, String> env,
  ReadTextFile readFile,
) {
  // The URL is what consumers use as the primary key of a build, so nothing
  // is detected without it.
  final url = evaluateVariableExpression(template.url, env);
  if (url == null) {
    return null;
  }
  return messages.Ci(
    name: template.name,
    url: url,
    buildNumber: evaluateVariableExpression(template.buildNumber, env),
    git: _detectGit(template.git, env, readFile),
  );
}

messages.Git? _detectGit(
  messages.Git? template,
  Map<String, String> env,
  ReadTextFile readFile,
) {
  if (template == null) {
    return null;
  }
  final revision = _detectRevision(template, env, readFile);
  if (revision == null || revision.isEmpty) {
    return null;
  }
  final remote = evaluateVariableExpression(template.remote, env);
  if (remote == null || remote.isEmpty) {
    return null;
  }
  return messages.Git(
    remote: removeUserInfoFromUrl(remote),
    revision: revision,
    branch: _nonEmpty(evaluateVariableExpression(template.branch, env)),
    tag: _nonEmpty(evaluateVariableExpression(template.tag, env)),
  );
}

String? _detectRevision(
  messages.Git template,
  Map<String, String> env,
  ReadTextFile readFile,
) =>
    _gitHubPullRequestRevision(env, readFile) ??
    evaluateVariableExpression(template.revision, env);

/// The head commit of a GitHub Actions pull request.
///
/// `GITHUB_SHA` is the merge commit for pull request events, not the commit
/// that was pushed (cucumber/ci-environment#67, #86).
String? _gitHubPullRequestRevision(
  Map<String, String> env,
  ReadTextFile readFile,
) {
  if (env['GITHUB_EVENT_NAME'] != 'pull_request') {
    return null;
  }
  final path = env['GITHUB_EVENT_PATH'];
  if (path == null) {
    return null;
  }
  final json = readFile(path);
  if (json == null) {
    return null;
  }
  try {
    return switch (jsonDecode(json)) {
      {'pull_request': {'head': {'sha': final String sha}}} => sha,
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;
