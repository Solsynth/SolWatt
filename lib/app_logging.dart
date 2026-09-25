import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:solwatt/app_log_sink_stub.dart'
    if (dart.library.io) 'package:solwatt/app_log_sink_io.dart'
    as file_sink;

/// Configures the same root-record pattern used by Island: structured records
/// are visible in the platform developer console and retained on native apps.
Future<void> initializeAppLogging() async {
  Logger.root.level = Level.ALL;
  await file_sink.initialize();

  Logger.root.onRecord.listen((record) {
    developer.log(
      record.message,
      time: record.time,
      level: record.level.value,
      name: record.loggerName,
      error: record.error,
      stackTrace: record.stackTrace,
    );
    file_sink.write(record);
  });

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Logger.root.severe(
      'Unhandled Flutter framework error',
      details.exception,
      details.stack,
    );
  };
}
