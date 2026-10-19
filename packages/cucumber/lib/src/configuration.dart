import 'dart:convert';
import 'dart:io';

import 'package:cucumber_core/engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart' show Timeout;
import 'package:yaml/yaml.dart';

import 'options.dart';

/// Thrown from `cucumber()` when the configuration is invalid, so `dart test`
/// reports a load failure for the test file.
final class CucumberConfigurationException implements Exception {
  /// Creates an exception with [message].
  CucumberConfigurationException(this.message);

  /// What is wrong, and where it was set.
  final String message;

  @override
  String toString() => 'CucumberConfigurationException: $message';
}

/// The names of the configuration files looked up in the package root, in
/// order of preference.
const List<String> configurationFileNames = ['cucumber.yaml', 'cucumber.yml'];

/// The settings of a suite after merging every source and applying the
/// defaults (design §4.9).
final class ResolvedConfiguration {
  /// Creates a resolved configuration.
  const ResolvedConfiguration({
    required this.features,
    required this.tags,
    required this.names,
    required this.retry,
    required this.order,
    required this.dryRun,
    required this.worldParameters,
    required this.plugins,
    required this.suiteName,
    required this.profiles,
    required this.mapTags,
    required this.scenarioTimeout,
  });

  /// Feature locations.
  final List<String> features;

  /// The tag expression, if any.
  final String? tags;

  /// Name patterns.
  final List<String> names;

  /// Extra attempts for FAILED scenarios.
  final int retry;

  /// The pickle order.
  final PickleOrder order;

  /// Whether this is a dry run.
  final bool dryRun;

  /// The world parameters.
  final Map<String, Object?> worldParameters;

  /// Plugin specifications and instances.
  final List<Object> plugins;

  /// The suite name, if known.
  final String? suiteName;

  /// The profiles that were applied, in order.
  final List<String> profiles;

  /// Whether Gherkin tags become `package:test` tags.
  final bool mapTags;

  /// The timeout of one scenario attempt.
  final Timeout? scenarioTimeout;

  /// The [RunOptions] for the engine, with [lines] from feature discovery.
  RunOptions toRunOptions({Map<String, Set<int>> lines = const {}}) =>
      RunOptions(
        tags: tags,
        names: names,
        lines: lines,
        order: order,
        retry: retry,
        dryRun: dryRun,
        worldParameters: worldParameters,
      );
}

/// Resolves the configuration of a suite whose options in code are [code].
///
/// Sources are merged with this precedence (later sources win):
///
/// > built-in defaults < [code] < `cucumber.yaml` profile(s) in
/// > [packageRoot] < `CUCUMBER_*` variables in [environment]
///
/// Values are merged with [CucumberOptions.merge]: scalars and lists are
/// replaced, tag expressions are combined with `and` and world parameters are
/// merged. One exception: when a profile or the environment sets `plugins`,
/// it replaces the plugin specifications from code, but [Plugin] instances
/// from code are kept, since they cannot be given anywhere else.
///
/// Throws a [CucumberConfigurationException] for invalid values.
ResolvedConfiguration resolveConfiguration(
  CucumberOptions code, {
  required String packageRoot,
  required Map<String, String> environment,
}) {
  final file = ConfigurationFile.find(packageRoot);
  final envProfile = _nonBlank(environment['CUCUMBER_PROFILE']);
  final requested = envProfile ?? _nonBlank(code.profile);
  final List<String> profiles;
  if (requested != null) {
    profiles = _splitList(requested);
  } else if (file != null && file.hasProfile('default')) {
    profiles = const ['default'];
  } else {
    profiles = const [];
  }

  var merged = code;
  // Plugin specifications set by a profile or the environment replace the
  // ones in code. Plugin instances can only be given in code, so they are
  // kept.
  List<Object>? configuredPlugins;
  void apply(CucumberOptions options) {
    configuredPlugins = options.plugins ?? configuredPlugins;
    merged = merged.merge(options);
  }

  for (final name in profiles) {
    if (file == null) {
      throw CucumberConfigurationException(
        'Profile "$name" was requested'
        '${envProfile != null ? ' by CUCUMBER_PROFILE' : ''}, but there is no '
        '${configurationFileNames.first} in $packageRoot.',
      );
    }
    apply(file.profile(name));
  }
  apply(optionsFromEnvironment(environment));
  if (configuredPlugins case final plugins?) {
    merged = merged.merge(
      CucumberOptions(
        plugins: [
          for (final plugin in code.plugins ?? const <Object>[])
            if (plugin is Plugin) plugin,
          ...plugins,
        ],
      ),
    );
  }
  return _applyDefaults(merged, profiles);
}

