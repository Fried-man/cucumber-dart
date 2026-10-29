import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:stack_trace/stack_trace.dart';

/// Packages whose frames are never reported as the location of user code.
const Set<String> internalPackages = {
  'cucumber_core',
  'cucumber',
  'cucumber_flutter',
  'stack_trace',
};

/// A location in Dart source code: where a glue value was constructed.
final class SourceReference {
  /// Creates a reference to [line] (and optionally [column]) of [uri].
  const SourceReference(this.uri, this.line, [this.column]);

  /// Captures the location of the caller: the first stack frame outside the
  /// cucumber packages and the Dart SDK.
  ///
  /// Returns `null` when no such frame can be found (for example, when stack
  /// traces are unavailable on the current platform).
  static SourceReference? capture() {
    try {
      final trace = StackTrace.current.toString();
      // Every glue value is captured, and parsing a whole trace takes about
      // a millisecond, most of glue loading (docs/performance.md). The user
      // frame is usually within the first few, so VM traces (`#0 …` lines)
      // are parsed one frame at a time.
      if (trace.startsWith('#')) {
        for (final line in trace.split('\n')) {
          if (!line.startsWith('#')) continue;
          final reference = _userFrame(Frame.parseVM(line));
          if (reference != null) return reference;
        }
        return null;
      }
      for (final frame in Trace.parse(trace).frames) {
        final reference = _userFrame(frame);
        if (reference != null) return reference;
      }
    } on Object {
      // Stack traces are best effort.
    }
    return null;
  }

  /// The reference to [frame], or `null` if it is not user code.
  static SourceReference? _userFrame(Frame frame) {
    if (frame.isCore || internalPackages.contains(frame.package)) return null;
    final line = frame.line;
    if (line == null) return null;
    return SourceReference(displayUri(frame.uri), line, frame.column);
  }

  /// The URI of the source file. `file:` URIs below the current directory are
  /// made relative, so they read like `test/steps/belly_steps.dart`.
  final String uri;

  /// The 1-based line number.
  final int line;

  /// The 1-based column number, when known.
  final int? column;

  /// This reference as a Cucumber Messages `SourceReference`.
  messages.SourceReference toMessage() => messages.SourceReference(
    uri: uri,
    location: messages.Location(line: line),
  );

  @override
  String toString() => column == null ? '$uri:$line' : '$uri:$line:$column';

  @override
  bool operator ==(Object other) =>
      other is SourceReference &&
      other.uri == uri &&
      other.line == line &&
      other.column == column;

  @override
  int get hashCode => Object.hash(uri, line, column);
}

/// Formats [uri] for messages: `file:` URIs below the current working directory
/// become relative paths with forward slashes; other URIs are kept as they are.
String displayUri(Uri uri) {
  if (uri.scheme == 'file') {
    try {
      final base = Uri.base;
      if (base.scheme == 'file') {
        final basePath = base.path.endsWith('/') ? base.path : '${base.path}/';
        final path = uri.path;
        if (path.toLowerCase().startsWith(basePath.toLowerCase())) {
          return path.substring(basePath.length);
        }
      }
    } on UnsupportedError {
      // Uri.base is not available on every platform.
    }
  }
  return uri.toString();
}
