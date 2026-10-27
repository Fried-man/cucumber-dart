import 'package:cucumber/cucumber.dart';

import 'steps/belly_steps.dart';

void main() =>
    cucumber(features: ['features/'], world: BellyWorld.new, glue: bellyGlue);
