import 'package:cucumber_flutter/cucumber_flutter.dart';

import 'steps.dart';

void main() => cucumberWidgets(
  features: ['features/outcomes.feature'],
  glue: glue,
  retry: 1,
);
