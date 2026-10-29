import 'package:cucumber_flutter/cucumber_flutter.dart';

import 'steps.dart';

void main() =>
    cucumberWidgets(features: ['features/second.feature'], glue: glue);
