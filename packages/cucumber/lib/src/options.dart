import 'package:cucumber_core/engine.dart';
import 'package:test/test.dart' show Timeout;

/// The options of a Cucumber suite (design §4.8, ADR-0012).
///
/// An options value is immutable. Every field is optional: `null` means "not
/// set here", so values can be layered with [merge]. Unset fields fall back
/// to the configuration files, the environment and the built-in defaults
/// (design §4.9):
///
/// > built-in defaults < code < `cucumber.yaml` profile(s) < `CUCUMBER_*`
/// > environment variables
///
/// ```dart
/// final base = CucumberOptions(glue: shopGlue, world: ShopWorld.new);
///
/// void main() => CucumberSuite<ShopWorld>(
///   base.merge(CucumberOptions(features: ['features/checkout/'])),
/// ).declare();
/// ```
final class CucumberOptions {
  /// Creates options. Lists and maps are copied.
  ///
  /// - [glue]: steps, hooks and types, in definition order. Code only.
  /// - [world]: creates the World for each scenario attempt. Code only.
  /// - [features]: feature locations: directories (searched recursively for
  ///   `*.feature`), globs, files and `path:line[:line]`, relative to the
  ///   package root. Default: `['features/']`.
  /// - [tags]: a Cucumber tag expression selecting scenarios.
  /// - [names]: regular expressions, one of which must match a scenario's
  ///   name.
  /// - [retry]: extra attempts for FAILED scenarios. Default: 0.
  /// - [order]: `defined` (default), `reverse`, `random` or `random:<seed>`.
  /// - [dryRun]: report the steps without running any user code.
  /// - [worldParameters]: JSON-like values exposed as `World.parameters`.
  /// - [plugins]: `'message:<path>'` (NDJSON), `'summary'` (printed when the
  ///   suite ends) or [Plugin] instances.
  /// - [suiteName]: the name of this suite's report part. Default: the test
  ///   file name.
  /// - [profile]: `cucumber.yaml` profile(s) to apply, comma separated.
  /// - [mapTags]: whether Gherkin tags become `package:test` tags. Default:
  ///   `true`.
  /// - [scenarioTimeout]: the `package:test` timeout of one attempt of a
  ///   scenario. The test's timeout is this times `retry + 1`.
  CucumberOptions({
    List<Glue>? glue,
    this.world,
    List<String>? features,
    this.tags,
    List<String>? names,
    this.retry,
    this.order,
    this.dryRun,
    Map<String, Object?>? worldParameters,
    List<Object>? plugins,
    this.suiteName,
    this.profile,
    this.mapTags,
    this.scenarioTimeout,
  }) : glue = _list(glue),
       features = _list(features),
       names = _list(names),
       worldParameters = worldParameters == null
           ? null
           : Map.unmodifiable(worldParameters),
       plugins = _list(plugins);

  static List<T>? _list<T>(List<T>? list) =>
      list == null ? null : List.unmodifiable(list);

  /// The glue: steps, hooks and types, in definition order.
  final List<Glue>? glue;

  /// Creates the World for each scenario attempt.
  final Object Function()? world;

  /// Feature locations: directories, globs, files and `path:line[:line]`.
  final List<String>? features;

  /// A Cucumber tag expression selecting scenarios.
  final String? tags;

  /// Regular expressions, one of which must match a scenario's name.
  final List<String>? names;

  /// Extra attempts for FAILED scenarios.
  final int? retry;

  /// `defined`, `reverse`, `random` or `random:<seed>`.
  final String? order;

  /// Whether to report the steps without running any user code.
  final bool? dryRun;

  /// JSON-like values exposed as `World.parameters`.
  final Map<String, Object?>? worldParameters;

  /// Plugin specifications (`'message:<path>'`, `'summary'`) and [Plugin]
  /// instances.
  final List<Object>? plugins;

  /// The name of this suite's report part.
  final String? suiteName;

  /// `cucumber.yaml` profile(s) to apply, comma separated.
  final String? profile;

  /// Whether Gherkin tags become `package:test` tags.
  final bool? mapTags;

  /// The `package:test` timeout of one attempt of a scenario.
  final Timeout? scenarioTimeout;

  /// Returns these options refined by [other] (design §4.9):
  ///
  /// - scalars and lists set in [other] replace the ones set here;
  /// - [tags] are combined with `and`, so [other] can only narrow the
  ///   selection;
  /// - [worldParameters] are merged key by key (recursively for nested maps).
  CucumberOptions merge(CucumberOptions other) => CucumberOptions(
    glue: other.glue ?? glue,
    world: other.world ?? world,
    features: other.features ?? features,
    tags: andTags(tags, other.tags),
    names: other.names ?? names,
    retry: other.retry ?? retry,
    order: other.order ?? order,
    dryRun: other.dryRun ?? dryRun,
    worldParameters: _mergeParameters(worldParameters, other.worldParameters),
    plugins: other.plugins ?? plugins,
    suiteName: other.suiteName ?? suiteName,
    profile: other.profile ?? profile,
    mapTags: other.mapTags ?? mapTags,
    scenarioTimeout: other.scenarioTimeout ?? scenarioTimeout,
  );

  @override
  String toString() {
    final fields = {
      if (glue != null) 'glue': '${glue!.length} values',
      if (world != null) 'world': world.runtimeType,
      'features': ?features,
      'tags': ?tags,
      'names': ?names,
      'retry': ?retry,
      'order': ?order,
      'dryRun': ?dryRun,
      'worldParameters': ?worldParameters,
      'plugins': ?plugins,
      'suiteName': ?suiteName,
      'profile': ?profile,
      'mapTags': ?mapTags,
      'scenarioTimeout': ?scenarioTimeout,
    };
    return 'CucumberOptions(${[for (final e in fields.entries) '${e.key}: ${e.value}'].join(', ')})';
  }
}

/// Combines two tag expressions with `and`. Blank expressions are ignored.
String? andTags(String? a, String? b) {
  final left = a?.trim() ?? '';
  final right = b?.trim() ?? '';
  if (left.isEmpty) return right.isEmpty ? null : right;
  if (right.isEmpty) return left;
  return '($left) and ($right)';
}

Map<String, Object?>? _mergeParameters(
  Map<String, Object?>? base,
  Map<String, Object?>? other,
) {
  if (base == null) return other;
  if (other == null) return base;
  final result = <String, Object?>{...base};
  for (final MapEntry(:key, :value) in other.entries) {
    final existing = result[key];
    result[key] =
        existing is Map<String, Object?> && value is Map<String, Object?>
        ? _mergeParameters(existing, value)
        : value;
  }
  return result;
}
