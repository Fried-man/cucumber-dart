import 'dart:convert';
import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import 'merge.dart';
import 'report_merging.dart';
import 'summary.dart';

/// The exit code of `dart run cucumber:merge` when the merged test run
/// succeeded.
const int mergeExitSuccess = 0;

/// The exit code of `dart run cucumber:merge` when the merged test run failed
/// (or never finished).
const int mergeExitFailure = 1;

/// The exit code of `dart run cucumber:merge` for a usage error: invalid
/// arguments, missing or invalid inputs, or an output that cannot be written.
const int mergeExitUsage = 2;

/// A problem with the command line or the inputs of `dart run cucumber:merge`.
final class MergeUsageException implements Exception {
  /// Creates an exception with [message].
  const MergeUsageException(this.message);

  /// What is wrong, for people.
  final String message;

  @override
  String toString() => 'MergeUsageException: $message';
}

/// The parsed command line of `dart run cucumber:merge` (design §8.4).
final class MergeArguments {
  /// Creates parsed arguments.
  MergeArguments({
    required List<String> inputs,
    required List<ReportOutput> outputs,
    required this.summary,
    this.help = false,
  }) : inputs = List.unmodifiable(inputs),
       outputs = List.unmodifiable(outputs);

  /// Part directories, part files and globs, as given.
  final List<String> inputs;

  /// The `message:` and `html:` outputs, without duplicates, with absolute
  /// paths.
  final List<ReportOutput> outputs;

  /// Whether to print the merged summary to standard output.
  final bool summary;

  /// Whether `--help` was given.
  final bool help;
}

final ArgParser _parser = ArgParser(usageLineLength: 80)
  ..addMultiOption(
    'plugin',
    abbr: 'p',
    valueHelp: 'spec',
    splitCommas: false,
    help:
        'Where to write the merged report (repeatable): message:<path> '
        '(NDJSON), html:<path> or summary (print the summary). Paths are '
        'relative to the current directory. Default: summary.',
  )
  ..addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: 'Print this usage information.',
  );

/// The usage text of `dart run cucumber:merge`.
String get mergeUsage =>
    '''
Merges Cucumber report parts into one report, for example the parts that CI
shards on several machines left in build/.cucumber/parts/.

Usage: dart run cucumber:merge [options] <input>...

Each <input> is one of:
  <directory>      every report part (*.ndjson) directly in it, such as
                   build/.cucumber/parts/<runId>/
  <file>.ndjson    one report part
  <glob>           the directories and .ndjson files it matches, such as
                   'shards/*/build/.cucumber/parts/*'

A part's suite ID is the one in its manifest (<name>.json next to it), or
else its file name. Parts are merged in the order of the inputs (the parts of
a directory by suite ID). When several parts have the same suite ID, the
first keeps it and the others get the first free <suiteId>#2, <suiteId>#3, …

Options:
${_parser.usage}

Exit codes:
  0  the merged test run succeeded
  1  the merged test run failed, or no part finished
  2  usage error: invalid arguments, missing or invalid inputs, or an output
     that cannot be written''';

