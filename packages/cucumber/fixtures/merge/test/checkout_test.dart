// Suite `checkout` (named by suiteName). Checked by
// packages/cucumber/test/end_to_end_test.dart.
import 'package:cucumber/cucumber.dart';

import 'support/glue.dart';

void main() => cucumber(
  features: ['features/checkout.feature'],
  glue: glue,
  suiteName: 'checkout',
);
