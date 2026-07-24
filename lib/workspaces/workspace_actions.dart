import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import '../network.dart';
import '../ui/page_scaffold.dart';

class WorkspaceDraft {
  const WorkspaceDraft(this.slug, this.name, this.description, this.type);
  final String slug;
  final String name;
  final String? description;
  final int type;
}

Future<void> createWorkspaceAction(BuildContext context, WidgetRef ref) async {
  final profile = await ref.read(userInfoProvider.future);
  if (!context.mounted) return;
  final draft = await showWorkspaceEditor(context, profile: profile);
  if (draft == null) return;
  try {
    final workspace = await ref
        .read(wattEngineClientProvider)
        .createWorkspace(
          slug: draft.slug,
          name: draft.name,
          description: draft.description,
          type: draft.type,
        );
    ref.invalidate(workspacesProvider);
    await selectWorkspace(ref.read(secureStorageProvider), workspace);
    invalidateWorkspaceScope(ref);
    showSnackBar('Workspace created.');
  } catch (error) {
    showSnackBar(error.toString());
  }
}

Future<void> editWorkspaceAction(
  BuildContext context,
  WidgetRef ref,
  Workspace workspace,
) async {
  final draft = await showWorkspaceEditor(context, workspace: workspace);
  if (draft == null) return;
  try {
    await ref
        .read(wattEngineClientProvider)
        .updateWorkspace(
          slug: workspace.slug,
          name: draft.name,
          description: draft.description,
        );
    ref.invalidate(workspacesProvider);
    invalidateWorkspaceScope(ref);
    showSnackBar('Workspace updated.');
  } catch (error) {
    showSnackBar(error.toString());
  }
}

Future<void> deleteWorkspaceAction(
  BuildContext context,
  WidgetRef ref,
  Workspace workspace,
) async {
  final scheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Symbols.delete, color: scheme.error),
      title: Text('Delete ${workspace.name}?'),
      content: const Text(
        'This permanently deletes the workspace and its data.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    final selected = await ref.read(selectedWorkspaceProvider.future);
    await ref.read(wattEngineClientProvider).deleteWorkspace(workspace.slug);
    if (selected?.id == workspace.id) {
      await clearSelectedWorkspace(ref.read(secureStorageProvider));
    }
    ref.invalidate(workspacesProvider);
    invalidateWorkspaceScope(ref);
    showSnackBar('Workspace deleted.');
  } catch (error) {
    showSnackBar(error.toString());
  }
}

Future<void> activateWorkspaceAction(WidgetRef ref, Workspace workspace) async {
  await selectWorkspace(ref.read(secureStorageProvider), workspace);
  invalidateWorkspaceScope(ref);
  showSnackBar('${workspace.name} is now active.');
}

Future<void> showWorkspaceQuota(
  BuildContext context,
  WidgetRef ref,
  Workspace workspace,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: FutureBuilder(
          future: ref
              .read(wattEngineClientProvider)
              .getWorkspaceQuota(workspace.slug),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return EmptyState(
                icon: Symbols.error,
                title: 'Could not load quotas',
                message: snapshot.error.toString(),
              );
            }
            final quota = snapshot.data!;
            final plan =
                ['Free', 'Pro', 'Enterprise'].elementAtOrNull(quota.plan) ??
                'Plan ${quota.plan}';
            return ListView(
              shrinkWrap: true,
              children: [
                Text('${workspace.name} quotas', style: text.titleLarge),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusChip(
                    label: plan,
                    icon: Symbols.workspace_premium,
                    tone: StatusChipTone.secondary,
                  ),
                ),
                const SizedBox(height: 16),
                for (final entry in quota.limits.entries)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        entry.key.replaceAll('_', ' '),
                        style: text.titleSmall,
                      ),
                      trailing: Text(
                        _formatQuota(entry.value),
                        style: text.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  },
);

String _formatQuota(dynamic value) {
  if (value is num && value >= 1024 * 1024 * 1024) {
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';
  }
  return value.toString();
}

