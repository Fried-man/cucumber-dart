// A suite whose BeforeAll hook fails, selecting one scenario by line.
// Checked by packages/cucumber/test/end_to_end_test.dart.
import 'package:cucumber/cucumber.dart';

void main() => cucumber(
  features: ['features/more/other.feature:3'],
  glue: [
    BeforeAll(() => throw StateError('database is down'), name: 'database'),
    Given('a step passes', () {}),
  ],
  plugins: ['message:build/cucumber/before_all.ndjson'],
);
