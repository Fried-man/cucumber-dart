// Takes the merge lock given as the only argument, from another process.
// Used by test/merge_lock_test.dart.
import 'package:cucumber/src/merge_lock.dart';

Future<void> main(List<String> arguments) async {
  print('waiting');
  final lock = await MergeLock.acquire(arguments.single);
  print('acquired');
  await lock.release();
}
