// The generated benchmark suite under `dart test`. benchmark/benchmark.dart
// generates the features and runs this file with CUCUMBER_FEATURES (and, for
// the reports, CUCUMBER_PLUGIN); see docs/performance.md. It is not in test/,
// so a plain `dart test` does not run it.
import 'package:cucumber/cucumber.dart';

import 'src/glue.dart';

void main() => cucumber(
  features: ['build/benchmark/features/'],
  world: WarehouseWorld.new,
  glue: warehouseGlue(),
);
