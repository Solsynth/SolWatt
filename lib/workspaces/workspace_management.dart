import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:solwatt/core/network.dart';

/// SolWatt's [Workspace] is the drive's workspace summary: it already carries
/// the `id` / `slug` / `name` / `type` / `plan` / `isBundled` fields the
/// ported drive list reads, so the summary is a plain alias.
typedef WorkspaceSummary = Workspace;

/// Converts Valve service identifiers into user-facing localized names.
///
/// Looks up `service.*` keys (added to the i18n catalog later); falls back to
/// a plain English label when the key is not yet translated, and to the raw
/// service identifier for unknown services.
String localizedWorkspaceServiceName(String serviceName) {
  final normalized = serviceName.trim().toLowerCase();
  final key = switch (normalized) {
    'drive' => 'workspaceServiceDrive',
    'mail' || 'postal' => 'workspaceServicePostal',
    'distribution' => 'workspaceServiceDistribution',
    'flywheel' => 'workspaceServiceFlywheel',
    _ => null,
  };
  if (key == null) return serviceName;
  final label = key.tr();
  return label == key ? _fallbackServiceName(normalized) : label;
}

String _fallbackServiceName(String normalized) => switch (normalized) {
  'drive' => 'Drive',
  'mail' || 'postal' => 'Mail',
  'board' => 'Board',
  'gate' => 'Gate',
  'flywheel' => 'Flywheel',
  'distribution' => 'Distribution',
  _ => normalized,
};

/// Storage usage retained for a single workspace service, mirroring the shape
/// of the per-service entries in Solian's Valve storage snapshot.
class WorkspaceStorageServiceUsage {
  final String name;
  final int usedBytes;

  const WorkspaceStorageServiceUsage({
    required this.name,
    required this.usedBytes,
  });

  /// Localized label for [name], while [name] remains the server identifier.
  String get displayName => localizedWorkspaceServiceName(name);

  Map<String, dynamic> toJson() => {'name': name, 'used_bytes': usedBytes};
}

/// Effective workspace storage quota for one workspace.
///
/// Derived from DysonFS billing ([WorkspaceDriveUsage]) instead of Solian's
/// Valve snapshot endpoint. [toUsageMap] adapts it to the drive usage view's
/// data contract (`total_quota` in MB, `used_quota` in MB, byte figures, and
/// a per-service breakdown).
class WorkspaceStorageQuota {
  final String slug;
  final int usedBytes;
  final int totalBytes;
  final int remainingBytes;
  final int totalFileCount;
  final DateTime? calculatedAt;
  final List<WorkspaceStorageServiceUsage> services;

  const WorkspaceStorageQuota({
    required this.slug,
    required this.usedBytes,
    required this.totalBytes,
    required this.remainingBytes,
    required this.totalFileCount,
    this.calculatedAt,
    this.services = const [],
  });

  factory WorkspaceStorageQuota.fromUsage(
    String slug,
    WorkspaceDriveUsage usage,
  ) {
    return WorkspaceStorageQuota(
      slug: slug,
      usedBytes: usage.usedBytes,
      totalBytes: usage.totalBytes,
      remainingBytes: usage.remainingBytes,
      totalFileCount: usage.totalFileCount,
      // DysonFS reports the aggregate workspace storage; present it as the
      // single "drive" service so the usage overview's service legend still
      // has one meaningful entry.
      services: [
        WorkspaceStorageServiceUsage(name: 'drive', usedBytes: usage.usedBytes),
      ],
    );
  }

  /// Adapts the workspace snapshot to the drive usage view's data contract.
  Map<String, dynamic> toUsageMap() => {
    'total_usage_bytes': usedBytes,
    'total_file_count': totalFileCount,
    'total_quota': totalBytes ~/ (1024 * 1024),
    'used_quota': usedBytes / (1024 * 1024),
    'used_bytes': usedBytes,
    'limit_bytes': totalBytes,
    'total_bytes': totalBytes,
    'remaining_bytes': remainingBytes,
    'calculated_at': calculatedAt?.toIso8601String(),
    'service_usages': [for (final service in services) service.toJson()],
  };
}

final workspaceListProvider =
    FutureProvider.autoDispose<List<WorkspaceSummary>>((ref) async {
      return ref.watch(workspacesProvider.future);
    });

final workspaceStorageQuotaProvider = FutureProvider.autoDispose
    .family<WorkspaceStorageQuota?, String?>((ref, slug) async {
      if (slug == null || slug.isEmpty) return null;
      final workspaces = await ref.watch(workspacesProvider.future);
      Workspace? workspace;
      for (final candidate in workspaces) {
        if (candidate.slug == slug) {
          workspace = candidate;
          break;
        }
      }
      if (workspace == null) return null;
      final usage = await ref
          .read(wattEngineClientProvider)
          .getWorkspaceDriveUsage(workspace.id);
      return WorkspaceStorageQuota.fromUsage(slug, usage);
    });
