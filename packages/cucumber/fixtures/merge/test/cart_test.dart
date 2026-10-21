// Suite `cart_test` (named after this file). Checked by
// packages/cucumber/test/end_to_end_test.dart.
import 'package:cucumber/cucumber.dart';

import 'support/glue.dart';

void main() => cucumber(
  features: ['features/cart.feature', 'features/shared.feature:4'],
  glue: glue,
);
