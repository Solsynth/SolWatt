import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/ui/cloud_files.dart';
import 'package:solwatt/ui/page_scaffold.dart';
import 'package:solwatt/workspaces/workspace_actions.dart';

/// Registry console for every workspace the signed-in account can reach.
///
/// Ported from Solian's workspace management screen: it lists the account's
/// workspaces, opens the per-workspace console, and carries the create/edit/
/// members/plan/delete actions. Selecting which workspace is *active* stays a
/// separate concern — that happens from this list's menu or the drawer.
@RoutePage()
class WorkspaceManagementPage extends ConsumerWidget {
  const WorkspaceManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaces = ref.watch(workspacesProvider);
    final selected = ref.watch(selectedWorkspaceProvider).value;

    Future<void> refresh() async {
      ref.invalidate(workspacesProvider);
      await ref.read(workspacesProvider.future);
    }

    return PageScaffold(
      title: 'manageWorkspaces'.tr(),
      subtitle: 'accountAndWorkspaces'.tr(),
      actions: [
        IconButton(
          tooltip: 'refresh'.tr(),
          onPressed: workspaces.isLoading ? null : refresh,
          icon: const Icon(Symbols.refresh),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        tooltip: 'createWorkspace'.tr(),
        onPressed: () => createWorkspaceAction(context, ref),
        child: const Icon(Symbols.add),
      ),
      child: workspaces.when(
        loading: () => const PageLoading(),
        error: (error, _) => PageError(
          message: wattApiErrorMessage(error),
          onRetry: refresh,
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Symbols.workspaces,
              title: 'noWorkspaces'.tr(),
              message: 'noWorkspacesEmpty'.tr(),
              action: FilledButton.icon(
                onPressed: () => createWorkspaceAction(context, ref),
                icon: const Icon(Symbols.add),
                label: Text('createWorkspace'.tr()),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _WorkspaceRow(
                workspace: items[index],
                isActive: selected?.id == items[index].id,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WorkspaceRow extends ConsumerWidget {
  const _WorkspaceRow({required this.workspace, required this.isActive});

  final Workspace workspace;
  final bool isActive;

  void _openConsole(BuildContext context) => context.router.pushPath(
    '/workspaces/${Uri.encodeComponent(workspace.slug)}',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final planLabel = workspace.isIndividual
        ? 'personalWorkspace'.tr()
        : 'organizationWorkspace'.tr();

    return Card(
      clipBehavior: Clip.antiAlias,
      color: isActive
          ? scheme.primaryContainer.withValues(alpha: 0.55)
          : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isActive
            ? BorderSide(color: scheme.primary.withValues(alpha: 0.45))
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openConsole(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            children: [
              CloudFileAvatar(
                file: workspace.picture,
                workspaceId: workspace.id,
                fallbackIcon: Symbols.workspaces,
                size: 44,
                selected: isActive,
                borderRadius: workspace.isIndividual
                    ? BorderRadius.circular(999)
                    : null,
                assumeImage: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            workspace.name,
                            style: text.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Symbols.check_circle,
                            size: 16,
                            color: scheme.primary,
                            fill: 1,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${workspace.slug} · $planLabel · ${workspace.planName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'workspaceActions'.tr(),
                icon: Icon(
                  Symbols.more_vert,
                  color: scheme.onSurfaceVariant,
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'open':
                      _openConsole(context);
                    case 'activate':
                      activateWorkspaceAction(ref, workspace);
                    case 'edit':
                      editWorkspaceAction(context, ref, workspace);
                    case 'members':
                      showWorkspaceMembers(context, workspace);
                    case 'plan':
                      showWorkspaceQuota(context, ref, workspace);
                    case 'leave':
                      leaveWorkspaceAction(context, ref);
                    case 'delete':
                      deleteWorkspaceAction(context, ref, workspace);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'open',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Symbols.open_in_new),
                      title: Text('manageWorkspaces'.tr()),
                    ),
                  ),
                  if (!isActive)
                    PopupMenuItem(
                      value: 'activate',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Symbols.check_circle),
                        title: Text('workspaceSetActive'.tr()),
                      ),
                    ),
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Symbols.edit),
                      title: Text('edit'.tr()),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'members',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Symbols.group),
                      title: Text('manageMembers'.tr()),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'plan',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Symbols.workspace_premium),
                      title: Text('planAndQuotas'.tr()),
                    ),
                  ),
                  if (isActive)
                    PopupMenuItem(
                      value: 'leave',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Symbols.logout),
                        title: Text('leaveWorkspace'.tr()),
                      ),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Symbols.delete, color: scheme.error),
                      title: Text(
                        'delete'.tr(),
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
