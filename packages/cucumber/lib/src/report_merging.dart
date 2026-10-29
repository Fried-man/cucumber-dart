import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cucumber_core/engine.dart' show Plugin;
import 'package:cucumber_html_formatter/cucumber_html_formatter.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:path/path.dart' as p;
import 'package:stack_trace/stack_trace.dart';

import 'buffered_sink.dart';
import 'merge.dart';
import 'merge_lock.dart';

/// The directory, relative to the package root, below which report parts and
/// the merge lock live: `build/.cucumber/` (design §8.4).
const String outputDirectoryName = 'build';

/// The run ID that correlates the report parts of one run (design §8.4):
///
/// 1. `CUCUMBER_RUN_ID` from [environment], if it is set;
/// 2. under `flutter test` (`FLUTTER_TEST` is set), `flutter-` and a hash of
///    `FONTCONFIG_FILE`: `flutter test` runs each test file in its own
///    process, but gives all of them the same font configuration file, which
///    it creates in a new temporary directory for each run;
/// 3. otherwise the ID of this process ([processId], default: [pid]), which
///    every isolate started by one `dart test` invocation shares.
String resolveRunId(Map<String, String> environment, {int? processId}) {
  final configured = environment['CUCUMBER_RUN_ID']?.trim() ?? '';
  if (configured.isNotEmpty) return configured;
  final fontConfig = environment['FONTCONFIG_FILE']?.trim() ?? '';
  if (environment.containsKey('FLUTTER_TEST') && fontConfig.isNotEmpty) {
    return 'flutter-${_fnv1a32(fontConfig).toRadixString(16).padLeft(8, '0')}';
  }
  return '${processId ?? pid}';
}

/// The 32-bit FNV-1a hash of the UTF-8 bytes of [text].
int _fnv1a32(String text) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(text)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// The suite ID of the test file that declares a suite: the path of the file
/// whose `main` is on the stack ([trace], default: the current stack trace),
/// relative to `<packageRoot>/test` (or else to [packageRoot]), without
/// `.dart` and with `/` separators. For example, `test/cucumber_test.dart`
/// gives `cucumber_test` and `test/checkout/cart_test.dart` gives
/// `checkout/cart_test`.
///
/// Returns `suite` when no test file is found.
String testFileSuiteId(String packageRoot, {Trace? trace}) {
  final frames = (trace ?? Trace.current()).frames;
  Uri? file;
  // The outermost `main` is the test file's: package:test calls it.
  for (final frame in frames.reversed) {
    if (frame.uri.isScheme('file') && frame.member == 'main') {
      file = frame.uri;
      break;
    }
  }
  file ??= frames.map((f) => f.uri).where((u) => u.isScheme('file')).lastOrNull;
  if (file == null) return 'suite';
  final path = p.fromUri(file);
  final test = p.join(packageRoot, 'test');
  final relative = p.isWithin(test, path)
      ? p.relative(path, from: test)
      : p.isWithin(packageRoot, path)
      ? p.relative(path, from: packageRoot)
      : p.basename(path);
  return p.split(p.withoutExtension(relative)).join('/');
}

