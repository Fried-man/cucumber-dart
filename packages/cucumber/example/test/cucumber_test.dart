// Runs the features in features/ with `dart test`.
//
// cucumber.yaml adds the NDJSON and HTML reports and the summary, and leaves
// out @wip scenarios. Try:
//
//   dart test                              # every other scenario, one test each
//   dart test --tags smoke                 # scenarios tagged @smoke
//   CUCUMBER_FILTER_TAGS=@smoke dart test  # the same, selected by Cucumber
//   CUCUMBER_PROFILE=wip dart test         # only @wip (undefined, so it fails)
//
// CUCUMBER_FILTER_TAGS narrows the active profiles' selection, so it cannot
// bring back the @wip scenarios that the default profile leaves out.
import 'package:cucumber/cucumber.dart';

import 'steps/belly_steps.dart';

void main() => cucumber(
  features: ['features/'],
  world: BellyWorld.new,
  glue: bellyGlue,
  worldParameters: {'greeting': 'Hi'},
);
