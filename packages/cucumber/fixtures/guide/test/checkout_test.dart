import 'package:cucumber/cucumber.dart';

import 'steps/shop_steps.dart';
import 'support/options.dart';

void main() => CucumberSuite<ShopWorld>(
  shopOptions.merge(
    CucumberOptions(features: ['features/checkout.feature'], retry: 1),
  ),
).declare();