/// [id] as a file name: characters other than ASCII letters, digits, `-`,
/// `_` and (except at the start) `.` are percent-encoded, so every ID gets a
/// different, portable file name.
String fileNameOf(String id) {
  final buffer = StringBuffer();
  final bytes = utf8.encode(id);
  for (var i = 0; i < bytes.length; i++) {
    final byte = bytes[i];
    final plain =
        (byte >= 0x30 && byte <= 0x39) ||
        (byte >= 0x41 && byte <= 0x5a) ||
        (byte >= 0x61 && byte <= 0x7a) ||
        byte == 0x2d ||
        byte == 0x5f ||
        (byte == 0x2e && i > 0);
    if (plain) {
      buffer.writeCharCode(byte);
    } else {
      buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return buffer.isEmpty ? '%' : buffer.toString();
}

/// Where a suite writes its report part and merges the reports (design §8.4):
///
/// ```text
/// <outputDirectory>/.cucumber/merge.lock
/// <outputDirectory>/.cucumber/parts/<runId>/<suiteId>.ndjson   the part
/// <outputDirectory>/.cucumber/parts/<runId>/<suiteId>.json     its outputs
/// ```
///
/// IDs are turned into file names with [fileNameOf].
final class ReportMerging {
  /// Creates the layout for the suite [suiteId] of the run [runId].
  const ReportMerging({
    required this.outputDirectory,
    required this.runId,
    required this.suiteId,
  });

  /// The directory holding `.cucumber/`, normally `<packageRoot>/build`.
  final String outputDirectory;

  /// Correlates the parts of one run ([resolveRunId]).
  final String runId;

  /// The requested suite ID: the `suiteName` or [testFileSuiteId]. If
  /// another suite of the run already uses it, the part gets the first free
  /// ID of `<suiteId>#2`, `<suiteId>#3`, …
  final String suiteId;

  /// `<outputDirectory>/.cucumber`.
  String get cucumberDirectory => p.join(outputDirectory, '.cucumber');

  /// The lock taken while merging.
  String get lockPath => p.join(cucumberDirectory, 'merge.lock');

  /// The directory holding one directory of parts per run.
  String get runsDirectory => p.join(cucumberDirectory, 'parts');

  /// The directory of the run's parts.
  String get partsDirectory => p.join(runsDirectory, fileNameOf(runId));

  /// The NDJSON part of the suite [suiteId].
  String partPath(String suiteId) =>
      p.join(partsDirectory, '${fileNameOf(suiteId)}.ndjson');

  /// The manifest of the suite [suiteId]'s part: its suite ID and outputs.
  String manifestPath(String suiteId) =>
      p.join(partsDirectory, '${fileNameOf(suiteId)}.json');
}

/// The format of a merged report output.
enum ReportFormat {
  /// NDJSON, `message:<path>`.
  message,

  /// HTML, `html:<path>`.
  html,
}

/// A report output that is written from the merged messages of every suite
/// of the run that configures it (design §8.4).
final class ReportOutput {
  /// Creates an output of [format] at [path].
  ReportOutput(this.format, String path) : path = p.normalize(p.absolute(path));

  /// The format.
  final ReportFormat format;

  /// The absolute path of the file.
  final String path;

  /// Identifies the output in manifests: equal for equal files.
  String get key => '${format.name}:${p.canonicalize(path)}';

  @override
  bool operator ==(Object other) => other is ReportOutput && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => '${format.name}:$path';
}

/// Writes a suite's messages to its report part, and when the suite ends,
/// merges the parts of the run into the configured outputs (design §8.4).
///
/// - The part and its manifest (which lists [outputs]) are created when the
///   first message arrives, so a suite that never starts its run writes
///   nothing and merges nothing.
/// - [close] closes the part, then takes the [MergeLock], and rewrites each
///   output from [mergeReportParts] of the parts of every suite of the run
///   that configures it. So the last suite to finish leaves the complete
///   report. Still holding the lock, it then deletes the parts of earlier
///   runs ([pruneReportParts]).
final class MergedReportPlugin implements Plugin {
  /// Creates a plugin for the suite laid out by [merging], writing
  /// [outputs].
  MergedReportPlugin(this.merging, Iterable<ReportOutput> outputs)
    : outputs = List.unmodifiable(outputs.toSet());

  /// Where the part goes.
  final ReportMerging merging;

  /// The outputs, without duplicates.
  final List<ReportOutput> outputs;

  BufferedFileSink? _part;
  String? _suiteId;

  /// The suite ID of the part, once it has been created.
  String? get suiteId => _suiteId;

  @override
  void onMessage(messages.Envelope envelope) {
    final part = _part ??= _openPart();
    part
      ..write(messages.envelopeToJsonString(envelope))
      ..write('\n');
    // Other suites may merge this part while it is being written. Flushing
    // after each test case (rather than after each message, which made writing
    // the part one of the slowest parts of a run) keeps it current on disk.
    if (endsUnit(envelope)) part.flush();
  }

  BufferedFileSink _openPart() {
    Directory(merging.partsDirectory).createSync(recursive: true);
    for (var n = 1; ; n++) {
      final suiteId = n == 1 ? merging.suiteId : '${merging.suiteId}#$n';
      final file = File(merging.partPath(suiteId));
      try {
        file.createSync(exclusive: true);
      } on FileSystemException {
        if (file.existsSync()) continue;
        rethrow;
      }
      _suiteId = suiteId;
      _writeAtomically(
        merging.manifestPath(suiteId),
        jsonEncode({
          'suiteId': suiteId,
          'outputs': [for (final output in outputs) output.key],
        }),
      );
      return BufferedFileSink.open(file);
    }
  }

  @override
  Future<void> close() async {
    final part = _part;
    if (part == null) return;
    _part = null;
    await part.close();
    await withMergeLock(merging.lockPath, () async {
      await mergeReports(merging, outputs);
      pruneReportParts(merging);
    });
  }

  @override
  String toString() => 'merged report (${outputs.join(', ')})';
}

/// A part listed in the run's directory.
final class _Manifest {
  _Manifest(this.suiteId, this.partPath, this.outputs);

  final String suiteId;
  final String partPath;
  final Set<String> outputs;
}

List<_Manifest> _readManifests(ReportMerging merging) {
  final directory = Directory(merging.partsDirectory);
  if (!directory.existsSync()) return const [];
  final manifests = <_Manifest>[];
  for (final file in directory.listSync().whereType<File>()) {
    if (p.extension(file.path) != '.json') continue;
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json case {
        'suiteId': final String suiteId,
        'outputs': final List<Object?> outputs,
      }) {
        manifests.add(
          _Manifest(suiteId, merging.partPath(suiteId), {
            for (final output in outputs)
              if (output is String) output,
          }),
        );
      }
    } on FormatException {
      // Not a manifest.
    } on FileSystemException {
      // Removed in the meantime.
    }
  }
  return manifests..sort((a, b) => a.suiteId.compareTo(b.suiteId));
}

