import 'dart:typed_data';

/// Web implementation: arbitrary file paths do not exist on the web. Callers
/// should read the picked file bytes themselves and pass them to
/// `MailImportService.parseBytes`.
Future<Uint8List> readImportFile(String path) {
  throw UnsupportedError(
    'Reading import files by path is unavailable on this platform. '
    'Pass the picked file bytes to MailImportService.parseBytes instead.',
  );
}

/// Web has no filesystem; callers always pass picked bytes instead.
Uint8List readImportFileSync(String path) {
  throw UnsupportedError(
    'Reading import files by path is unavailable on this platform.',
  );
}
