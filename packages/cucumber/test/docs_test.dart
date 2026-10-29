// Keeps the user documentation (docs/guide/ and docs/performance.md) true.
//
// Every fenced code block there is preceded by a marker comment that says how
// it is checked:
//
//   <!-- excerpt: <path>[#<region>] -->
//       The block is the file at <path> (relative to the repository root), or
//       its lines between `#docregion <region>` and `#enddocregion <region>`
//       comments. Region comments are left out, and so is the region's common
//       indentation.
//   <!-- run in: <directory> -->
//       Each line is a `dart` or `flutter` command, optionally preceded by
//       NAME=value environment variables, that is run in <directory>. It must
//       succeed, unless its comment says that it "fails". `dart test` and
//       `flutter test` run with the expanded reporter, whose output does not
//       depend on the terminal or CI. Documents with `flutter` commands are
//       only run when the Flutter SDK is on the PATH (the flutter CI job).
//   <!-- output -->
//       Each line appears, in order, in an output line of the last command
//       run before the block.
//   <!-- files in: <directory> -->
//       The first word of each line is a file in <directory>, after the
//       commands before the block ran.
//   <!-- checked: <name> -->
//       A test below checks the block.
//   <!-- not run: <reason> -->
//       Not checked.
//
// The tests also check that the configuration and merge command references
// list every option there is, and that the links of the documentation and the
// READMEs point at files and headings that exist.
//
// `UPDATE_DOC_EXCERPTS=true dart test test/docs_test.dart` rewrites the
// excerpts from their sources.
import 'dart:convert';
import 'dart:io';

import 'package:cucumber/src/configuration.dart' show profileOptionNames;
import 'package:cucumber/src/merge_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/dart_test_runner.dart' show cucumberPackageDirectory;

/// The root of the repository.
final String repositoryRoot = p.normalize(
  p.join(cucumberPackageDirectory, '..', '..'),
);

String _repo(String path) => p.normalize(p.join(repositoryRoot, path));