Future<WorkspaceDraft?> showWorkspaceEditor(
  BuildContext context, {
  Workspace? workspace,
  SnAccount? profile,
}) {
  final slug = TextEditingController(text: workspace?.slug ?? '');
  final name = TextEditingController(text: workspace?.name ?? '');
  final description = TextEditingController(text: workspace?.description ?? '');
  var type = 0;
  var usePersonalDetails = false;
  return showModalBottomSheet<WorkspaceDraft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => SheetScaffold(
        titleText: workspace == null ? 'New workspace' : 'Edit workspace',
        heightFactor: 0.72,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (workspace == null) ...[
                TextField(
                  controller: slug,
                  decoration: const InputDecoration(
                    labelText: 'Slug',
                    hintText: 'my-team',
                    prefixIcon: Icon(Symbols.link),
                  ),
                ),
                const SizedBox(height: 16),
                if (profile?.name.isNotEmpty == true) ...[
                  Card(
                    child: CheckboxListTile(
                      value: usePersonalDetails,
                      title: const Text('Use my personal workspace details'),
                      subtitle: Text(
                        'Uses @${profile!.name} and your profile nick.',
                      ),
                      onChanged: type == 0
                          ? (selected) => setState(() {
                              usePersonalDetails = selected ?? false;
                              if (usePersonalDetails) {
                                slug.text = profile.name;
                                name.text = profile.solWattDisplayName;
                                description.text =
                                    "${profile.solWattDisplayName}'s personal workspace";
                              }
                            })
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Symbols.badge),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: description,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Symbols.notes),
                ),
                maxLines: 4,
              ),
              if (workspace == null) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: type,
                  decoration: const InputDecoration(
                    labelText: 'Workspace type',
                    prefixIcon: Icon(Symbols.category),
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Individual')),
                    DropdownMenuItem(value: 1, child: Text('Organization')),
                  ],
                  onChanged: (value) => setState(() {
                    type = value ?? 0;
                    if (type != 0) usePersonalDetails = false;
                  }),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () {
                  final slugText = slug.text.trim();
                  final nameText = name.text.trim();
                  if (workspace == null && slugText.isEmpty) {
                    showSnackBar('Slug is required.');
                    return;
                  }
                  if (nameText.isEmpty) {
                    showSnackBar('Name is required.');
                    return;
                  }
                  Navigator.pop(
                    context,
                    WorkspaceDraft(
                      slugText,
                      nameText,
                      description.text.trim().isEmpty
                          ? null
                          : description.text.trim(),
                      type,
                    ),
                  );
                },
                child: Text(
                  workspace == null ? 'Create workspace' : 'Save changes',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ).whenComplete(() {
    slug.dispose();
    name.dispose();
    description.dispose();
  });
}

/// Compact list of workspaces used by the gate and profile screens.
class WorkspaceList extends ConsumerWidget {
  const WorkspaceList({
    super.key,
    required this.onActivate,
    this.manageActions = false,
    this.emptyMessage = 'No workspaces yet. Create one to continue.',
  });

  final Future<void> Function(Workspace workspace) onActivate;
  final bool manageActions;
  final String emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaces = ref.watch(workspacesProvider);
    final selected = ref.watch(selectedWorkspaceProvider).value;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return workspaces.when(
      loading: () => const PageLoading(),
      error: (error, _) => PageError(
        message: error.toString(),
        onRetry: () => ref.invalidate(workspacesProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            icon: Symbols.workspaces,
            title: 'No workspaces',
            message: emptyMessage,
            action: FilledButton.icon(
              onPressed: () => createWorkspaceAction(context, ref),
              icon: const Icon(Symbols.add),
              label: const Text('Create workspace'),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final workspace = items[index];
            final isActive = selected?.id == workspace.id;
            return Card(
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
                onTap: () => onActivate(workspace),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      IconBadge(
                        icon: isActive
                            ? Symbols.check_circle
                            : Symbols.workspaces,
                        selected: isActive,
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
                                  const SizedBox(width: 8),
                                  StatusChip(
                                    label: 'Active',
                                    tone: StatusChipTone.primary,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              workspace.description?.isNotEmpty == true
                                  ? '${workspace.slug} · ${workspace.description}'
                                  : workspace.slug,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (manageActions)
                        PopupMenuButton<String>(
                          tooltip: 'Workspace actions',
                          icon: Icon(
                            Symbols.more_vert,
                            color: scheme.onSurfaceVariant,
                          ),
                          onSelected: (value) {
                            switch (value) {
                              case 'quota':
                                showWorkspaceQuota(context, ref, workspace);
                              case 'edit':
                                editWorkspaceAction(context, ref, workspace);
                              case 'delete':
                                deleteWorkspaceAction(context, ref, workspace);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'quota',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Symbols.monitoring),
                                title: Text('View quotas'),
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'edit',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Symbols.edit),
                                title: Text('Edit'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Symbols.delete,
                                  color: scheme.error,
                                ),
                                title: Text(
                                  'Delete',
                                  style: TextStyle(color: scheme.error),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Icon(
                          Symbols.chevron_right,
                          color: scheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
