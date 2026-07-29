import 'package:auto_route/auto_route.dart';
import 'package:dio/dio.dart';
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

@RoutePage()
class FlywheelPage extends ConsumerWidget {
  const FlywheelPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(selectedWorkspaceProvider);
    return workspace.when(
      loading: () =>
          const PageScaffold(title: 'Flywheel', child: PageLoading()),
      error: (error, _) => PageScaffold(
        title: 'Flywheel',
        child: PageError(message: wattApiErrorMessage(error)),
      ),
      data: (value) => value == null
          ? const PageScaffold(
              title: 'Flywheel',
              child: EmptyState(
                icon: Symbols.workspaces,
                title: 'Select a workspace',
              ),
            )
          : _FlywheelWorkspacePage(workspaceId: value.id),
    );
  }
}

class _FlywheelWorkspacePage extends ConsumerStatefulWidget {
  const _FlywheelWorkspacePage({required this.workspaceId});
  final String workspaceId;

  @override
  ConsumerState<_FlywheelWorkspacePage> createState() =>
      _FlywheelWorkspacePageState();
}

class _FlywheelWorkspacePageState
    extends ConsumerState<_FlywheelWorkspacePage> {
  late Future<List<FlywheelOwnerApp>> _apps;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _apps = ref
      .read(wattEngineClientProvider)
      .listFlywheelApps(widget.workspaceId);

  Future<void> _openApp(FlywheelOwnerApp app) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _FlywheelAppSheet(workspaceId: widget.workspaceId, app: app),
    );
    if (mounted) {
      setState(_reload);
    }
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
    title: 'Flywheel',
    subtitle:
        'Securely sync WattEngine productivity apps, like MaidKit, across your devices.',
    action: IconButton.filledTonal(
      tooltip: 'Refresh',
      onPressed: () => setState(_reload),
      icon: const Icon(Symbols.refresh),
    ),
    child: FutureBuilder<List<FlywheelOwnerApp>>(
      future: _apps,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const PageLoading();
        }
        if (snapshot.hasError) {
          final denied =
              snapshot.error is DioException &&
              (snapshot.error as DioException).response?.statusCode == 403;
          return EmptyState(
            icon: denied ? Symbols.lock : Symbols.error,
            title: denied
                ? 'Workspace owner access required'
                : 'Could not load Flywheel',
            message: denied
                ? 'Only the workspace owner can manage encrypted saves and view their audit trail.'
                : wattApiErrorMessage(snapshot.error!),
            action: OutlinedButton.icon(
              onPressed: () => setState(_reload),
              icon: const Icon(Symbols.refresh),
              label: const Text('Retry'),
            ),
          );
        }
        final apps = snapshot.data ?? const [];
        if (apps.isEmpty) {
          return const EmptyState(
            icon: Symbols.sync,
            title: 'No Flywheel saves',
            message:
                'Apps will appear here after they upload an encrypted save for this workspace.',
          );
        }
        final wide = MediaQuery.sizeOf(context).width >= 900;
        if (wide) {
          return GridView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.55,
            ),
            itemCount: apps.length,
            itemBuilder: (context, index) => _FlywheelAppCard(
              app: apps[index],
              onOpen: () => _openApp(apps[index]),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: apps.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final app = apps[index];
            final product = _flywheelProducts[app.appId];
            return Card(
              child: ListTile(
                leading: _FlywheelProductIcon(product: product),
                title: Text(product?.name ?? app.appId),
                subtitle: Text(
                  '${app.blobCount} saves · ${app.retainedRevisionCountTotal} retained revisions · ${_bytes(app.retainedBytes)}',
                ),
                trailing: const Icon(Symbols.chevron_right),
                onTap: () => _openApp(app),
              ),
            );
          },
        );
      },
    ),
  );
}

class _FlywheelAppCard extends StatelessWidget {
  const _FlywheelAppCard({required this.app, required this.onOpen});

  final FlywheelOwnerApp app;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final product = _flywheelProducts[app.appId];
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _FlywheelProductIcon(product: product, size: 40),
                  const Spacer(),
                  Icon(
                    Symbols.arrow_outward,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                product?.name ?? app.appId,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium,
              ),
              if (product != null) ...[
                const SizedBox(height: 4),
                Text(
                  app.appId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                '${app.blobCount} saves · ${app.retainedRevisionCountTotal} revisions',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                _bytes(app.retainedBytes),
                style: text.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlywheelProductIcon extends StatelessWidget {
  const _FlywheelProductIcon({required this.product, this.size = 40});

  final _FlywheelProduct? product;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconAsset = product?.iconAsset;
    if (iconAsset == null) {
      return Icon(Symbols.sync, size: size);
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

class _FlywheelAppSheet extends ConsumerStatefulWidget {
  const _FlywheelAppSheet({required this.workspaceId, required this.app});
  final String workspaceId;
  final FlywheelOwnerApp app;

  @override
  ConsumerState<_FlywheelAppSheet> createState() => _FlywheelAppSheetState();
}

class _FlywheelAppSheetState extends ConsumerState<_FlywheelAppSheet> {
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
      'This permanently removes every retained encrypted revision. Apps cannot restore it.',
      'Delete this Flywheel save?',
      icon: Symbols.delete,
      isDanger: true,
      confirmLabel: 'Delete',
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
      _notify('Flywheel save deleted.');
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
                const TabBar(
                  tabs: [
                    Tab(text: 'Saves'),
                    Tab(text: 'Audit'),
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
      return const EmptyState(icon: Symbols.sync, title: 'No saves');
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
            'Revision ${blob.currentRevision} · ${blob.retainedRevisionCount} retained · ${_bytes(blob.retainedBytes)}',
          ),
          trailing: IconButton(
            tooltip: 'Delete encrypted save',
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
      return const EmptyState(icon: Symbols.history, title: 'No audit events');
    }
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final revision = entry.revision == null
            ? ''
            : ' · revision ${entry.revision}';
        return ListTile(
          leading: Icon(
            entry.action == 'blob.deleted' ? Symbols.delete : Symbols.upload,
          ),
          title: Text('${entry.action}$revision'),
          subtitle: Text(
            'User ${entry.actorAccountId}\n${entry.createdAt.toLocal()}',
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
