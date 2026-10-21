import 'package:cucumber_messages/cucumber_messages.dart' as messages;

/// The messages of one suite, to be merged with the messages of other suites
/// of the same run (design §8.4, ADR-0016).
final class ReportPart {
  /// Creates the part of the suite [suiteId], made of [envelopes] in emission
  /// order.
  ReportPart(this.suiteId, Iterable<messages.Envelope> envelopes)
    : envelopes = List.unmodifiable(envelopes);

  /// Identifies the suite: its `suiteName` or test file name. It becomes the
  /// `workerId` of the suite's test cases and test run hooks.
  final String suiteId;

  /// The suite's messages, in emission order.
  final List<messages.Envelope> envelopes;

  @override
  String toString() => 'ReportPart($suiteId, ${envelopes.length} messages)';
}

/// Merges the messages of several suites of one run into a single stream
/// (design §8.4, ADR-0016).
///
/// - **One `meta`**: the first part's.
/// - **Static messages** (`source`, `gherkinDocument`, `parseError`, `pickle`,
///   `parameterType`, `stepDefinition`, `hook`, `undefinedParameterType`) are
///   de-duplicated: sources and Gherkin documents by URI, the others by ID
///   (static IDs are deterministic, ADR-0018), and messages without an ID by
///   their content. The first occurrence is kept.
/// - **One synthetic `testRunStarted`**, with the earliest timestamp of the
///   parts and the ID of the first part's, and **one `testRunFinished`**
///   (when at least one part finished), with the latest timestamp. Its
///   `success` is true only if every part finished and succeeded; its
///   `message` mentions the parts that did not finish, and its `exception`
///   is the first part's.
/// - **`testRunStartedId`** references are remapped to the synthetic test
///   run.
/// - **`workerId`** is set to the part's [ReportPart.suiteId] on
///   `testCaseStarted` and `testRunHookStarted`, as cucumber-js does for its
///   parallel workers.
/// - **Dynamic IDs** (test cases, test steps, attempts, hook runs,
///   suggestions) are kept, unless they are already used by an earlier part
///   or a static message, as happens when parts use incrementing IDs. Such
///   IDs are renamed `<suiteId>/<id>`, and every reference in the part
///   follows.
///
/// The result is in a valid order (design §7.1): `meta`, the Gherkin
/// messages, the glue messages, `testRunStarted`, then the dynamic messages
/// of each part, one part after the other, in the given order (parts that
/// did not finish come last), and `testRunFinished`.
///
/// This is a pure function: it reads no files and keeps no state. Throws an
/// [ArgumentError] if two parts have the same suite ID.
List<messages.Envelope> mergeReportParts(Iterable<ReportPart> parts) {
  final list = parts.toList();
  final suiteIds = <String>{};
  for (final part in list) {
    if (!suiteIds.add(part.suiteId)) {
      throw ArgumentError.value(
        part.suiteId,
        'parts',
        'Two report parts have the same suite ID',
      );
    }
  }
  return _Merger(list).merge();
}

enum _Kind { meta, gherkin, glue, testRunStarted, testRunFinished, execution }

_Kind _kindOf(messages.Envelope envelope) {
  if (envelope.meta != null) return _Kind.meta;
  if (envelope.source != null ||
      envelope.gherkinDocument != null ||
      envelope.parseError != null ||
      envelope.pickle != null) {
    return _Kind.gherkin;
  }
  if (envelope.parameterType != null ||
      envelope.stepDefinition != null ||
      envelope.hook != null ||
      envelope.undefinedParameterType != null) {
    return _Kind.glue;
  }
  if (envelope.testRunStarted != null) return _Kind.testRunStarted;
  if (envelope.testRunFinished != null) return _Kind.testRunFinished;
  return _Kind.execution;
}

/// The key that identifies a static message across parts.
String _staticKey(messages.Envelope envelope) {
  if (envelope.source case final source?) return 'source ${source.uri}';
  if (envelope.gherkinDocument case final document?) {
    if (document.uri case final uri?) return 'gherkinDocument $uri';
  }
  final id =
      envelope.pickle?.id ??
      envelope.stepDefinition?.id ??
      envelope.hook?.id ??
      envelope.parameterType?.id;
  if (id != null) return 'id $id';
  return messages.envelopeToJsonString(envelope);
}

/// One part, split by kind.
final class _SplitPart {
  _SplitPart(this.part) {
    for (final envelope in part.envelopes) {
      switch (_kindOf(envelope)) {
        case _Kind.meta:
          meta ??= envelope.meta;
        case _Kind.gherkin:
          gherkin.add(envelope);
        case _Kind.glue:
          glue.add(envelope);
        case _Kind.testRunStarted:
          testRunStarted ??= envelope.testRunStarted;
        case _Kind.testRunFinished:
          testRunFinished = envelope.testRunFinished;
        case _Kind.execution:
          execution.add(envelope.toJson());
      }
    }
  }

  final ReportPart part;
  messages.Meta? meta;
  final List<messages.Envelope> gherkin = [];
  final List<messages.Envelope> glue = [];
  messages.TestRunStarted? testRunStarted;
  messages.TestRunFinished? testRunFinished;

  /// The dynamic messages as JSON, so their IDs can be rewritten.
  final List<Map<String, Object?>> execution = [];

  String get suiteId => part.suiteId;

  bool get finished => testRunStarted != null && testRunFinished != null;

