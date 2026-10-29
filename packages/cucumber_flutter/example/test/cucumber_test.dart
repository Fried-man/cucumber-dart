// Runs the features as widget tests: flutter test
import 'package:cucumber_flutter/cucumber_flutter.dart';

import 'steps/todo_steps.dart';

void main() => cucumberWidgets(
  features: ['features/'],
  world: TodoWorld.new,
  glue: todoGlue,
);
