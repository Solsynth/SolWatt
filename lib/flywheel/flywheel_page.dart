import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/ui/alert.dart';
import 'package:solwatt/ui/page_scaffold.dart';

const _flywheelProducts = <String, _FlywheelProduct>{
  'dev.solsynth.maidkit': _FlywheelProduct(
    name: 'MaidKit',
    iconAsset: 'assets/flywheel/maidkit.png',
  ),
};

class _FlywheelProduct {
  const _FlywheelProduct({required this.name, this.iconAsset});

  final String name;
  final String? iconAsset;
}

/// Display name for a Flywheel app id, falling back to the id itself. The
/// product table is the single source of truth for these names.
String flywheelAppName(String appId) => _flywheelProducts[appId]?.name ?? appId;

/// Retained apps for [workspaceId]. The profile page and the workspace console
/// read the same provider, so a refresh in one place is visible everywhere.
final flywheelAppsProvider = FutureProvider.autoDispose
    .family<List<FlywheelOwnerApp>, String>(
      (ref, workspaceId) =>
          ref.watch(wattEngineClientProvider).listFlywheelApps(workspaceId),
    );

/// Workspace Flywheel usage, embedded in the profile page.
///
/// Flywheel is account activity, not a destination of its own: it lives under
/// Profile next to the workspace list instead of taking a rail slot.
class FlywheelSection extends ConsumerWidget {
  const FlywheelSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(selectedWorkspaceProvider);
    return workspace.when(
      loading: () => const _FlywheelFrame(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => _FlywheelFrame(
        child: _FlywheelNotice(
          icon: Symbols.error,
          title: 'flywheelLoadFailed'.tr(),
          message: wattApiErrorMessage(error),
        ),
      ),
      data: (value) => value == null
          ? _FlywheelFrame(
              child: _FlywheelNotice(
                icon: Symbols.workspaces,
                title: 'selectWorkspaceTitle'.tr(),
              ),
            )
          : _FlywheelWorkspaceSection(workspaceId: value.id),
    );
  }
}

/// Section heading for states that cannot offer a refresh yet.
class _FlywheelFrame extends StatelessWidget {
  const _FlywheelFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [const _FlywheelHeader(), child],
  );
}

class _FlywheelHeader extends StatelessWidget {
  const _FlywheelHeader({this.trailing});

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: 'flywheel'.tr(), trailing: trailing),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'flywheelSubtitle'.tr(),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _FlywheelWorkspaceSection extends ConsumerWidget {
  const _FlywheelWorkspaceSection({required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(flywheelAppsProvider(workspaceId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FlywheelHeader(
          trailing: IconButton(
            tooltip: 'refresh'.tr(),
            onPressed: () => ref.invalidate(flywheelAppsProvider(workspaceId)),
            icon: const Icon(Symbols.refresh, size: 20),
          ),
        ),
        apps.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) {
            final denied =
                error is DioException && error.response?.statusCode == 403;
            return _FlywheelNotice(
              icon: denied ? Symbols.lock : Symbols.error,
              title: denied
                  ? 'flywheelOwnerRequired'.tr()
                  : 'flywheelLoadFailed'.tr(),
              message: denied
                  ? 'flywheelOwnerRequiredDetail'.tr()
                  : wattApiErrorMessage(error),
              action: OutlinedButton.icon(
                onPressed: () =>
                    ref.invalidate(flywheelAppsProvider(workspaceId)),
                icon: const Icon(Symbols.refresh),
                label: Text('retry'.tr()),
              ),
            );
          },
          data: (apps) => apps.isEmpty
              ? _FlywheelNotice(
                  icon: Symbols.sync,
                  title: 'flywheelNoSaves'.tr(),
                  message: 'flywheelNoSavesHint'.tr(),
                )
              : _FlywheelAppList(workspaceId: workspaceId, apps: apps),
        ),
      ],
    );
  }
}