  /// Renamed IDs of this part.
  final Map<String, String> ids = {};
}

final class _Merger {
  _Merger(List<ReportPart> parts)
    : _parts = [for (final part in parts) _SplitPart(part)];

  final List<_SplitPart> _parts;

  /// Every ID in the output so far.
  final Set<String> _used = {};

  List<messages.Envelope> merge() {
    final output = <messages.Envelope>[];
    for (final part in _parts) {
      if (part.meta case final meta?) {
        output.add(messages.Envelope(meta: meta));
        break;
      }
    }

    final seen = <String>{};
    void addStatic(Iterable<messages.Envelope> envelopes) {
      for (final envelope in envelopes) {
        if (seen.add(_staticKey(envelope))) {
          output.add(envelope);
          _visitIds(envelope.toJson(), _used.add);
        }
      }
    }

    for (final part in _parts) {
      addStatic(part.gherkin);
    }
    for (final part in _parts) {
      addStatic(part.glue);
    }

    // Rename the dynamic IDs that clash with earlier ones.
    for (final part in _parts) {
      void claim(String id) {
        if (_used.add(id)) return;
        var renamed = '${part.suiteId}/$id';
        for (var n = 2; !_used.add(renamed); n++) {
          renamed = '${part.suiteId}/$id#$n';
        }
        part.ids[id] = renamed;
      }

      if (part.testRunStarted?.id case final id?) claim(id);
      for (final json in part.execution) {
        _visitIds(json, claim);
      }
    }

    final started = [
      for (final part in _parts)
        if (part.testRunStarted case final started?) (part, started),
    ];
    String? testRunStartedId;
    if (started.isNotEmpty) {
      for (final (part, started) in started) {
        if (started.id case final id?) {
          testRunStartedId ??= part.ids[id] ?? id;
          part.ids[id] = testRunStartedId;
        }
      }
      output.add(
        messages.Envelope(
          testRunStarted: messages.TestRunStarted(
            id: testRunStartedId,
            timestamp: _earliest([for (final (_, s) in started) s.timestamp]),
          ),
        ),
      );
    }

    for (final part in [
      ..._parts.where((part) => part.finished),
      ..._parts.where((part) => !part.finished),
    ]) {
      for (final json in part.execution) {
        final remapped = _remap(json, part.ids)! as Map<String, Object?>;
        for (final type in const ['testCaseStarted', 'testRunHookStarted']) {
          if (remapped[type] case final Map<String, Object?> message) {
            message['workerId'] = part.suiteId;
          }
        }
        output.add(messages.Envelope.fromJson(remapped));
      }
    }

    if (_testRunFinished(testRunStartedId) case final finished?) {
      output.add(messages.Envelope(testRunFinished: finished));
    }
    return output;
  }

  messages.TestRunFinished? _testRunFinished(String? testRunStartedId) {
    final finished = [for (final part in _parts) ?part.testRunFinished];
    if (finished.isEmpty) return null;
    final several = _parts.length > 1;
    final notes = [
      for (final part in _parts)
        if (!part.finished)
          'The report part of suite "${part.suiteId}" did not finish.'
        else if (part.testRunFinished!.message case final message?)
          several ? 'Suite "${part.suiteId}": $message' : message,
    ];
    return messages.TestRunFinished(
      success: _parts.every(
        (part) => part.finished && part.testRunFinished!.success,
      ),
      timestamp: _latest([for (final f in finished) f.timestamp]),
      testRunStartedId: testRunStartedId,
      message: notes.isEmpty ? null : notes.join('\n\n'),
      exception: [for (final f in finished) ?f.exception].firstOrNull,
    );
  }
}

int _compare(messages.Timestamp a, messages.Timestamp b) {
  final seconds = a.seconds.compareTo(b.seconds);
  return seconds != 0 ? seconds : a.nanos.compareTo(b.nanos);
}

messages.Timestamp _earliest(List<messages.Timestamp> timestamps) =>
    timestamps.reduce((a, b) => _compare(b, a) < 0 ? b : a);

messages.Timestamp _latest(List<messages.Timestamp> timestamps) =>
    timestamps.reduce((a, b) => _compare(b, a) > 0 ? b : a);

/// Calls [visit] with every ID that [json] defines: the values of its `id`
/// keys, at any depth.
void _visitIds(Object? json, void Function(String id) visit) {
  if (json is List<Object?>) {
    for (final item in json) {
      _visitIds(item, visit);
    }
  } else if (json is Map<String, Object?>) {
    for (final MapEntry(:key, :value) in json.entries) {
      if (key == 'id' && value is String) {
        visit(value);
      } else {
        _visitIds(value, visit);
      }
    }
  }
}

/// A copy of [json] whose IDs and ID references (`id`, `…Id` and `…Ids`
/// keys, but not `workerId`) are renamed with [ids].
Object? _remap(Object? json, Map<String, String> ids) {
  if (json is List<Object?>) {
    return [for (final item in json) _remap(item, ids)];
  }
  if (json is! Map<String, Object?>) return json;
  return <String, Object?>{
    for (final MapEntry(:key, :value) in json.entries)
      key: switch (value) {
        final String id
            when key != 'workerId' && (key == 'id' || key.endsWith('Id')) =>
          ids[id] ?? id,
        final List<Object?> list when key.endsWith('Ids') => [
          for (final id in list) id is String ? ids[id] ?? id : id,
        ],
        _ => _remap(value, ids),
      },
  };
}
