import 'package:cucumber/cucumber.dart';
import 'package:cucumber_messages/cucumber_messages.dart' show Envelope;

/// Prints how many scenarios finished when the suite ends.
final class ScenarioCounter implements Plugin {
  int _finished = 0;

  @override
  void onMessage(Envelope envelope) {
    if (envelope.testCaseFinished case final finished?
        when !finished.willBeRetried) {
      _finished++;
    }
  }

  @override
  Future<void> close() async => print('$_finished scenarios finished');
}
