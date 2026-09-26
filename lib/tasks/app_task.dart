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
  static const driveUpload = 'drive.upload';
  static const driveDownload = 'drive.download';
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

// --- Typed metadata classes for drive domain data (ported from Solian) ---

class DriveUploadStage {
  static const preparing = 'preparing';
  static const hashing = 'hashing';
  static const preparingMedia = 'preparing_media';
  static const creatingUpload = 'creating_upload';
  static const uploadingSource = 'uploading_source';
  static const uploadingThumbnail = 'uploading_thumbnail';
  static const uploadingCompression = 'uploading_compression';
  static const finalizing = 'finalizing';
  static const fallingBack = 'falling_back';
  static const completed = 'completed';

  static String label(String stage) => switch (stage) {
    hashing => 'Hashing file',
    preparingMedia => 'Preparing media',
    creatingUpload => 'Creating upload',
    uploadingSource => 'Uploading source',
    uploadingThumbnail => 'Uploading thumbnail',
    uploadingCompression => 'Uploading compression',
    finalizing => 'Finalizing upload',
    fallingBack => 'Switching to standard upload',
    completed => 'Upload completed',
    _ => 'Preparing upload',
  };
}

class DriveUploadTaskMeta {
  final String? serverTaskId;
  final int fileSize;
  final int totalChunks;
  final int uploadedChunks;
  final double? transmissionProgress;
  final String? stage;
  final double stageProgress;
  final double sourceProgress;
  final double thumbnailProgress;
  final double compressionProgress;
  final String? poolId;
  final String? encryptPassword;
  final String? expiredAt;

  const DriveUploadTaskMeta({
    this.serverTaskId,
    required this.fileSize,
    required this.totalChunks,
    this.uploadedChunks = 0,
    this.transmissionProgress,
    this.stage,
    this.stageProgress = 0,
    this.sourceProgress = 0,
    this.thumbnailProgress = 0,
    this.compressionProgress = 0,
    this.poolId,
    this.encryptPassword,
    this.expiredAt,
  });

  Map<String, dynamic> toMap() => {
    if (serverTaskId != null) 'serverTaskId': serverTaskId,
    'fileSize': fileSize,
    'totalChunks': totalChunks,
    'uploadedChunks': uploadedChunks,
    if (transmissionProgress != null)
      'transmissionProgress': transmissionProgress,
    if (stage != null) 'stage': stage,
    'stageProgress': stageProgress,
    'sourceProgress': sourceProgress,
    'thumbnailProgress': thumbnailProgress,
    'compressionProgress': compressionProgress,
    if (poolId != null) 'poolId': poolId,
    if (encryptPassword != null) 'encryptPassword': encryptPassword,
    if (expiredAt != null) 'expiredAt': expiredAt,
  };

  factory DriveUploadTaskMeta.fromMap(Map<String, dynamic> map) =>
      DriveUploadTaskMeta(
        serverTaskId: map['serverTaskId'] as String?,
        fileSize: (map['fileSize'] as num).toInt(),
        totalChunks: (map['totalChunks'] as num).toInt(),
        uploadedChunks: (map['uploadedChunks'] as num?)?.toInt() ?? 0,
        transmissionProgress: (map['transmissionProgress'] as num?)?.toDouble(),
        stage: map['stage'] as String?,
        stageProgress: (map['stageProgress'] as num?)?.toDouble() ?? 0,
        sourceProgress: (map['sourceProgress'] as num?)?.toDouble() ?? 0,
        thumbnailProgress: (map['thumbnailProgress'] as num?)?.toDouble() ?? 0,
        compressionProgress:
            (map['compressionProgress'] as num?)?.toDouble() ?? 0,
        poolId: map['poolId'] as String?,
        encryptPassword: map['encryptPassword'] as String?,
        expiredAt: map['expiredAt'] as String?,
      );
}

class DriveDownloadTaskMeta {
  final String fileId;
  final int totalBytes;
  final int downloadedBytes;

  const DriveDownloadTaskMeta({
    required this.fileId,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
  });

  Map<String, dynamic> toMap() => {
    'fileId': fileId,
    'totalBytes': totalBytes,
    'downloadedBytes': downloadedBytes,
  };

  factory DriveDownloadTaskMeta.fromMap(Map<String, dynamic> map) =>
      DriveDownloadTaskMeta(
        fileId: map['fileId'] as String,
        totalBytes: map['totalBytes'] as int? ?? 0,
        downloadedBytes: map['downloadedBytes'] as int? ?? 0,
      );
}