/// Compact empty/error/loading state that fits the profile page's scroll view.
class _FlywheelNotice extends StatelessWidget {
  const _FlywheelNotice({
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 28, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center, style: text.titleSmall),
            if (message case final String message) ...[
              const SizedBox(height: 4),
              Text(
                message,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (action case final Widget action) ...[
              const SizedBox(height: 12),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

class _FlywheelAppList extends ConsumerWidget {
  const _FlywheelAppList({required this.workspaceId, required this.apps});

  final String workspaceId;
  final List<FlywheelOwnerApp> apps;

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    FlywheelOwnerApp app,
  ) async {
    await showFlywheelApp(context, workspaceId: workspaceId, app: app);
    if (context.mounted) {
      ref.invalidate(flywheelAppsProvider(workspaceId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < apps.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            _FlywheelAppTile(
              app: apps[index],
              onOpen: () => _open(context, ref, apps[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _FlywheelAppTile extends StatelessWidget {
  const _FlywheelAppTile({required this.app, required this.onOpen});

  final FlywheelOwnerApp app;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final product = _flywheelProducts[app.appId];
    return ListTile(
      leading: _FlywheelProductIcon(product: product),
      title: Text(product?.name ?? app.appId),
      subtitle: Text(
        'flywheelSavesSummaryRetained'.tr(
          namedArgs: {
            'saves': '${app.blobCount}',
            'revisions': '${app.retainedRevisionCountTotal}',
            'size': _bytes(app.retainedBytes),
          },
        ),
      ),
      trailing: const Icon(Symbols.chevron_right),
      onTap: onOpen,
    );
  }
}

class _FlywheelProductIcon extends StatelessWidget {
  const _FlywheelProductIcon({required this.product});

  final _FlywheelProduct? product;
  static const size = 40.0;

  @override
  Widget build(BuildContext context) {
    final iconAsset = product?.iconAsset;
    if (iconAsset == null) {
      return const Icon(Symbols.sync, size: size);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        iconAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// Opens the per-app Flywheel management sheet (retained saves and audit log).
Future<void> showFlywheelApp(
  BuildContext context, {
  required String workspaceId,
  required FlywheelOwnerApp app,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (_) => FlywheelAppSheet(workspaceId: workspaceId, app: app),
);

class FlywheelAppSheet extends ConsumerStatefulWidget {
  const FlywheelAppSheet({
    super.key,
    required this.workspaceId,
    required this.app,
  });
  final String workspaceId;
  final FlywheelOwnerApp app;

  @override
  ConsumerState<FlywheelAppSheet> createState() => _FlywheelAppSheetState();
}

class _FlywheelAppSheetState extends ConsumerState<FlywheelAppSheet> {
  late Future<(List<FlywheelOwnerBlob>, List<FlywheelAuditEntry>)> _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final client = ref.read(wattEngineClientProvider);
    _data =
        Future.wait<Object>([
          client.listFlywheelBlobs(widget.workspaceId, widget.app.appId),
          client.listFlywheelAudit(widget.workspaceId, widget.app.appId),
        ]).then(
          (value) => (
            value[0] as List<FlywheelOwnerBlob>,
            value[1] as List<FlywheelAuditEntry>,
          ),
        );
  }

  Future<void> _delete(FlywheelOwnerBlob blob) async {
    final confirmed = await showConfirmAlert(
      'flywheelDeleteSaveDetail'.tr(),
      'flywheelDeleteSaveTitle'.tr(),
      icon: Symbols.delete,
      isDanger: true,
      confirmLabel: 'delete'.tr(),
    );
    if (!confirmed || !mounted) {
      return;
    }
    try {
      await ref
          .read(wattEngineClientProvider)
          .deleteFlywheelBlob(
            widget.workspaceId,
            widget.app.appId,
            blob.blobId,
          );
      if (!mounted) {
        return;
      }
      setState(_reload);
      _notify('flywheelSaveDeleted'.tr());
    } catch (error) {
      if (mounted) {
        _notify(wattApiErrorMessage(error));
      }
    }
  }

  void _notify(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final product = _flywheelProducts[widget.app.appId];
    return SheetScaffold(
      titleText: product?.name ?? widget.app.appId,
      actions: [
        IconButton(
          onPressed: () => setState(_reload),
          icon: const Icon(Symbols.refresh),
        ),
      ],
      child: FutureBuilder<(List<FlywheelOwnerBlob>, List<FlywheelAuditEntry>)>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const PageLoading();
          }
          if (snapshot.hasError) {
            return PageError(message: wattApiErrorMessage(snapshot.error!));
          }
          final (blobs, audit) = snapshot.data!;
          return DefaultTabController(
            length: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TabBar(
                  tabs: [
                    Tab(text: 'flywheelSaves'.tr()),
                    Tab(text: 'flywheelAudit'.tr()),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    children: [
                      _BlobList(blobs: blobs, onDelete: _delete),
                      _AuditList(entries: audit),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BlobList extends StatelessWidget {
  const _BlobList({required this.blobs, required this.onDelete});
  final List<FlywheelOwnerBlob> blobs;
  final ValueChanged<FlywheelOwnerBlob> onDelete;

  @override
  Widget build(BuildContext context) {
    if (blobs.isEmpty) {
      return EmptyState(
        icon: Symbols.sync,
        title: 'flywheelNoEncryptedSaves'.tr(),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: blobs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final blob = blobs[index];
        return ListTile(
          title: Text(
            blob.blobId,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          subtitle: Text(
            'flywheelRevisionSummary'.tr(
              namedArgs: {
                'revision': '${blob.currentRevision}',
                'retained': '${blob.retainedRevisionCount}',
                'size': _bytes(blob.retainedBytes),
              },
            ),
          ),
          trailing: IconButton(
            tooltip: 'flywheelDeleteSave'.tr(),
            onPressed: () => onDelete(blob),
            icon: Icon(
              Symbols.delete,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        );
      },
    );
  }
}

class _AuditList extends StatelessWidget {
  const _AuditList({required this.entries});
  final List<FlywheelAuditEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return EmptyState(
        icon: Symbols.history,
        title: 'flywheelNoAuditEvents'.tr(),
      );
    }
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final revision = entry.revision == null
            ? ''
            : 'flywheelRevisionSuffix'.tr(
                namedArgs: {'revision': '${entry.revision}'},
              );
        return ListTile(
          leading: Icon(
            entry.action == 'blob.deleted' ? Symbols.delete : Symbols.upload,
          ),
          title: Text('${entry.action}$revision'),
          subtitle: Text(
            'flywheelAuditActor'.tr(
              namedArgs: {
                'id': entry.actorAccountId,
                'time': '${entry.createdAt.toLocal()}',
              },
            ),
          ),
          isThreeLine: true,
        );
      },
    );
  }
}

String _bytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
