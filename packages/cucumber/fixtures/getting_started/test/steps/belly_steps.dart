import 'package:cucumber/cucumber.dart';
import 'package:cucumber_getting_started/belly.dart';
import 'package:test/test.dart';

/// Holds the state of one scenario. A new one is created for every scenario.
class BellyWorld extends World {
  final belly = Belly();
}

final bellyGlue = <Glue>[
  Given('I have {int} cukes in my belly', (BellyWorld w, int cukes) {
    w.belly.eat(cukes);
  }),
  When('I wait {int} hour(s)', (BellyWorld w, int hours) {
    w.belly.wait(hours);
  }),
  Then('my belly should growl', (BellyWorld w) {
    expect(w.belly.isGrowling, isTrue);
  }),
  Then('my belly should not growl', (BellyWorld w) {
    expect(w.belly.isGrowling, isFalse);
  }),
];