/// Rewrites each of [outputs] from the merged parts of the run laid out by
/// [merging] that list it in their manifests (design §8.4). Parts are merged
/// in suite ID order.
///
/// Call it while holding the [MergeLock] of [merging].
Future<void> mergeReports(
  ReportMerging merging,
  List<ReportOutput> outputs,
) async {
  final manifests = _readManifests(merging);
  final parts = <String, List<messages.Envelope>>{};
  final merged = <String, List<messages.Envelope>>{};
  for (final output in outputs) {
    final contributing = [
      for (final manifest in manifests)
        if (manifest.outputs.contains(output.key)) manifest,
    ];
    final envelopes = merged[contributing.map((m) => m.suiteId).join('\n')] ??=
        mergeReportParts([
          for (final manifest in contributing)
            if (parts[manifest.partPath] ??= readReportPart(manifest.partPath)
                case final part when part.isNotEmpty)
              ReportPart(manifest.suiteId, part),
        ]);
    await writeReport(output, envelopes);
  }
}

/// How long the parts of another run are kept after their last modification
/// (design §8.4): a run whose parts have not changed for this long is no
/// longer in progress.
const Duration reportPartRetention = Duration(hours: 1);

/// Deletes the part directories of finished earlier runs below
/// [ReportMerging.runsDirectory] (design §8.4) and returns their paths.
///
/// A run's directory is deleted when it is not the run of [merging] and its
/// last modification (the latest modification time of its entries, or of the
/// directory itself if it is empty) is more than [retention] before [now]
/// (default: the current time). Suites write their parts as they run, so a
/// run that is still in progress has been modified recently and is kept.
///
/// Call it while holding the [MergeLock] of [merging], after merging. It
/// never throws: a directory that cannot be inspected or deleted is left
/// (possibly in part) for a later suite to prune.
List<String> pruneReportParts(
  ReportMerging merging, {
  DateTime? now,
  Duration retention = reportPartRetention,
}) {
  final deleted = <String>[];
  try {
    final runs = Directory(merging.runsDirectory);
    if (!runs.existsSync()) return deleted;
    final current = fileNameOf(merging.runId);
    final cutoff = (now ?? DateTime.now()).subtract(retention);
    for (final run in runs.listSync(followLinks: false)) {
      if (run is! Directory || p.basename(run.path) == current) continue;
      try {
        if (!_lastModified(run).isBefore(cutoff)) continue;
        run.deleteSync(recursive: true);
        deleted.add(run.path);
      } on Object {
        // In use, removed in the meantime, or not ours to delete: keep it.
      }
    }
  } on Object {
    // Pruning is housekeeping: it must never fail a suite.
  }
  return deleted;
}

DateTime _lastModified(Directory directory) {
  DateTime? latest;
  for (final entity in directory.listSync(followLinks: false)) {
    final modified = entity.statSync().modified;
    if (latest == null || modified.isAfter(latest)) latest = modified;
  }
  return latest ?? directory.statSync().modified;
}

/// Reads the NDJSON report part at [path]. An incomplete last line (of a
/// part that is still being written) is left out, as is a missing file.
///
/// Throws a [FormatException] if a line is not a Cucumber Messages envelope.
List<messages.Envelope> readReportPart(String path) {
  final Uint8List bytes;
  try {
    bytes = File(path).readAsBytesSync();
  } on PathNotFoundException {
    return const [];
  }
  final end = bytes.lastIndexOf(0x0a);
  if (end < 0) return const [];
  final text = utf8.decode(Uint8List.sublistView(bytes, 0, end));
  return [
    for (final (index, line) in const LineSplitter().convert(text).indexed)
      if (line.trim().isNotEmpty) _parseLine(line, index + 1),
  ];
}

messages.Envelope _parseLine(String line, int lineNumber) {
  try {
    return messages.parseEnvelopeJson(line, lineNumber: lineNumber);
  } on TypeError catch (error) {
    // A JSON object that does not match the Envelope schema.
    // The same wording as parseEnvelopeJson's errors.
    throw FormatException(
      'Failed to parse Envelope on line $lineNumber: $error',
    );
  }
}

/// Writes [envelopes] to [output], replacing the file in one step (through a
/// temporary file), so readers never see a partial report.
Future<void> writeReport(
  ReportOutput output,
  List<messages.Envelope> envelopes,
) async {
  final file = File(output.path);
  file.parent.createSync(recursive: true);
  final temporary = File('${output.path}.$pid.tmp');
  try {
    final sink = BufferedFileSink.open(temporary);
    try {
      switch (output.format) {
        case ReportFormat.message:
          for (final envelope in envelopes) {
            sink
              ..write(messages.envelopeToJsonString(envelope))
              ..write('\n');
          }
        case ReportFormat.html:
          final writer = MessagesToHtmlWriter(sink);
          envelopes.forEach(writer.write);
          writer.close();
      }
    } finally {
      await sink.close();
    }
    temporary.renameSync(output.path);
  } on Object {
    try {
      if (temporary.existsSync()) temporary.deleteSync();
    } on FileSystemException {
      // Nothing more to do.
    }
    rethrow;
  }
}

void _writeAtomically(String path, String contents) {
  final temporary = File('$path.$pid.tmp')..writeAsStringSync(contents);
  temporary.renameSync(path);
}
