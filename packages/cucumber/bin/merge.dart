// `dart run cucumber:merge`: merges Cucumber report parts, such as the parts
// collected from CI shards, into one report (docs/design.md §8.4). Run it with
// --help for usage. The command is implemented in lib/src/merge_command.dart.
import 'dart:io';

import 'package:cucumber/src/merge_command.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runMergeCommand(arguments);
}
