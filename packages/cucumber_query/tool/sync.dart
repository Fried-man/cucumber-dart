// Synchronises the upstream cucumber/query acceptance test data into
// `testdata/` from a pinned commit, after verifying the SHA-256 digest of its
// content.
//
//   dart run tool/sync.dart          # (re)write testdata/
//   dart run tool/sync.dart --check  # exit 1 when testdata/ differs (CI drift check)
//
// Synced files:
//
// - `testdata/src/<sample>.<query>.results.json`: the expected result of each
//   query for a sample;
// - `testdata/src/<sample>.naming-strategy.<strategy>.txt`: the expected
//   pickle names for each naming strategy;
// - `testdata/src/<sample>.ndjson`: the messages of the samples above (copies
//   of Cucumber Compatibility Kit samples);
// - `testdata/LICENSE`: the upstream licence.
//
// GitHub does not guarantee that its source archives are byte-for-byte
// stable, so the digest covers the extracted files rather than the archive:
// it is the SHA-256 of the lines `<sha256 of file>  <path>\n` (the format of
// `sha256sum`), sorted by path. Files are written byte-for-byte;
// `.gitattributes` keeps git from rewriting them.
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The upstream commit whose test data is synced.
///
/// This is a commit on `main` after v16.1.1. The library code is unchanged
/// since v16.1.1, but its test data was regenerated from
/// `@cucumber/compatibility-kit` 31 and messages 34.2.1, which this repository
/// also uses. Update together with [_digest].
const String _upstreamCommit = '08bf6f03961cf7a07305b5f5d58a6a2d8a5c3cea';

/// A label for [_upstreamCommit].
const String _upstreamVersion = 'v16.1.1+08bf6f0';

/// The content digest of the upstream files at [_upstreamCommit].
const String _digest =
    'sha256-573f8ad425c1a815da5f3ea1e4a62444db03c0e839944079bc78b04d4d93ccca';

final Uri _archiveUrl = Uri.parse(
  'https://codeload.github.com/cucumber/query/tar.gz/$_upstreamCommit',
);

const String _testdataPrefix = 'testdata/src/';
const String _licenseEntry = 'LICENSE';
final RegExp _expectation = RegExp(
  r'^testdata/src/([^/.]+)\.(?:[^/.]+\.results\.json|naming-strategy\.[^/.]+\.txt)$',
);

/// The directory this tool owns completely: files in it that upstream does
/// not have are reported (with `--check`) or deleted.
const String _managedDirectory = 'testdata/';

/// Entry point; see the file header for usage.
Future<void> main(List<String> args) async {
  final check = args.contains('--check');
  if (args.any((arg) => arg != '--check')) {
    stderr.writeln('Usage: dart run tool/sync.dart [--check]');
    exitCode = 64;
    return;
  }

  final packageDir = Directory.fromUri(Platform.script.resolve('../'));
  final upstream = _selectUpstreamFiles(
    _extractFiles(gzip.decode(await _download(_archiveUrl))),
  );
  _verifyDigest(upstream);
  final expected = _outputs(upstream);
  const label = 'cucumber/query@$_upstreamVersion';

  if (check) {
    final problems = _compare(packageDir, expected);
    if (problems.isEmpty) {
      stdout.writeln('Synced files match $label (${expected.length} files).');
    } else {
      stderr
        ..writeln('Synced files are out of sync with $label:')
        ..writeAll(problems.map((problem) => '  $problem\n'))
        ..writeln('Run: dart run tool/sync.dart');
      exitCode = 1;
    }
    return;
  }

  final managed = Directory.fromUri(packageDir.uri.resolve(_managedDirectory));
  if (managed.existsSync()) {
    managed.deleteSync(recursive: true);
  }
  for (final MapEntry(key: path, value: bytes) in expected.entries) {
    final file = File.fromUri(
      packageDir.uri.resolveUri(Uri(pathSegments: path.split('/'))),
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes, flush: true);
  }
  stdout.writeln(
    'Wrote ${expected.length} files from $label to ${packageDir.path}',
  );
}

/// The upstream files this package uses, keyed by their upstream path: the
/// expectations, the samples they are about, and the licence.
SplayTreeMap<String, List<int>> _selectUpstreamFiles(
  Map<String, List<int>> files,
) {
  final samples = {
    for (final path in files.keys) ?_expectation.firstMatch(path)?[1],
  };
  final selected = SplayTreeMap<String, List<int>>();
  for (final MapEntry(key: path, value: bytes) in files.entries) {
    if (path == _licenseEntry || _expectation.hasMatch(path)) {
      selected[path] = bytes;
    } else if (path.startsWith(_testdataPrefix) && path.endsWith('.ndjson')) {
      final sample = path.substring(
        _testdataPrefix.length,
        path.length - '.ndjson'.length,
      );
      if (samples.contains(sample)) {
        selected[path] = bytes;
      }
    }
  }
  for (final sample in samples) {
    if (!selected.containsKey('$_testdataPrefix$sample.ndjson')) {
      throw StateError('$sample.ndjson is missing from $_archiveUrl');
    }
  }
  return selected;
}

/// The files to write, keyed by their path relative to the package.
SplayTreeMap<String, List<int>> _outputs(Map<String, List<int>> upstream) =>
    SplayTreeMap.of({
      for (final MapEntry(key: path, value: bytes) in upstream.entries)
        path == _licenseEntry ? 'testdata/LICENSE' : path: bytes,
    });

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

void _verifyDigest(Map<String, List<int>> files) {
  final actual = _contentDigest(files);
  if (actual != _digest) {
    throw StateError(
      'Content digest mismatch for $_archiveUrl\n'
      '  expected: $_digest\n'
      '  actual:   $actual',
    );
  }
}

/// The SHA-256 of `sha256sum`-style lines for [files], sorted by path.
String _contentDigest(Map<String, List<int>> files) {
  final paths = files.keys.toList()..sort();
  final manifest = StringBuffer();
  for (final path in paths) {
    manifest.write('${sha256.convert(files[path]!)}  $path\n');
  }
  return 'sha256-${sha256.convert(utf8.encode(manifest.toString()))}';
}

/// Returns the regular files of an uncompressed tar archive, keyed by their
/// `/`-separated path without the archive's top-level directory.
Map<String, List<int>> _extractFiles(List<int> tar) {
  final files = <String, List<int>>{};
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
      final slash = name.indexOf('/');
      if (slash > 0) {
        files[name.substring(slash + 1)] = data;
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

List<String> _compare(Directory packageDir, Map<String, List<int>> expected) {
  final actual = <String, List<int>>{};
  final root = packageDir.uri.path;
  final managed = Directory.fromUri(packageDir.uri.resolve(_managedDirectory));
  if (managed.existsSync()) {
    for (final entity in managed.listSync(recursive: true)) {
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
