/// Runner-agnostic Cucumber engine for Dart: the glue API.
///
/// Define steps, hooks and types as glue values, and share scenario state
/// through a World:
///
/// ```dart
/// class BellyWorld extends World {
///   final belly = Belly();
/// }
///
/// final bellyGlue = <Glue>[
///   Given('I have {int} cukes in my belly',
///       (BellyWorld w, int cukes) => w.belly.eat(cukes)),
///   When('I wait {int} hour(s)', (BellyWorld w, int hours) => w.belly.wait(hours)),
///   Then('my belly should growl', (BellyWorld w) => check(w.belly.isGrowling)),
///   Before((Scenario s) => log('starting ${s.name}')),
/// ];
/// ```
///
/// This library is pure Dart: no `dart:io`, `dart:mirrors`, Flutter or
/// `package:test`. Most users depend on `package:cucumber`, which re-exports it
/// and runs features with `dart test`. Hosts that run suites themselves use
/// `package:cucumber_core/engine.dart`. See `docs/design.md`.
library;

export 'src/data/data_table.dart' show DataTable;
export 'src/data/doc_string.dart' show DocString;
export 'src/data/table_converter.dart' show ConversionException;
export 'src/data/table_diff.dart' show TableDiffException;
export 'src/exceptions.dart'
    show
        GlueError,
        GlueException,
        PendingException,
        SkippedException,
        pending,
        skip;
export 'src/glue/glue.dart'
    show
        After,
        AfterAll,
        AfterStep,
        Before,
        BeforeAll,
        BeforeStep,
        DataTableType,
        DocStringType,
        Given,
        Glue,
        HookGlue,
        HookKind,
        ParameterType,
        StepGlue,
        Then,
        When;
export 'src/runtime/plugin.dart' show CallbackPlugin, CollectingPlugin, Plugin;
export 'src/source_reference.dart' show SourceReference;
export 'src/status.dart' show Status;
export 'src/world/scenario.dart' show Scenario, Step, TestRun;
export 'src/world/world.dart' show DefaultWorld, World, attach, link, log;
