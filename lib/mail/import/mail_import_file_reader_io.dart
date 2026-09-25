import 'dart:io';
import 'dart:typed_data';

/// Desktop/mobile implementation: reads the file from the local filesystem.
Future<Uint8List> readImportFile(String path) => File(path).readAsBytes();

/// Synchronous read for background-isolate parsing, where the async event
/// loop is unavailable and the file bytes must never touch the main isolate.
Uint8List readImportFileSync(String path) => File(path).readAsBytesSync();