ResolvedConfiguration _applyDefaults(
  CucumberOptions options,
  List<String> profiles,
) {
  final retry = options.retry ?? 0;
  if (retry < 0) {
    throw CucumberConfigurationException(
      'retry must not be negative, got $retry.',
    );
  }
  final PickleOrder order;
  try {
    order = PickleOrder.parse(options.order ?? 'defined');
  } on ArgumentError {
    throw CucumberConfigurationException(
      'Invalid order "${options.order}". Expected defined, reverse, random '
      'or random:<seed>.',
    );
  }
  return ResolvedConfiguration(
    features: options.features ?? const ['features/'],
    tags: options.tags,
    names: options.names ?? const [],
    retry: retry,
    order: order,
    dryRun: options.dryRun ?? false,
    worldParameters: options.worldParameters ?? const {},
    plugins: options.plugins ?? const [],
    suiteName: options.suiteName,
    profiles: List.unmodifiable(profiles),
    mapTags: options.mapTags ?? true,
    scenarioTimeout: options.scenarioTimeout,
  );
}

/// The options set by `CUCUMBER_*` variables in [environment] (design §4.9).
/// Blank variables are ignored.
CucumberOptions optionsFromEnvironment(Map<String, String> environment) {
  String? read(String name) => _nonBlank(environment[name]);

  final features = read('CUCUMBER_FEATURES');
  final tags = read('CUCUMBER_FILTER_TAGS');
  final name = read('CUCUMBER_FILTER_NAME');
  final plugins = read('CUCUMBER_PLUGIN');
  final dryRun = read('CUCUMBER_EXECUTION_DRY_RUN');
  final order = read('CUCUMBER_EXECUTION_ORDER');
  final retry = read('CUCUMBER_EXECUTION_RETRY');
  final parameters = read('CUCUMBER_WORLD_PARAMETERS');

  return CucumberOptions(
    features: features == null ? null : _splitList(features),
    tags: tags,
    names: name == null ? null : [name],
    plugins: plugins == null ? null : _splitList(plugins),
    dryRun: dryRun == null
        ? null
        : switch (dryRun.toLowerCase()) {
            'true' => true,
            'false' => false,
            _ => throw CucumberConfigurationException(
              'CUCUMBER_EXECUTION_DRY_RUN must be true or false, got '
              '"$dryRun".',
            ),
          },
    order: order,
    retry: retry == null
        ? null
        : int.tryParse(retry) ??
              (throw CucumberConfigurationException(
                'CUCUMBER_EXECUTION_RETRY must be an integer, got "$retry".',
              )),
    worldParameters: parameters == null ? null : _decodeParameters(parameters),
  );
}

Map<String, Object?> _decodeParameters(String json) {
  Object? value;
  try {
    value = jsonDecode(json);
  } on FormatException catch (e) {
    throw CucumberConfigurationException(
      'CUCUMBER_WORLD_PARAMETERS is not valid JSON: ${e.message}',
    );
  }
  if (value is! Map<String, Object?>) {
    throw CucumberConfigurationException(
      'CUCUMBER_WORLD_PARAMETERS must be a JSON object, got $json',
    );
  }
  return value;
}

/// A parsed `cucumber.yaml`: named profiles of options (design §4.9).
final class ConfigurationFile {
  ConfigurationFile._(this.path, this._profiles);

  /// Parses [contents], read from [path].
  ///
  /// Throws a [CucumberConfigurationException] if it is not a map of
  /// profiles.
  factory ConfigurationFile.parse(
    String contents, {
    String path = 'cucumber.yaml',
  }) {
    final Object? document;
    try {
      document = loadYaml(contents, sourceUrl: Uri.file(path));
    } on YamlException catch (e) {
      throw CucumberConfigurationException('$path is not valid YAML: $e');
    }
    if (document == null) return ConfigurationFile._(path, const {});
    if (document is! YamlMap) {
      throw CucumberConfigurationException(
        '$path must map profile names to options.',
      );
    }
    return ConfigurationFile._(path, {
      for (final entry in document.entries) '${entry.key}': entry.value,
    });
  }

  /// Reads the configuration file in [packageRoot], if there is one.
  static ConfigurationFile? find(String packageRoot) {
    for (final name in configurationFileNames) {
      final file = File(p.join(packageRoot, name));
      if (file.existsSync()) {
        return ConfigurationFile.parse(file.readAsStringSync(), path: name);
      }
    }
    return null;
  }

