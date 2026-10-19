import 'dart:async';
import 'dart:convert';

import 'package:cucumber_messages/cucumber_messages.dart' as messages;

/// The media type of `log` attachments.
const String logMediaType = 'text/x.cucumber.log+plain';

/// The media type of `link` attachments.
const String linkMediaType = 'text/uri-list';

/// Where attachments go: a running scenario or test-run hook.
abstract class ExecutionContext {
  /// Attaches [data] to the current step or hook.
  void attach(Object data, {String? mediaType, String? fileName});

  /// Attaches [text] as a log message.
  void log(String text) => attach(text, mediaType: logMediaType);

  /// Attaches a link to [url], with an optional [title].
  void link(String url, {String? title}) =>
      attach(url, mediaType: linkMediaType, fileName: title);
}

final Object _contextKey = Object();

/// The context of the code running in the current zone, if any.
ExecutionContext? get currentContext =>
    Zone.current[_contextKey] as ExecutionContext?;

/// The context of the code running in the current zone.
///
/// Throws a [StateError] outside a scenario or test-run hook.
ExecutionContext requireContext(String member) {
  final context = currentContext;
  if (context == null) {
    throw StateError(
      '$member can only be used while a scenario or test-run hook is running.',
    );
  }
  return context;
}

/// Runs [body] with [context] as the current context.
R runInContext<R>(ExecutionContext context, R Function() body) =>
    runZoned(body, zoneValues: {_contextKey: context});

/// Runs [body] in an error zone with [context] as the current context;
/// uncaught errors go to [onError].
void runGuardedInContext(
  ExecutionContext context,
  void Function() body,
  void Function(Object error, StackTrace stackTrace) onError,
) {
  runZonedGuarded(body, onError, zoneValues: {_contextKey: context});
}

/// Builds an attachment message body for [data] (design §7.4).
///
/// Strings are attached as-is (`text/plain` by default); byte lists are
/// Base64-encoded (`application/octet-stream` by default).
({String body, messages.AttachmentContentEncoding encoding, String mediaType})
encodeAttachment(Object data, String? mediaType) {
  if (data is String) {
    return (
      body: data,
      encoding: messages.AttachmentContentEncoding.identity,
      mediaType: mediaType ?? 'text/plain',
    );
  }
  if (data is List<int>) {
    return (
      body: base64Encode(data),
      encoding: messages.AttachmentContentEncoding.base64,
      mediaType: mediaType ?? 'application/octet-stream',
    );
  }
  throw ArgumentError.value(
    data,
    'data',
    'Attachments must be a String or a List<int>, not ${data.runtimeType}',
  );
}
