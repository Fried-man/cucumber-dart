import 'dart:io';

import 'package:cucumber_core/cucumber_core.dart';
import 'package:path/path.dart' as p;

/// Attaches the contents of the file at [path] to the current step or
/// test-run hook (design §7.4).
///
/// - A relative [path] is resolved against the current directory, which is
///   the package root under `dart test` and `flutter test`.
/// - The file is read when this is called, and attached Base64-encoded, so
///   it may be deleted or changed afterwards.
/// - [mediaType] defaults to the media type of the file's extension, such as
///   `image/png` for `.png` (common image, video, audio, text and document
///   types are known), or `application/octet-stream`.
/// - [fileName] defaults to the file's name, without its directory.
///
/// ```dart
/// After((Scenario scenario) {
///   if (scenario.isFailed) attachFile('build/screenshots/last.png');
/// }),
/// ```
///
/// Throws a [FileSystemException] if the file cannot be read, and a
/// [StateError] outside a scenario or test-run hook.
void attachFile(String path, {String? mediaType, String? fileName}) {
  final bytes = File(path).readAsBytesSync();
  attach(
    bytes,
    mediaType: mediaType ?? mediaTypeOfPath(path) ?? 'application/octet-stream',
    fileName: fileName ?? p.basename(path),
  );
}

/// The media type of a file with the extension of [path], such as
/// `image/png` for `screenshot.png`, or `null` for extensions that are not
/// known. The extension is compared without regard to case.
String? mediaTypeOfPath(String path) =>
    _mediaTypes[p.extension(path).toLowerCase()];

/// Media types by file extension: the ones Cucumber reports usually contain.
const Map<String, String> _mediaTypes = {
  '.avif': 'image/avif',
  '.bmp': 'image/bmp',
  '.css': 'text/css',
  '.csv': 'text/csv',
  '.gif': 'image/gif',
  '.htm': 'text/html',
  '.html': 'text/html',
  '.jpeg': 'image/jpeg',
  '.jpg': 'image/jpeg',
  '.js': 'text/javascript',
  '.json': 'application/json',
  '.log': 'text/plain',
  '.md': 'text/markdown',
  '.mp3': 'audio/mpeg',
  '.mp4': 'video/mp4',
  '.ndjson': 'application/x-ndjson',
  '.pdf': 'application/pdf',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.txt': 'text/plain',
  '.wav': 'audio/wav',
  '.webm': 'video/webm',
  '.webp': 'image/webp',
  '.xml': 'application/xml',
  '.yaml': 'application/yaml',
  '.yml': 'application/yaml',
  '.zip': 'application/zip',
};
