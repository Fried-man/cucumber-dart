import 'package:cucumber/cucumber.dart';

import 'steps/shop_steps.dart';
import 'support/options.dart';
import 'support/scenario_counter.dart';

void main() => CucumberSuite<ShopWorld>(
  shopOptions.merge(
    CucumberOptions(
      features: ['features/cart.feature'],
      plugins: [ScenarioCounter()],
    ),
  ),
).declare();