/// The documents whose code blocks are checked.
List<String> get _documents => [
  for (final entity in Directory(_repo('docs/guide')).listSync())
    if (entity is File && entity.path.endsWith('.md'))
      p.relative(entity.path, from: repositoryRoot).replaceAll(r'\', '/'),
  'docs/performance.md',
]..sort();

void main() {
  for (final document in _documents) {
    group(document, () {
      late final List<CodeBlock> blocks = CodeBlock.parse(document);

      test('every code block says how it is checked', () {
        for (final block in blocks) {
          expect(
            block.marker,
            isNotNull,
            reason:
                '${block.where}: a code block needs a marker comment on the '
                'line before it (see test/docs_test.dart).',
          );
        }
      });

      test('excerpts match their sources', () {
        if (Platform.environment['UPDATE_DOC_EXCERPTS'] == 'true') {
          _updateExcerpts(document, blocks);
        }
        for (final block in CodeBlock.parse(document)) {
          if (block.marker != 'excerpt') continue;
          final (path, region) = _excerptTarget(block.argument);
          expect(
            block.text,
            excerpt(path, region),
            reason:
                '${block.where} is not the same as $path'
                '${region == null ? '' : '#$region'}. '
                'UPDATE_DOC_EXCERPTS=true updates it.',
          );
        }
      });

      final commands = [
        for (final block in CodeBlock.parse(document))
          if (block.marker == 'run in')
            for (final line in block.lines)
              if (line.trim().isNotEmpty) _Command.parse(line),
      ];
      if (commands.isNotEmpty) {
        test(
          'commands run as shown',
          () => _runCommands(document, blocks),
          timeout: const Timeout(Duration(minutes: 10)),
          skip: commands.any((c) => c.executable == 'flutter') && !_hasFlutter
              ? 'Needs the Flutter SDK on the PATH (the flutter CI job runs it).'
              : null,
        );
      }
    });
  }

  group('checked blocks', () {
    final checks = <String, void Function(CodeBlock block)>{
      'install': _checkInstall,
      'flutter-install': _checkFlutterInstall,
      'workflow': _checkWorkflow,
    };
    final checked = [
      for (final document in _documents)
        for (final block in CodeBlock.parse(document))
          if (block.marker == 'checked') block,
    ];

    test('have a check, and every check is used', () {
      expect({
        for (final block in checked) block.argument,
      }, checks.keys.toSet());
    });

    for (final block in checked) {
      if (checks[block.argument] case final check?) {
        test('${block.argument} (${block.where})', () => check(block));
      }
    }
  });

  group('configuration.md', () {
    late final List<List<String>> options = _table(
      'docs/guide/configuration.md',
      '| Code | `cucumber.yaml` | Environment variable |',
    );

    test('lists every option of CucumberOptions', () {
      expect(_names(options, 0), _cucumberOptionsParameters());
    });

    test('lists every cucumber.yaml option', () {
      expect(_names(options, 1), profileOptionNames);
    });

    test('lists every CUCUMBER_* variable', () {
      expect(_names(options, 2), _environmentVariables());
    });
  });

  group('reports.md', () {
    test('lists every option of dart run cucumber:merge', () {
      final arguments = _table('docs/guide/reports.md', '| Argument |');
      final documented = {
        for (final row in arguments)
          for (final match in RegExp(r'`(--?[a-z][\w-]*)').allMatches(row[0]))
            match[1]!,
      };
      final options = {
        for (final match in RegExp(
          r'^\s*(-\w), (--[\w-]+)',
          multiLine: true,
        ).allMatches(mergeUsage)) ...[match[1]!, match[2]!],
      };
      expect(options, isNotEmpty);
      expect(documented, options);
    });

    test('lists every exit code of dart run cucumber:merge', () {
      final codes = _table('docs/guide/reports.md', '| Exit code |');
      expect(
        {for (final row in codes) int.parse(row[0])},
        {mergeExitSuccess, mergeExitFailure, mergeExitUsage},
      );
    });
  });

  test('links point at files and headings that exist', () {
    final documents = [
      for (final directory in ['docs', 'docs/guide'])
        for (final entity in Directory(_repo(directory)).listSync())
          if (entity is File && entity.path.endsWith('.md'))
            p.relative(entity.path, from: repositoryRoot),
      'README.md',
      for (final entity in Directory(_repo('packages')).listSync())
        if (entity is Directory &&
            File(p.join(entity.path, 'README.md')).existsSync())
          p.relative(p.join(entity.path, 'README.md'), from: repositoryRoot),
      'packages/cucumber/example/README.md',
      'packages/cucumber_flutter/example/README.md',
    ];
    final broken = <String>[];
    var checked = 0;
    for (final document in documents) {
      for (final link in _links(document)) {
        final problem = _checkLink(document, link);
        if (problem != null) broken.add('$document: $link: $problem');
        checked++;
      }
    }
    expect(broken, isEmpty);
    // The guide alone has dozens of links; this catches a parser that finds
    // none.
    expect(checked, greaterThan(150));
  });
}

// ---------------------------------------------------------------------------
// Code blocks
// ---------------------------------------------------------------------------

final RegExp _fence = RegExp(r'^(\s*)```(\S*)\s*$');
final RegExp _marker = RegExp(
  r'^\s*<!-- (excerpt|run in|files in|checked|not run): (.+?) -->\s*$|'
  r'^\s*<!-- (output) -->\s*$',
);

/// A fenced code block of a Markdown document.
final class CodeBlock {
  CodeBlock._(
    this.document,
    this.line,
    this.indent,
    this.lines,
    this.marker,
    this.argument,
  );

  /// The code blocks of [document] (relative to the repository root).
  static List<CodeBlock> parse(String document) {
    final lines = File(_repo(document)).readAsLinesSync();
    final blocks = <CodeBlock>[];
    for (var i = 0; i < lines.length; i++) {
      final open = _fence.firstMatch(lines[i]);
      if (open == null) continue;
      final indent = open[1]!.length;
      var end = i + 1;
      while (end < lines.length && lines[end].trim() != '```') {
        end++;
      }
      var previous = i - 1;
      while (previous >= 0 && lines[previous].trim().isEmpty) {
        previous--;
      }
      final marker = previous < 0 ? null : _marker.firstMatch(lines[previous]);
      blocks.add(
        CodeBlock._(
          document,
          i + 1,
          indent,
          [
            for (final line in lines.sublist(i + 1, end))
              line.length >= indent ? line.substring(indent) : line.trimLeft(),
          ],
          marker == null ? null : marker[1] ?? marker[3],
          marker?[2],
        ),
      );
      i = end;
    }
    return blocks;
  }

  /// The document.
  final String document;

  /// The line of the opening fence (1-based).
  final int line;

  /// The indentation of the fences.
  final int indent;

  /// The lines between the fences, without the fences' indentation.
  final List<String> lines;

  /// The kind of marker comment before the block, if any.
  final String? marker;

  /// The marker's argument.
  final String? argument;

  /// The block's text.
  String get text => lines.join('\n');

  /// `document:line`, for messages.
  String get where => '$document:$line';
}

(String, String?) _excerptTarget(String? argument) {
  final hash = argument!.indexOf('#');
  return hash < 0
      ? (argument, null)
      : (argument.substring(0, hash), argument.substring(hash + 1));
}

final RegExp _region = RegExp(r'^\s*(?://|#)\s*#(end)?docregion\s+(\S+)\s*$');

/// The excerpt of the file at [path] (relative to the repository root): the
/// whole file, or the lines of [region], without region comments and without
/// their common indentation.
String excerpt(String path, String? region) {
  final lines = File(_repo(path)).readAsLinesSync();
  var selected = lines;
  if (region != null) {
    final start = lines.indexWhere((line) {
      final match = _region.firstMatch(line);
      return match != null && match[1] == null && match[2] == region;
    });
    final end = lines.indexWhere((line) {
      final match = _region.firstMatch(line);
      return match != null && match[1] != null && match[2] == region;
    }, start + 1);
    if (start < 0 || end < 0) {
      throw StateError('$path has no region "$region".');
    }
    selected = lines.sublist(start + 1, end);
  }
  selected = [
    for (final line in selected)
      if (!_region.hasMatch(line)) line,
  ];
  while (selected.isNotEmpty && selected.last.trim().isEmpty) {
    selected.removeLast();
  }
  final indents = [
    for (final line in selected)
      if (line.trim().isNotEmpty) line.length - line.trimLeft().length,
  ];
  final indent = indents.isEmpty ? 0 : indents.reduce((a, b) => a < b ? a : b);
  return [
    for (final line in selected)
      line.trim().isEmpty ? '' : line.substring(indent),
  ].join('\n');
}

void _updateExcerpts(String document, List<CodeBlock> blocks) {
  final lines = File(_repo(document)).readAsLinesSync();
  for (final block in blocks.reversed) {
    if (block.marker != 'excerpt') continue;
    final (path, region) = _excerptTarget(block.argument);
    final padding = ' ' * block.indent;
    lines.replaceRange(block.line, block.line + block.lines.length, [
      for (final line in excerpt(path, region).split('\n'))
        line.isEmpty ? '' : '$padding$line',
    ]);
  }
  File(_repo(document)).writeAsStringSync('${lines.join('\n')}\n');
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

/// Whether the Flutter SDK's `flutter` command is on the PATH.
final bool _hasFlutter = () {
  final names = Platform.isWindows
      ? ['flutter.bat', 'flutter.exe']
      : ['flutter'];
  final path = Platform.environment['PATH'] ?? '';
  return path
      .split(Platform.isWindows ? ';' : ':')
      .where((directory) => directory.isNotEmpty)
      .any((d) => names.any((n) => File(p.join(d, n)).existsSync()));
}();

/// A command line of a `run in:` block.
final class _Command {
  _Command(
    this.text,
    this.environment,
    this.executable,
    this.arguments, {
    required this.fails,
  });

  /// Parses [line]: `[NAME=value ...] (dart|flutter) <arguments> [# comment]`.
  factory _Command.parse(String line) {
    final words = <String>[];
    final word = StringBuffer();
    var hasWord = false;
    String? quote;
    var comment = '';
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (quote != null) {
        if (char == quote) {
          quote = null;
        } else {
          word.write(char);
        }
      } else if (char == '"' || char == "'") {
        quote = char;
        hasWord = true;
      } else if (char == '#' && !hasWord) {
        comment = line.substring(i + 1);
        break;
      } else if (char.trim().isEmpty) {
        if (hasWord) words.add(word.toString());
        word.clear();
        hasWord = false;
      } else {
        word.write(char);
        hasWord = true;
      }
    }
    if (hasWord) words.add(word.toString());
    final environment = <String, String>{};
    while (words.isNotEmpty &&
        RegExp(r'^[A-Z_][A-Z0-9_]*=').hasMatch(words.first)) {
      final assignment = words.removeAt(0);
      final equals = assignment.indexOf('=');
      environment[assignment.substring(0, equals)] = assignment.substring(
        equals + 1,
      );
    }
    if (words.isEmpty || (words.first != 'dart' && words.first != 'flutter')) {
      throw FormatException('Not a dart or flutter command: $line');
    }
    return _Command(
      line.trim(),
      environment,
      words.first,
      words.sublist(1),
      fails: comment.contains('fails'),
    );
  }

  final String text;
  final Map<String, String> environment;

  /// `dart` or `flutter`.
  final String executable;
  final List<String> arguments;
  final bool fails;

  /// The arguments to run: `dart test` and `flutter test` get the expanded
  /// reporter.
  List<String> get processArguments =>
      arguments.isNotEmpty &&
          arguments.first == 'test' &&
          !arguments.any((a) => a.startsWith('--reporter') || a == '-r')
      ? ['test', '--reporter', 'expanded', ...arguments.skip(1)]
      : arguments;
}

Future<void> _runCommands(String document, List<CodeBlock> blocks) async {
  final cleaned = <String>{};
  String? output;
  String? lastCommand;
  for (final block in blocks) {
    switch (block.marker) {
      case 'run in':
        final directory = _repo(block.argument!);
        if (cleaned.add(directory)) {
          final build = Directory(p.join(directory, 'build'));
          if (build.existsSync()) build.deleteSync(recursive: true);
        }
        for (final line in block.lines) {
          if (line.trim().isEmpty) continue;
          final command = _Command.parse(line);
          final flutter = command.executable == 'flutter';
          final result = await Process.run(
            flutter ? 'flutter' : Platform.resolvedExecutable,
            command.processArguments,
            workingDirectory: directory,
            runInShell: flutter && Platform.isWindows,
            environment: {
              for (final key in Platform.environment.keys)
                if (key.toUpperCase().startsWith('CUCUMBER_')) key: '',
              ...command.environment,
            },
            stdoutEncoding: utf8,
            stderrEncoding: utf8,
          );
          output = '${result.stdout}\n${result.stderr}';
          lastCommand = command.text;
          final succeeded = result.exitCode == 0;
          expect(
            succeeded,
            !command.fails,
            reason:
                '${block.where}: `${command.text}` exited with '
                '${result.exitCode}${command.fails ? ', but should fail' : ''}.'
                '\n$output',
          );
        }
      case 'output':
        expect(output, isNotNull, reason: '${block.where}: no command ran.');
        final outputLines = [
          for (final line in const LineSplitter().convert(output!)) line.trim(),
        ];
        var from = 0;
        for (final expected in block.lines) {
          final text = expected.trim();
          if (text.isEmpty) continue;
          final index = outputLines.indexWhere((l) => l.contains(text), from);
          expect(
            index,
            isNonNegative,
            reason:
                '${block.where}: "$text" is not in the output of '
                '`$lastCommand` (after the lines before it):\n$output',
          );
          from = index + 1;
        }
      case 'files in':
        for (final line in block.lines) {
          final words = line.trim().split(RegExp(r'\s+'));
          if (words.first.isEmpty) continue;
          final path = p.join(_repo(block.argument!), words.first);
          expect(
            FileSystemEntity.typeSync(path),
            isNot(FileSystemEntityType.notFound),
            reason: '${block.where}: $path does not exist.',
          );
        }
    }
  }
}

// ---------------------------------------------------------------------------
// Checked blocks
// ---------------------------------------------------------------------------

/// The pubspec of [package] (a directory below `packages/`).
YamlMap _pubspec(String package) =>
    loadYaml(File(_repo('packages/$package/pubspec.yaml')).readAsStringSync())
        as YamlMap;

/// The install snippet depends on `cucumber`, and overrides exactly the
/// workspace packages that `cucumber` depends on, from this repository.
void _checkInstall(CodeBlock block) {
  final snippet = loadYaml(block.text) as YamlMap;
  final cucumber = _pubspec('cucumber');
  final repository = '${cucumber['repository']}';
  final url = repository.substring(0, repository.indexOf('/tree/'));
  final workspacePackages = {
    for (final entity in Directory(_repo('packages')).listSync())
      if (File(p.join(entity.path, 'pubspec.yaml')).existsSync())
        '${_pubspec(p.basename(entity.path))['name']}',
  };

  void expectGit(String name, Object? dependency) {
    expect(dependency, isA<YamlMap>(), reason: name);
    final git = (dependency! as YamlMap)['git'] as YamlMap;
    expect(git['url'], url, reason: name);
    expect(git['path'], 'packages/$name', reason: name);
    expect(_pubspec(name)['name'], name);
  }

  final devDependencies = snippet['dev_dependencies'] as YamlMap;
  expectGit('cucumber', devDependencies['cucumber']);
  expect(
    devDependencies['test'],
    (cucumber['dependencies'] as YamlMap)['test'],
  );
  final overrides = snippet['dependency_overrides'] as YamlMap;
  expect(overrides.keys.toSet(), {
    for (final name in (cucumber['dependencies'] as YamlMap).keys)
      if (workspacePackages.contains(name)) name,
  });
  for (final MapEntry(:key, :value) in overrides.entries) {
    expectGit('$key', value);
  }
}

/// The Flutter install snippet depends on `cucumber_flutter` from this
/// repository and on `flutter_test`, and overrides `cucumber` and the
/// workspace packages that `cucumber` depends on, from this repository: the
/// overrides of `cucumber_flutter`'s own pubspec plus `cucumber`, which it
/// depends on by path.
void _checkFlutterInstall(CodeBlock block) {
  final snippet = loadYaml(block.text) as YamlMap;
  final flutter = _pubspec('cucumber_flutter');
  final repository = '${flutter['repository']}';
  final url = repository.substring(0, repository.indexOf('/tree/'));

  void expectGit(String name, Object? dependency) {
    expect(dependency, isA<YamlMap>(), reason: name);
    final git = (dependency! as YamlMap)['git'] as YamlMap;
    expect(git['url'], url, reason: name);
    expect(git['path'], 'packages/$name', reason: name);
    expect(_pubspec(name)['name'], name);
  }

  final devDependencies = snippet['dev_dependencies'] as YamlMap;
  expectGit('cucumber_flutter', devDependencies['cucumber_flutter']);
  expect(devDependencies['flutter_test'], {'sdk': 'flutter'});
  final overrides = snippet['dependency_overrides'] as YamlMap;
  final dependencies = flutter['dependencies'] as YamlMap;
  expect(overrides.keys.toSet(), {
    for (final MapEntry(:key, :value) in dependencies.entries)
      if (value is YamlMap && value.containsKey('path')) key,
    ...(flutter['dependency_overrides'] as YamlMap).keys,
  });
  for (final MapEntry(:key, :value) in overrides.entries) {
    expectGit('$key', value);
  }
}

/// The workflow is YAML, uses only the `CUCUMBER_*` variables that exist,
/// uploads the directory that holds the report parts, and runs a valid merge
/// command.
void _checkWorkflow(CodeBlock block) {
  final workflow = loadYaml(block.text) as YamlMap;
  final known = _environmentVariables();
  final used = RegExp(r'CUCUMBER_[A-Z_]+').allMatches(block.text);
  expect(used, isNotEmpty);
  for (final match in used) {
    expect(known, contains(match[0]));
  }
  final steps = [
    for (final job in (workflow['jobs'] as YamlMap).values)
      for (final step in (job as YamlMap)['steps'] as YamlList) step as YamlMap,
  ];
  final uploads = [
    for (final step in steps)
      if ('${step['uses']}'.startsWith('actions/upload-artifact'))
        '${(step['with'] as YamlMap)['path']}',
  ];
  expect(uploads, contains('build/.cucumber/parts/'));
  final merges = [
    for (final step in steps)
      if ('${step['run']}'.startsWith('dart run cucumber:merge '))
        '${step['run']}',
  ];
  expect(merges, hasLength(1));
  final arguments = [
    for (final match in RegExp(
      r"'([^']*)'|(\S+)",
    ).allMatches(merges.single.substring('dart run cucumber:merge '.length)))
      match[1] ?? match[2]!,
  ];
  final parsed = parseMergeArguments(arguments);
  expect(parsed.inputs, ['parts/*/*']);
  expect(parsed.outputs, hasLength(2));
}

// ---------------------------------------------------------------------------
// References
// ---------------------------------------------------------------------------

/// The rows (cells, trimmed) of the table of [document] whose header starts
/// with [header].
List<List<String>> _table(String document, String header) {
  final lines = File(_repo(document)).readAsLinesSync();
  final start = lines.indexWhere((line) => line.startsWith(header));
  expect(start, isNonNegative, reason: 'No table "$header" in $document');
  return [
    for (final line
        in lines.skip(start + 2).takeWhile((l) => l.startsWith('|')))
      [
        for (final cell in line.substring(1, line.length - 1).split('|'))
          cell.trim(),
      ],
  ];
}

/// The names in backticks in [column] of [rows].
Set<String> _names(List<List<String>> rows, int column) => {
  for (final row in rows)
    for (final match in RegExp(r'`([\w]+)`').allMatches(row[column])) match[1]!,
};

/// The parameters of the `CucumberOptions` constructor.
Set<String> _cucumberOptionsParameters() {
  final source = File(
    p.join(cucumberPackageDirectory, 'lib', 'src', 'options.dart'),
  ).readAsStringSync();
  final start = source.indexOf('  CucumberOptions({');
  final end = source.indexOf('})', start);
  expect(start, isNonNegative);
  return {
    for (final match in RegExp(
      r'(\w+),\s*$',
      multiLine: true,
    ).allMatches(source.substring(start, end)))
      match[1]!,
  };
}

/// The `CUCUMBER_*` environment variables that `package:cucumber` reads.
Set<String> _environmentVariables() => {
  for (final entity in Directory(
    p.join(cucumberPackageDirectory, 'lib'),
  ).listSync(recursive: true))
    if (entity is File && entity.path.endsWith('.dart'))
      for (final match in RegExp(
        r"'(CUCUMBER_[A-Z_]+)'",
      ).allMatches(entity.readAsStringSync()))
        match[1]!,
};

// ---------------------------------------------------------------------------
// Links
// ---------------------------------------------------------------------------

const String _githubPrefix = 'https://github.com/Fried-man/cucumber-dart/';

/// The link targets of [document], outside code.
List<String> _links(String document) {
  final text = _withoutCode(File(_repo(document)).readAsStringSync());
  return [
    for (final match in RegExp(r'\]\(([^)\s]+)\)').allMatches(text)) match[1]!,
    for (final match in RegExp(
      r'^\s*\[[^\]]+\]:\s*(\S+)',
      multiLine: true,
    ).allMatches(text))
      match[1]!,
  ];
}

/// The lines of [markdown] outside fenced code blocks.
List<String> _withoutFences(String markdown) {
  final lines = <String>[];
  var inFence = false;
  for (final line in const LineSplitter().convert(markdown)) {
    if (_fence.hasMatch(line) || (inFence && line.trim() == '```')) {
      inFence = !inFence;
      continue;
    }
    if (!inFence) lines.add(line);
  }
  return lines;
}

/// [markdown] without fenced code blocks and code spans.
String _withoutCode(String markdown) => [
  for (final line in _withoutFences(markdown))
    line.replaceAll(RegExp('`[^`]*`'), '``'),
].join('\n');

/// What is wrong with [link] in [document], or `null`.
String? _checkLink(String document, String link) {
  String target;
  if (link.startsWith(_githubPrefix)) {
    final match = RegExp(
      r'^(?:blob|tree)/main/([^#?]*)(#.*)?$',
    ).firstMatch(link.substring(_githubPrefix.length));
    if (match == null) return 'not a link to a file on main';
    target = '${match[1]}${match[2] ?? ''}';
  } else if (link.contains('://') || link.startsWith('mailto:')) {
    return null;
  } else if (link.startsWith('#')) {
    target = '${p.basename(document)}$link';
    target = p.join(p.dirname(document), target);
  } else {
    target = p.join(p.dirname(document), link);
  }
  final hash = target.indexOf('#');
  final path = p.normalize(
    Uri.decodeComponent(hash < 0 ? target : target.substring(0, hash)),
  );
  final anchor = hash < 0 ? null : target.substring(hash + 1);
  final file = _repo(path);
  if (FileSystemEntity.typeSync(file) == FileSystemEntityType.notFound) {
    return '$path does not exist';
  }
  if (anchor != null && anchor.isNotEmpty && file.endsWith('.md')) {
    final anchors = _anchors(file);
    if (!anchors.contains(anchor)) return '$path has no heading #$anchor';
  }
  return null;
}

/// The anchors of the headings of the Markdown file at [path], as GitHub
/// makes them.
Set<String> _anchors(String path) {
  final anchors = <String>{};
  final counts = <String, int>{};
  for (final line in _withoutFences(File(path).readAsStringSync())) {
    final match = RegExp(r'^#{1,6}\s+(.*?)\s*#*\s*$').firstMatch(line);
    if (match == null) continue;
    final slug = _slug(match[1]!);
    final count = counts[slug] = (counts[slug] ?? -1) + 1;
    anchors.add(count == 0 ? slug : '$slug-$count');
  }
  return anchors;
}

String _slug(String heading) => heading
    .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
    .replaceAll('`', '')
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N} _-]', unicode: true), '')
    .replaceAll(' ', '-');
