// Declares every feature in features/ (cucumber.yaml's default profile leaves
// out @wip). Checked by packages/cucumber/test/end_to_end_test.dart.
import 'package:cucumber/cucumber.dart';

import 'support/shop_glue.dart';

void main() => cucumber(
  world: ShopWorld.new,
  glue: shopGlue,
  retry: 1,
  worldParameters: {'source': 'code', 'fromCode': true},
  plugins: [
    'message:build/cucumber/messages.ndjson',
    'html:build/cucumber/report.html',
    'summary',
    CountingPlugin('build/cucumber/counts.json'),
  ],
);
