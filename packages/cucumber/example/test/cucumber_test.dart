// Runs the features in features/ with `dart test`.
//
// cucumber.yaml adds the NDJSON report and leaves out @wip scenarios. Try:
//
//   dart test                         # every scenario, one test each
//   dart test --tags smoke            # scenarios tagged @smoke
//   CUCUMBER_FILTER_TAGS=@wip dart test
import 'package:cucumber/cucumber.dart';

import 'steps/belly_steps.dart';

void main() => cucumber(
  features: ['features/'],
  world: BellyWorld.new,
  glue: bellyGlue,
  worldParameters: {'greeting': 'Hi'},
);
