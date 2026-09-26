import 'package:solar_network_foundation/solar_network_foundation.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/core/database.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/route.dart';
import 'package:solwatt/tasks/app_task.dart';
import 'package:solwatt/tasks/tasks_notifier.dart';
import 'package:solwatt/ui/alert.dart';

/// Binds the shared drive service (`solar_network_foundation`) to SolWatt's
/// client, settings, secret store, task list, navigator, and alert helpers.
///
/// The drive package never reaches into app state directly; everything it
/// needs from the host flows through these overrides.
///
/// The return type is inferred because Riverpod keeps `Override` out of its
/// public API surface, so it cannot be named here.
// ignore: strict_top_level_inference
driveHostOverrides() {
  return [
    driveClientProvider.overrideWith(
      (ref) => ref.watch(solarNetworkClientProvider),
    ),
    driveServerUrlProvider.overrideWith((ref) => ref.watch(serverUrlProvider)),
    driveSettingsProvider.overrideWith((ref) {
      final settings = ref.watch(appSettingsProvider);
      return DriveSettings(
        dataSavingMode: settings.dataSavingMode,
        imageCompressionEnabled: settings.imageCompressionEnabled,
        imageCompressionQuality: settings.imageCompressionQuality,
        defaultPoolId: settings.defaultPoolId,
      );
    }),
    driveSecretStoreProvider.overrideWith(
      (ref) => AppDatabaseSecretStore(ref.watch(databaseProvider)),
    ),
    driveTaskSinkProvider.overrideWith(
      (ref) => AppTasksSink(ref.read(appTasksProvider.notifier)),
    ),
    driveNavigatorKeyProvider.overrideWith(
      (ref) => ref.watch(routerProvider).navigatorKey,
    ),
    driveErrorReporterProvider.overrideWithValue(showErrorAlert),
  ];
}

/// Backs the drive's E2EE file-key storage with SolWatt's secure storage.
class AppDatabaseSecretStore implements DriveSecretStore {
  AppDatabaseSecretStore(this._database);

  final AppDatabase _database;

  @override
  Future<String?> getSecret(String key) => _database.getSecret(key);

  @override
  Future<void> setSecret(String key, String value) =>
      _database.setSecret(key, value);
}

/// Feeds drive uploads/downloads into SolWatt's task overlay.
class AppTasksSink implements DriveTaskSink {
  AppTasksSink(this._tasks);

  final AppTasksNotifier _tasks;

  @override
  String addTask({
    required String title,
    required String type,
    required DriveTaskStatus status,
    Map<String, dynamic>? metadata,
  }) {
    return _tasks.addTask(
      title: title,
      type: type,
      status: _toAppStatus(status),
      metadata: metadata,
    );
  }

  @override
  void updateTask(
    String id, {
    DriveTaskStatus? status,
    double? progress,
    String? statusMessage,
    String? errorMessage,
    Map<String, dynamic>? result,
    Map<String, dynamic>? metadata,
  }) {
    _tasks.updateTask(
      id,
      status: status == null ? null : _toAppStatus(status),
      progress: progress,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
      result: result,
      metadata: metadata,
    );
  }

  @override
  DriveTaskSnapshot? getTask(String id) {
    final task = _tasks.getTask(id);
    if (task == null) return null;
    return DriveTaskSnapshot(progress: task.progress, metadata: task.metadata);
  }

  static AppTaskStatus _toAppStatus(DriveTaskStatus status) => switch (status) {
    DriveTaskStatus.pending => AppTaskStatus.pending,
    DriveTaskStatus.inProgress => AppTaskStatus.inProgress,
    DriveTaskStatus.paused => AppTaskStatus.paused,
    DriveTaskStatus.completed => AppTaskStatus.completed,
    DriveTaskStatus.failed => AppTaskStatus.failed,
    DriveTaskStatus.cancelled => AppTaskStatus.cancelled,
    DriveTaskStatus.expired => AppTaskStatus.expired,
  };
}