/// Parses the command line of `dart run cucumber:merge`. Relative output
/// paths are resolved against [workingDirectory] (default: the current
/// directory).
///
/// Throws a [MergeUsageException] if the arguments are invalid.
MergeArguments parseMergeArguments(
  List<String> arguments, {
  String? workingDirectory,
}) {
  final ArgResults results;
  try {
    results = _parser.parse(arguments);
  } on FormatException catch (error) {
    throw MergeUsageException(error.message);
  }
  if (results.flag('help')) {
    return MergeArguments(
      inputs: const [],
      outputs: const [],
      summary: false,
      help: true,
    );
  }
  final root = workingDirectory ?? io.Directory.current.path;
  final specs = results.multiOption('plugin');
  final outputs = <ReportOutput>{};
  var summary = specs.isEmpty;
  for (final raw in specs) {
    final spec = raw.trim();
    final colon = spec.indexOf(':');
    final name = colon < 0 ? spec : spec.substring(0, colon);
    final argument = colon < 0 ? '' : spec.substring(colon + 1).trim();
    switch (name) {
      case 'message' || 'html':
        if (argument.isEmpty) {
          throw MergeUsageException(
            'Plugin "$spec" needs an output file: $name:<path>.',
          );
        }
        outputs.add(
          ReportOutput(
            name == 'message' ? ReportFormat.message : ReportFormat.html,
            p.join(root, argument),
          ),
        );
      case 'summary' when colon < 0:
        summary = true;
      case 'summary':
        throw MergeUsageException(
          'Plugin "$spec" takes no argument: the summary is printed to '
          'standard output.',
        );
      default:
        throw MergeUsageException(
          'Unknown plugin "$spec". Available: message:<path>, html:<path>, '
          'summary.',
        );
    }
  }
  final inputs = results.rest;
  if (inputs.isEmpty) {
    throw const MergeUsageException(
      'No inputs. Give the report part directories or .ndjson files to merge.',
    );
  }
  for (final input in inputs) {
    if (input.trim().isEmpty) {
      throw const MergeUsageException('Empty input.');
    }
  }
  return MergeArguments(
    inputs: inputs,
    outputs: outputs.toList(),
    summary: summary,
  );
}

/// A report part file found in the inputs of `dart run cucumber:merge`.
final class ReportPartFile {
  /// Creates the part at [path] of the suite [suiteId].
  const ReportPartFile(this.suiteId, this.path);

  /// The suite ID: the one in the part's manifest, or else its file name
  /// (percent-decoded, without `.ndjson`).
  final String suiteId;

  /// The absolute path of the `.ndjson` file.
  final String path;

  @override
  bool operator ==(Object other) =>
      other is ReportPartFile && other.suiteId == suiteId && other.path == path;

  @override
  int get hashCode => Object.hash(suiteId, path);

  @override
  String toString() => '$suiteId ($path)';
}

/// The report part files of [inputs] (design §8.4), in order: each input in
/// turn, the parts of a directory by suite ID, the matches of a glob by path.
/// A file given twice is listed once. Relative inputs are resolved against
/// [workingDirectory] (default: the current directory).
///
/// The suite IDs are as found, so they can repeat: see
/// [disambiguateSuiteIds].
///
/// Throws a [MergeUsageException] for an input that does not exist, is not a
/// directory or an `.ndjson` file, is a directory without parts, or is a glob
/// without matches.
List<ReportPartFile> findReportPartFiles(
  List<String> inputs, {
  String? workingDirectory,
}) {
  final root = workingDirectory ?? io.Directory.current.path;
  final found = <ReportPartFile>[];
  final seen = <String>{};
  void add(ReportPartFile part) {
    if (seen.add(p.canonicalize(part.path))) found.add(part);
  }

  for (final input in inputs) {
    final path = p.normalize(p.join(root, input));
    switch (io.FileSystemEntity.typeSync(path)) {
      case io.FileSystemEntityType.directory:
        final parts = _partsIn(path);
        if (parts.isEmpty) {
          throw MergeUsageException(_noPartsMessage(input, path));
        }
        parts.forEach(add);
      case io.FileSystemEntityType.notFound when _isGlob(input):
        final matches = _glob(input, root);
        if (matches.isEmpty) {
          throw MergeUsageException(
            'No report part directories or .ndjson files match "$input".',
          );
        }
        for (final match in matches) {
          if (io.FileSystemEntity.isDirectorySync(match)) {
            _partsIn(match).forEach(add);
          } else {
            add(_partFile(match));
          }
        }
      case io.FileSystemEntityType.notFound:
        final looksLikePlugin =
            input == 'summary' ||
            input.startsWith('message:') ||
            input.startsWith('html:');
        throw MergeUsageException(
          looksLikePlugin
              ? 'Input "$input" not found. To write the merged report, use '
                    '--plugin $input.'
              : 'Input "$input" not found.',
        );
      default:
        if (p.extension(path) != '.ndjson') {
          throw MergeUsageException(
            'Input "$input" is not a report part: give a directory of parts '
            'or an .ndjson file.',
          );
        }
        add(_partFile(path));
    }
  }
  return found;
}

