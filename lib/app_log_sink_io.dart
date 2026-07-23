import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

const _maxLogFileSize = 5 * 1024 * 1024;
const _maxLogFiles = 3;

IOSink? _sink;
int _size = 0;

Future<void> initialize() async {
  final support = await getApplicationSupportDirectory();
  final directory = Directory('${support.path}/logs');
  await directory.create(recursive: true);

  final files =
      (await directory.list().toList())
          .whereType<File>()
          .where((file) => file.path.endsWith('.log'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
  for (final file in files.skip(_maxLogFiles - 1)) {
    await file.delete();
  }

  final file = File(
    '${directory.path}/${DateTime.now().millisecondsSinceEpoch}.log',
  );
  _sink = file.openWrite(mode: FileMode.append);
}

void write(LogRecord record) {
  final line =
      '[${record.time.toIso8601String()}] [${record.level.name}] '
      '[${record.loggerName}] ${record.message}'
      '${record.error == null ? '' : ' | error: ${record.error}'}';
  _sink?.writeln(line);
  if (record.stackTrace != null) _sink?.writeln(record.stackTrace);
  _size += line.length + 1;
  if (_size >= _maxLogFileSize) {
    _sink?.flush().then((_) => _sink?.close());
    _sink = null;
    _size = 0;
    initialize();
  }
}
