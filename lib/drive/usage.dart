import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:solwatt/drive/screens/file_list.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/workspaces/workspace_management.dart';

/// Used/available bytes for the active drive, plus the raw usage maps its
/// overview sheet reads. The contextual sidebar owns the figures, so the meter
/// and the sheet come from one snapshot.
class DriveStorageSnapshot {
  const DriveStorageSnapshot({
    required this.usedBytes,
    required this.totalBytes,
    this.usage,
    this.quota,
  });

  final int usedBytes;
  final int totalBytes;

  /// Usage map in the drive overview's contract (`used_bytes`, `limit_bytes`,
  /// pool/service breakdowns). Null when a bare [DriveStorageSnapshot] override
  /// supplied the figures.
  final Map<String, dynamic>? usage;

  /// Purchased-quota map; the personal drive has one, workspace drives do not.
  final Map<String, dynamic>? quota;

  double get ratio =>
      totalBytes > 0 ? (usedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
}

final driveStorageUsageProvider =
    FutureProvider.autoDispose<DriveStorageSnapshot?>((ref) async {
      final workspace = await ref.watch(selectedWorkspaceProvider.future);
      if (workspace != null && !workspace.isIndividual) {
        // The workspace console reads the same endpoint, so the two surfaces
        // share one request and one invalidation.
        final quota = await ref.watch(
          workspaceStorageQuotaProvider(workspace.slug).future,
        );
        if (quota == null) return null;
        return DriveStorageSnapshot(
          usedBytes: quota.usedBytes,
          totalBytes: quota.totalBytes,
          usage: quota.toUsageMap(),
        );
      }
      final usage = await ref.watch(billingUsageProvider.future);
      if (usage == null) return null;
      final quota = await ref.watch(billingQuotaProvider.future);
      final used =
          (usage['used_bytes'] as num?)?.toInt() ??
          ((usage['used_quota'] as num? ?? 0) * 1024 * 1024).round();
      final total =
          (usage['limit_bytes'] as num?)?.toInt() ??
          (usage['total_bytes'] as num?)?.toInt() ??
          ((usage['total_quota'] as num? ?? 0) * 1024 * 1024).round();
      return DriveStorageSnapshot(
        usedBytes: used,
        totalBytes: total,
        usage: usage,
        quota: quota,
      );
    });
