import 'package:cucumber/cucumber.dart';
import 'package:cucumber/hosting.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class HostWorld extends World {
  HostWorld() {
    created++;
  }

  static int created = 0;
}

void main() {
  final declared = <(String, TestLocation, List<String>?, Timeout?)>[];
  final steps = <String>[];
  var checks = 0;

  group('declareCucumberSuite', () {
    declareCucumberSuite<HostWorld>(
      CucumberOptions(
        features: ['test/support/hosting.feature'],
        glue: [
          Given('a step', (HostWorld w) => steps.add('a step')),
          When('another step', (HostWorld w) => steps.add('another step')),
        ],
        retry: 1,
        suiteName: 'hosting_test',
      ),
      defaultWorld: HostWorld.new,
      declareScenario: (name, body, {required location, tags, timeout}) {
        declared.add((name, location, tags, timeout));
        test(name, body, location: location, tags: tags, timeout: timeout);
      },
      afterUserCode: () => checks++,
    );
  });

  test('declares each scenario with the declarer and the default World', () {
    expect(declared, hasLength(1));
    final (name, location, tags, timeout) = declared.single;
    expect(name, 'declared by the host');
    expect(
      p.fromUri(location.uri),
      p.join(p.current, 'test', 'support', 'hosting.feature'),
    );
    expect(location.line, 3);
    expect(tags, isNull);
    // retry: 1 doubles the timeout, as for package:test tests.
    expect(timeout, const Timeout.factor(2));
    expect(steps, ['a step', 'another step']);
    expect(HostWorld.created, 1);
    expect(checks, 2, reason: 'afterUserCode runs after each step');
  });
}
