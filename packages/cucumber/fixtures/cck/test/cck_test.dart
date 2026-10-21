// Declares the compatibility kit samples named in CCK_SAMPLES (comma
// separated), one group per sample, through the dart test host.
//
// packages/cucumber/test/compatibility_host_test.dart copies the samples to
// samples/ and compares the NDJSON written to build/cck/ with the expected
// messages.
import 'dart:io';

import 'package:cucumber/cucumber.dart';
import 'package:test/test.dart';

import '../../../../cucumber_core/test/compatibility/samples.dart'
    show CckWorld, sampleGlue;

void main() {
  final names = [
    for (final name in (Platform.environment['CCK_SAMPLES'] ?? '').split(','))
      if (name.trim().isNotEmpty) name.trim(),
  ];
  for (final name in names) {
    group(name, () {
      final dir = Directory('samples/$name');
      var retry = 0;
      var order = 'defined';
      final arguments = File('${dir.path}/$name.arguments.txt');
      if (arguments.existsSync()) {
        final args = arguments.readAsStringSync().trim().split(RegExp(r'\s+'));
        for (var i = 0; i < args.length; i++) {
          switch (args[i]) {
            case '--retry':
              retry = int.parse(args[++i]);
            case '--order':
              order = args[++i];
            default:
              throw UnsupportedError('Unknown sample argument ${args[i]}');
          }
        }
      }
      cucumber(
        features: ['samples/$name/'],
        glue: sampleGlue[name]!(dir),
        world: CckWorld.new,
        retry: retry,
        order: order,
        plugins: ['message:build/cck/$name.ndjson'],
        // Names the sample's report part (design §8.4).
        suiteName: name,
        mapTags: false,
      );
    });
  }
}