bool _isGlob(String input) => input.contains(RegExp(r'[*?[{]'));

/// The directories and `.ndjson` files that [pattern] matches, sorted.
List<String> _glob(String pattern, String root) {
  // Globs use `/`; `\` escapes. Windows users write paths with `\`.
  final normalized = p.style == p.Style.windows
      ? pattern.replaceAll(r'\', '/')
      : pattern;
  try {
    return [
      for (final entity in Glob(normalized).listSync(root: root))
        if (entity is io.Directory ||
            (entity is io.File && p.extension(entity.path) == '.ndjson'))
          p.normalize(p.absolute(entity.path)),
    ]..sort();
  } on io.FileSystemException {
    return const [];
  } on FormatException catch (error) {
    throw MergeUsageException('Invalid glob "$pattern": ${error.message}');
  }
}

String _noPartsMessage(String input, String path) {
  final directories = [
    for (final entity in io.Directory(path).listSync())
      if (entity is io.Directory) p.basename(entity.path),
  ]..sort();
  final buffer = StringBuffer(
    'No report parts (*.ndjson) in directory "$input".',
  );
  if (directories.isNotEmpty) {
    const shown = 5;
    buffer.write(
      ' Parts are directly in the directory of their run, such as '
      'build/.cucumber/parts/<runId>/, and "$input" contains the '
      'directories ${directories.take(shown).join(', ')}'
      '${directories.length > shown ? ', …' : ''}.',
    );
  }
  return buffer.toString();
}

/// The parts directly in [directory], by suite ID (then path).
List<ReportPartFile> _partsIn(String directory) {
  final parts = [
    for (final entity in io.Directory(directory).listSync())
      if (entity is io.File && p.extension(entity.path) == '.ndjson')
        _partFile(p.normalize(p.absolute(entity.path))),
  ];
  return parts..sort((a, b) {
    final bySuite = a.suiteId.compareTo(b.suiteId);
    return bySuite != 0 ? bySuite : a.path.compareTo(b.path);
  });
}

/// The part at [path], with the suite ID of its manifest if it has one.
ReportPartFile _partFile(String path) {
  final manifest = io.File('${p.withoutExtension(path)}.json');
  try {
    if (jsonDecode(manifest.readAsStringSync()) case {
      'suiteId': final String suiteId,
    } when suiteId.isNotEmpty) {
      return ReportPartFile(suiteId, path);
    }
  } on io.FileSystemException {
    // No manifest.
  } on FormatException {
    // Not a manifest.
  }
  final name = p.basenameWithoutExtension(path);
  String suiteId;
  try {
    suiteId = Uri.decodeComponent(name);
  } on ArgumentError {
    suiteId = name;
  }
  return ReportPartFile(suiteId, path);
}

/// Makes [suiteIds] unique, deterministically: the first occurrence of an ID
/// keeps it, and each later one gets the first `<suiteId>#2`, `<suiteId>#3`,
/// … that no other part uses, as suites of one run do (design §8.4).
List<String> disambiguateSuiteIds(List<String> suiteIds) {
  final taken = suiteIds.toSet();
  final kept = <String>{};
  return [
    for (final suiteId in suiteIds)
      if (kept.add(suiteId)) suiteId else _nextFree(suiteId, taken),
  ];
}

String _nextFree(String suiteId, Set<String> taken) {
  for (var n = 2; ; n++) {
    final candidate = '$suiteId#$n';
    if (taken.add(candidate)) return candidate;
  }
}

/// Reads [files] as report parts, with unique suite IDs
/// ([disambiguateSuiteIds]). Parts without any complete message are left out
/// (and [warn] is told), and so is an incomplete last line. [note] is told
/// about renamed suite IDs: shards of one test run (such as
/// `dart test --shard-index`) usually have the same suites.
///
/// Throws a [MergeUsageException] if a part cannot be read or is not NDJSON
/// Cucumber Messages.
List<ReportPart> readReportPartFiles(
  List<ReportPartFile> files, {
  void Function(String warning)? warn,
  void Function(String note)? note,
}) {
  final read = <(ReportPartFile, List<messages.Envelope>)>[];
  for (final file in files) {
    final List<messages.Envelope> envelopes;
    try {
      envelopes = readReportPart(file.path);
    } on FormatException catch (error) {
      throw MergeUsageException(
        'Report part "${file.path}" is not NDJSON Cucumber Messages: '
        '${error.message}',
      );
    } on io.FileSystemException catch (error) {
      throw MergeUsageException(
        'Cannot read report part "${file.path}": ${error.message}'
        '${error.osError == null ? '' : ' (${error.osError!.message})'}',
      );
    }
    if (envelopes.isEmpty) {
      warn?.call('Skipped report part "${file.path}": it has no messages.');
      continue;
    }
    read.add((file, envelopes));
  }
  final suiteIds = disambiguateSuiteIds([
    for (final (file, _) in read) file.suiteId,
  ]);
  final parts = <ReportPart>[];
  for (final (index, (file, envelopes)) in read.indexed) {
    final suiteId = suiteIds[index];
    if (suiteId != file.suiteId) {
      note?.call(
        'Suite ID "${file.suiteId}" is used by several report parts: '
        '"${file.path}" is merged as "$suiteId".',
      );
    }
    parts.add(ReportPart(suiteId, envelopes));
  }
  return parts;
}

/// Whether the merged [envelopes] have a successful `testRunFinished`.
bool mergedRunSucceeded(Iterable<messages.Envelope> envelopes) =>
    envelopes.map((e) => e.testRunFinished).nonNulls.lastOrNull?.success ??
    false;

/// Runs `dart run cucumber:merge` with [arguments] and returns its exit code
/// ([mergeExitSuccess], [mergeExitFailure] or [mergeExitUsage]).
///
/// The help and the summary are written to [out] (default: standard output);
/// errors and warnings to [err] (default: standard error). Relative paths are
/// resolved against [workingDirectory] (default: the current directory).
Future<int> runMergeCommand(
  List<String> arguments, {
  StringSink? out,
  StringSink? err,
  String? workingDirectory,
}) async {
  final output = out ?? io.stdout;
  final errors = err ?? io.stderr;
  try {
    final parsed = parseMergeArguments(
      arguments,
      workingDirectory: workingDirectory,
    );
    if (parsed.help) {
      output.writeln(mergeUsage);
      return mergeExitSuccess;
    }
    void warn(String warning) => errors.writeln('Warning: $warning');
    final parts = readReportPartFiles(
      findReportPartFiles(parsed.inputs, workingDirectory: workingDirectory),
      warn: warn,
      note: (note) => errors.writeln('Note: $note'),
    );
    if (parts.isEmpty) {
      throw const MergeUsageException('No messages in the report parts.');
    }
    final merged = mergeReportParts(parts);
    for (final report in parsed.outputs) {
      try {
        await writeReport(report, merged);
      } on io.FileSystemException catch (error) {
        throw MergeUsageException(
          'Cannot write "${report.path}": ${error.message}'
          '${error.osError == null ? '' : ' (${error.osError!.message})'}',
        );
      }
    }
    if (parsed.summary) output.writeln(formatSummaryOf(merged));
    if (!merged.any((e) => e.testRunFinished != null)) {
      warn('No report part finished, so the merged test run did not finish.');
    }
    return mergedRunSucceeded(merged) ? mergeExitSuccess : mergeExitFailure;
  } on MergeUsageException catch (error) {
    errors
      ..writeln('Error: ${error.message}')
      ..writeln('Run "dart run cucumber:merge --help" for usage.');
    return mergeExitUsage;
  }
}
