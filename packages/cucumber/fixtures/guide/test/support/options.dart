import 'package:cucumber/cucumber.dart';

import '../steps/shop_steps.dart';

/// The options that every entry file of the project shares.
final shopOptions = CucumberOptions(world: ShopWorld.new, glue: shopGlue);
