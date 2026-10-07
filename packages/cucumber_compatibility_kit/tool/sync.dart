// Synchronises the Cucumber Compatibility Kit samples into `features/` from the
// pinned npm tarball, after verifying its published SHA-512 integrity.
//
//   dart run tool/sync.dart          # (re)write features/
//   dart run tool/sync.dart --check  # exit 1 when features/ differs (CI drift check)
//
// Files are written byte-for-byte; `.gitattributes` keeps git from rewriting
// them. See docs/decisions/0019-compatibility-kit-conformance.md.
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cucumber_compatibility_kit/cucumber_compatibility_kit.dart';

/// The npm `dist.integrity` of the pinned `@cucumber/compatibility-kit`.
///
/// Update together with [compatibilityKitVersion].
const String _integrity =
    'sha512-0UGPMXQiZfy8cNEdcHnu9/Ov+VmjgoW0hwxbnOv8PEjIGxvvSGAwtnzdkMlFS0u0cdU8BfvAzRRervtlbm0GPA==';

final Uri _tarballUrl = Uri.parse(
  'https://registry.npmjs.org/@cucumber/compatibility-kit/-/'
  'compatibility-kit-$compatibilityKitVersion.tgz',
);

const String _samplesPrefix = 'package/features/';
const String _licenseEntry = 'package/LICENSE';

/// Entry point; see the file header for usage.
Future<void> main(List<String> args) async {
  final check = args.contains('--check');
  if (args.any((arg) => arg != '--check')) {
    stderr.writeln('Usage: dart run tool/sync.dart [--check]');
    exitCode = 64;
    return;
  }

  final featuresDir = Directory.fromUri(
    Platform.script.resolve('../features/'),
  );
  final tarball = await _download(_tarballUrl);
  _verifyIntegrity(tarball);
  final expected = _extractSamples(gzip.decode(tarball));
  final label = '@cucumber/compatibility-kit@$compatibilityKitVersion';

  if (check) {
    final problems = _compare(featuresDir, expected);
    if (problems.isEmpty) {
      stdout.writeln('features/ matches $label (${expected.length} files).');
    } else {
      stderr
        ..writeln('features/ is out of sync with $label:')
        ..writeAll(problems.map((problem) => '  $problem\n'))
        ..writeln('Run: dart run tool/sync.dart');
      exitCode = 1;
    }
    return;
  }

  if (featuresDir.existsSync()) {
    featuresDir.deleteSync(recursive: true);
  }
  for (final MapEntry(key: path, value: bytes) in expected.entries) {
    final file = File.fromUri(
      featuresDir.uri.resolveUri(Uri(pathSegments: path.split('/'))),
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes, flush: true);
  }
  stdout.writeln(
    'Wrote ${expected.length} files from $label to ${featuresDir.path}',
  );
}

Future<Uint8List> _download(Uri url) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'GET $url failed with HTTP ${response.statusCode}',
        uri: url,
      );
    }
    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add);
    return builder.takeBytes();
  } finally {
    client.close();
  }
}

void _verifyIntegrity(List<int> bytes) {
  final actual = 'sha512-${base64.encode(sha512.convert(bytes).bytes)}';
  if (actual != _integrity) {
    throw StateError(
      'Integrity mismatch for $_tarballUrl\n'
      '  expected: $_integrity\n'
      '  actual:   $actual',
    );
  }
}

/// Returns the sample files (and the upstream LICENSE) from an uncompressed
/// tar archive, keyed by their `/`-separated path relative to `features/`.
SplayTreeMap<String, List<int>> _extractSamples(List<int> tar) {
  final files = SplayTreeMap<String, List<int>>();
  String? paxPath;
  var offset = 0;
  while (offset + 512 <= tar.length) {
    final header = tar.sublist(offset, offset + 512);
    if (header.every((byte) => byte == 0)) {
      break; // End-of-archive marker.
    }
    final sizeField = _field(header, 124, 12).trim();
    final size = sizeField.isEmpty ? 0 : int.parse(sizeField, radix: 8);
    final dataStart = offset + 512;
    final data = tar.sublist(dataStart, dataStart + size);
    offset = dataStart + ((size + 511) ~/ 512) * 512;

    final type = header[156];
    if (type == 0x78) {
      // 'x': PAX extended header describing the next entry.
      paxPath = _paxPath(data);
    } else if (type == 0x30 || type == 0x00) {
      // '0' or NUL: regular file.
      final name = paxPath ?? _ustarName(header);
      paxPath = null;
      if (name.startsWith(_samplesPrefix)) {
        files[name.substring(_samplesPrefix.length)] = data;
      } else if (name == _licenseEntry) {
        files['LICENSE'] = data;
      }
    } else if (type != 0x67) {
      // Anything else except a global PAX header ('g'): directories, links.
      paxPath = null;
    }
  }
  return files;
}

String _ustarName(List<int> header) {
  final name = _field(header, 0, 100);
  final isUstar = _field(header, 257, 6).startsWith('ustar');
  final prefix = isUstar ? _field(header, 345, 155) : '';
  return prefix.isEmpty ? name : '$prefix/$name';
}

String _field(List<int> header, int start, int length) {
  final bytes = header.sublist(start, start + length);
  final end = bytes.indexOf(0);
  return utf8.decode(end < 0 ? bytes : bytes.sublist(0, end));
}

/// Extracts the `path` record from PAX extended header [data]
/// (records of the form `"<length> <key>=<value>\n"`).
String? _paxPath(List<int> data) {
  String? path;
  var index = 0;
  while (index < data.length) {
    final space = data.indexOf(0x20, index);
    if (space < 0) {
      break;
    }
    final length = int.parse(ascii.decode(data.sublist(index, space)));
    final record = utf8.decode(data.sublist(space + 1, index + length - 1));
    final equals = record.indexOf('=');
    if (equals > 0 && record.substring(0, equals) == 'path') {
      path = record.substring(equals + 1);
    }
    index += length;
  }
  return path;
}

List<String> _compare(Directory dir, Map<String, List<int>> expected) {
  final actual = <String, List<int>>{};
  if (dir.existsSync()) {
    final root = dir.uri.path;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) {
        final relative = Uri.decodeComponent(
          entity.uri.path.substring(root.length),
        );
        actual[relative] = entity.readAsBytesSync();
      }
    }
  }

  final problems = <String>[];
  for (final MapEntry(key: path, value: bytes) in expected.entries) {
    final found = actual.remove(path);
    if (found == null) {
      problems.add('missing:    $path');
    } else if (!_sameBytes(found, bytes)) {
      problems.add('changed:    $path');
    }
  }
  problems
    ..addAll(actual.keys.map((path) => 'unexpected: $path'))
    ..sort();
  return problems;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
