import 'dart:io';
import 'dart:typed_data';

/// Desktop/mobile implementation: reads the file from the local filesystem.
Future<Uint8List> readImportFile(String path) => File(path).readAsBytes();