  /// The file's path, for error messages.
  final String path;

  final Map<String, Object?> _profiles;

  /// The profile names, in file order.
  Iterable<String> get profileNames => _profiles.keys;

  /// Whether the file defines profile [name].
  bool hasProfile(String name) => _profiles.containsKey(name);

  /// The options of profile [name].
  ///
  /// Throws a [CucumberConfigurationException] if there is no such profile or
  /// it has invalid options.
  CucumberOptions profile(String name) {
    if (!_profiles.containsKey(name)) {
      throw CucumberConfigurationException(
        'Profile "$name" is not defined in $path. Defined profiles: '
        '${profileNames.isEmpty ? '(none)' : profileNames.join(', ')}.',
      );
    }
    final value = _profiles[name];
    if (value == null) return CucumberOptions();
    if (value is! YamlMap) {
      throw CucumberConfigurationException(
        'Profile "$name" in $path must be a map of options.',
      );
    }
    return _ProfileReader(path, name, value).read();
  }
}

final class _ProfileReader {
  _ProfileReader(this.path, this.name, this.map);

  final String path;
  final String name;
  final YamlMap map;

  static const _keys = {
    'features',
    'tags',
    'names',
    'retry',
    'order',
    'dryRun',
    'worldParameters',
    'plugins',
    'suiteName',
    'mapTags',
    'scenarioTimeout',
  };

  Never _error(String key, String problem) =>
      throw CucumberConfigurationException(
        '$path, profile "$name", $key: $problem',
      );

  CucumberOptions read() {
    for (final key in map.keys) {
      if (key == 'glue' || key == 'world') {
        _error('$key', 'can only be set in code.');
      }
      if (key == 'profile') {
        _error('$key', 'profiles cannot select other profiles.');
      }
      if (!_keys.contains(key)) {
        _error('$key', 'unknown option. Known options: ${_keys.join(', ')}.');
      }
    }
    return CucumberOptions(
      features: _strings('features'),
      tags: _string('tags'),
      names: _strings('names'),
      retry: _int('retry'),
      order: _string('order'),
      dryRun: _bool('dryRun'),
      worldParameters: _map('worldParameters'),
      plugins: _strings('plugins'),
      suiteName: _string('suiteName'),
      mapTags: _bool('mapTags'),
      scenarioTimeout: _timeout('scenarioTimeout'),
    );
  }

  String? _string(String key) => switch (map[key]) {
    null => null,
    final String s => s,
    final num n => '$n',
    final other => _error(key, 'expected a string, got $other.'),
  };

  List<String>? _strings(String key) => switch (map[key]) {
    null => null,
    final String s => [s],
    final YamlList list => [
      for (final item in list)
        if (item is String)
          item
        else
          _error(key, 'expected strings, got $item.'),
    ],
    final other => _error(key, 'expected a list of strings, got $other.'),
  };

  int? _int(String key) => switch (map[key]) {
    null => null,
    final int i => i,
    final other => _error(key, 'expected an integer, got $other.'),
  };

  bool? _bool(String key) => switch (map[key]) {
    null => null,
    final bool b => b,
    final other => _error(key, 'expected true or false, got $other.'),
  };

  Map<String, Object?>? _map(String key) => switch (map[key]) {
    null => null,
    final YamlMap m => _plain(m)! as Map<String, Object?>,
    final other => _error(key, 'expected a map, got $other.'),
  };

  Timeout? _timeout(String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is num) {
      // A number of seconds.
      return Timeout(Duration(milliseconds: (value * 1000).round()));
    }
    if (value is String) {
      if (value.trim() == 'none') return Timeout.none;
      try {
        return Timeout.parse(value);
      } on FormatException {
        // Reported below.
      }
    }
    _error(key, 'expected a duration such as 30s, 2m or 1.5x, got $value.');
  }
}

/// Converts YAML collections to plain Dart maps and lists.
Object? _plain(Object? value) => switch (value) {
  final YamlMap map => <String, Object?>{
    for (final entry in map.entries) '${entry.key}': _plain(entry.value),
  },
  final YamlList list => [for (final item in list) _plain(item)],
  _ => value,
};

String? _nonBlank(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

List<String> _splitList(String value) => [
  for (final item in value.split(','))
    if (item.trim().isNotEmpty) item.trim(),
];
