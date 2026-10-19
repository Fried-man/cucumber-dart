import 'dart:io';

import 'package:cucumber_core/engine.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import 'configuration.dart';

/// The feature files of a suite, read from disk.
final class DiscoveredFeatures {
  /// Creates discovered features.
  const DiscoveredFeatures(this.sources, this.lines);

  /// The feature files, in discovery order, with URIs relative to the
  /// package root.
  final List<FeatureSource> sources;

  /// The lines selecting scenarios, per feature URI, for locations given as
  /// `path:line[:line]`.
  final Map<String, Set<int>> lines;
}

/// A feature location: a directory, glob or file, with optional lines.
final class FeatureLocation {
  /// Creates a location.
  const FeatureLocation(this.path, [this.lines = const []]);

  /// Parses `path`, `path:line` or `path:line:line…`.
  factory FeatureLocation.parse(String spec) {
    final value = spec.trim();
    final match = _withLines.firstMatch(value);
    if (match == null) return FeatureLocation(value);
    return FeatureLocation(match[1]!, [
      for (final line in match[2]!.substring(1).split(':')) int.parse(line),
    ]);
  }

  static final RegExp _withLines = RegExp(r'^(.+?)((?::\d+)+)$');

  /// The path or glob.
  final String path;

  /// The selected lines; empty to select the whole file.
  final List<int> lines;

  /// Whether [path] is a glob.
  bool get isGlob => path.contains(RegExp(r'[*?[{]'));

  @override
  String toString() => lines.isEmpty ? path : '$path:${lines.join(':')}';
}

/// Finds and reads the feature files at [locations] (design §5.10).
///
/// Locations are relative to [packageRoot] (or absolute):
///
/// - a directory selects every `*.feature` file below it, sorted by path;
/// - a glob (`features/**/checkout_*.feature`) selects the matching
///   `*.feature` files, sorted by path;
/// - a file selects itself;
/// - `path:line[:line]` selects the scenarios, rules, examples or example
///   rows at those lines.
///
/// A file selected several times keeps its first position. If it is selected
/// as a whole at least once, line selections for it are ignored.
///
/// Files are read synchronously, so suites can be declared synchronously.
/// Throws a [CucumberConfigurationException] for paths that do not exist.
DiscoveredFeatures discoverFeatures(
  List<String> locations, {
  required String packageRoot,
}) {
  final root = p.normalize(p.absolute(packageRoot));
  final files = <String, _Selection>{};

  void add(String path, List<int> lines) {
    final absolute = p.normalize(path);
    final selection = files.putIfAbsent(absolute, _Selection.new);
    if (lines.isEmpty) {
      selection.whole = true;
    } else {
      selection.lines.addAll(lines);
    }
  }

  for (final spec in locations) {
    final location = FeatureLocation.parse(spec);
    if (location.path.isEmpty) {
      throw CucumberConfigurationException('Empty feature location "$spec".');
    }
    for (final line in location.lines) {
      if (line < 1) {
        throw CucumberConfigurationException(
          'Invalid line $line in feature location "$spec".',
        );
      }
    }
    if (location.isGlob) {
      if (location.lines.isNotEmpty) {
        throw CucumberConfigurationException(
          'Lines cannot be combined with a glob: "$spec".',
        );
      }
      final pattern = p.isAbsolute(location.path)
          ? location.path.replaceAll(r'\', '/')
          : location.path;
      final matches = [
        for (final entity in Glob(pattern).listSync(root: root))
          if (entity is File && entity.path.endsWith('.feature'))
            p.normalize(p.absolute(entity.path)),
      ]..sort((a, b) => _uri(a, root).compareTo(_uri(b, root)));
      for (final match in matches) {
        add(match, const []);
      }
      continue;
    }

    final path = p.normalize(p.join(root, location.path));
    switch (FileSystemEntity.typeSync(path)) {
      case FileSystemEntityType.directory:
        if (location.lines.isNotEmpty) {
          throw CucumberConfigurationException(
            'Lines can only be given for a file, but "${location.path}" is '
            'a directory.',
          );
        }
        final found = [
          for (final entity in Directory(
            path,
          ).listSync(recursive: true, followLinks: true))
            if (entity is File &&
                entity.path.endsWith('.feature') &&
                !_isHidden(p.relative(entity.path, from: path)))
              p.normalize(entity.path),
        ]..sort((a, b) => _uri(a, root).compareTo(_uri(b, root)));
        for (final file in found) {
          add(file, const []);
        }
      case FileSystemEntityType.notFound:
        throw CucumberConfigurationException(
          'Feature location "${location.path}" does not exist '
          '(relative to $root).',
        );
      default:
        add(path, location.lines);
    }
  }

  final sources = <FeatureSource>[];
  final lines = <String, Set<int>>{};
  for (final MapEntry(key: path, value: selection) in files.entries) {
    final uri = _uri(path, root);
    sources.add(FeatureSource(uri, _read(path)));
    if (!selection.whole) lines[uri] = Set.unmodifiable(selection.lines);
  }
  return DiscoveredFeatures(
    List.unmodifiable(sources),
    Map.unmodifiable(lines),
  );
}

final class _Selection {
  bool whole = false;
  final Set<int> lines = {};
}

bool _isHidden(String relative) =>
    p.split(relative).any((segment) => segment.startsWith('.'));

/// The URI of [path] relative to [root], with forward slashes.
String _uri(String path, String root) =>
    p.split(p.relative(path, from: root)).join('/');

String _read(String path) {
  try {
    final text = File(path).readAsStringSync();
    return text.startsWith('\uFEFF') ? text.substring(1) : text;
  } on FileSystemException catch (e) {
    throw CucumberConfigurationException(
      'Cannot read feature file $path: ${e.message}',
    );
  }
}
