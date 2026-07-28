import 'package:auto_route/auto_route.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/ui/alert.dart';
import 'package:solwatt/ui/page_scaffold.dart';

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
          : _FlywheelWorkspacePage(
              workspaceId: value.id,
              workspaceName: value.name,
            ),
    );
  }
}

class _FlywheelWorkspacePage extends ConsumerStatefulWidget {
  const _FlywheelWorkspacePage({
    required this.workspaceId,
    required this.workspaceName,
  });
  final String workspaceId;
  final String workspaceName;

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

  @override
  Widget build(BuildContext context) => PageScaffold(
    title: 'Flywheel',
    subtitle: widget.workspaceName,
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
        return ListView.separated(
          itemCount: apps.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final app = apps[index];
            return Card(
              child: ListTile(
                leading: const Icon(Symbols.sync),
                title: Text(app.appId),
                subtitle: Text(
                  '${app.blobCount} saves · ${app.retainedRevisionCountTotal} retained revisions · ${_bytes(app.retainedBytes)}',
                ),
                trailing: const Icon(Symbols.chevron_right),
                onTap: () async {
                  await showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => _FlywheelAppSheet(
                      workspaceId: widget.workspaceId,
                      app: app,
                    ),
                  );
                  if (mounted) {
                    setState(_reload);
                  }
                },
              ),
            );
          },
        );
      },
    ),
  );
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

  void _notify(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FractionallySizedBox(
      heightFactor: 0.86,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child:
            FutureBuilder<(List<FlywheelOwnerBlob>, List<FlywheelAuditEntry>)>(
              future: _data,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const PageLoading();
                }
                if (snapshot.hasError) {
                  return PageError(
                    message: wattApiErrorMessage(snapshot.error!),
                  );
                }
                final (blobs, audit) = snapshot.data!;
                return DefaultTabController(
                  length: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.app.appId,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(_reload),
                            icon: const Icon(Symbols.refresh),
                          ),
                        ],
                      ),
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
      ),
    ),
  );
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
      itemCount: blobs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final blob = blobs[index];
        return ListTile(
          title: Text(
            blob.blobId,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
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
