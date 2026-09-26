import 'package:solar_network_foundation/solar_network_foundation.dart';

/// Background app-task status (uploads, downloads, etc.).
enum AppTaskStatus {
  pending,
  inProgress,
  paused,
  completed,
  failed,
  cancelled,
  expired,
}

/// Task type identifiers. Extend as new background jobs are added.
abstract final class AppTaskType {
  static const driveUpload = DriveTaskTypes.upload;
  static const driveDownload = DriveTaskTypes.download;
  static const mailImport = 'mail.import';
  static const generic = 'generic';
}

/// In-memory background task shown in the Island-style task overlay.
class AppTask {
  const AppTask({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.type,
    this.progress = 0,
    this.statusMessage,
    this.errorMessage,
    this.metadata,
    this.result,
  });

  final String id;
  final String title;
  final AppTaskStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String type;
  final double progress;
  final String? statusMessage;
  final String? errorMessage;
  final Map<String, dynamic>? metadata;
  final Map<String, dynamic>? result;

  bool get isActive =>
      status == AppTaskStatus.pending ||
      status == AppTaskStatus.inProgress ||
      status == AppTaskStatus.paused;

  bool get isFinished =>
      status == AppTaskStatus.completed ||
      status == AppTaskStatus.failed ||
      status == AppTaskStatus.cancelled ||
      status == AppTaskStatus.expired;

  AppTask copyWith({
    String? title,
    AppTaskStatus? status,
    DateTime? updatedAt,
    double? progress,
    String? statusMessage,
    String? errorMessage,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? result,
    bool clearStatusMessage = false,
    bool clearErrorMessage = false,
  }) {
    return AppTask(
      id: id,
      title: title ?? this.title,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      type: type,
      progress: progress ?? this.progress,
      statusMessage: clearStatusMessage
          ? null
          : (statusMessage ?? this.statusMessage),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      metadata: metadata ?? this.metadata,
      result: result ?? this.result,
    );
  }
}
