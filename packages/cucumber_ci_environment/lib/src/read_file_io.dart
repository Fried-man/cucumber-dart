import 'dart:io';

/// Reads the UTF-8 text file at [path], or returns `null` when it cannot be
/// read.
String? readTextFile(String path) {
  try {
    return File(path).readAsStringSync();
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}
