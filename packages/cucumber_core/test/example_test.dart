import 'package:cucumber_core/engine.dart';
import 'package:test/test.dart';

import '../example/cucumber_core_example.dart';

void main() {
  test('the example runs its feature through the SerialHost', () async {
    final collector = CollectingPlugin();
    final result = await runBellyFeature(plugins: [collector]);

    expect(
      [for (final testCase in result.testCases) testCase.status],
      [Status.passed, Status.undefined],
    );
    expect(
      result.testCases.last.snippets.single,
      contains('my belly should sing'),
    );
    expect(result.success, isFalse);
    expect(collector.isClosed, isTrue);
    expect(collector.envelopes.last.testRunFinished?.success, isFalse);
  });
}
