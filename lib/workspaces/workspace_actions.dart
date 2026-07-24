import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import '../network.dart';
import '../theme.dart';
import '../ui/cloud_files.dart';
import '../ui/page_scaffold.dart';

class WorkspaceDraft {
  const WorkspaceDraft({
    required this.slug,
    required this.name,
    this.description,
    required this.type,
    this.pictureId,
    this.updatePicture = false,
    this.backgroundId,
    this.updateBackground = false,
  });
  final String slug;
  final String name;
  final String? description;
  final int type;
  final String? pictureId;
  final bool updatePicture;
  final String? backgroundId;
  final bool updateBackground;
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
          pictureId: draft.updatePicture ? draft.pictureId : null,
          backgroundId: draft.updateBackground ? draft.backgroundId : null,
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
          pictureId: draft.pictureId,
          updatePicture: draft.updatePicture,
          backgroundId: draft.backgroundId,
          updateBackground: draft.updateBackground,
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
  isScrollControlled: true,
  builder: (context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SheetScaffold(
      titleText: '${workspace.name} quotas',
      heightFactor: 0.6,
      child: FutureBuilder(
        future: ref
            .read(wattEngineClientProvider)
            .getWorkspaceQuota(workspace.slug),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
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
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
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
    );
  },
);

Future<void> showWorkspaceMembers(BuildContext context, Workspace workspace) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WorkspaceMembersSheet(workspace: workspace),
    );

class _WorkspaceMembersSheet extends ConsumerStatefulWidget {
  const _WorkspaceMembersSheet({required this.workspace});

  final Workspace workspace;

  @override
  ConsumerState<_WorkspaceMembersSheet> createState() =>
      _WorkspaceMembersSheetState();
}

class _WorkspaceMembersSheetState
    extends ConsumerState<_WorkspaceMembersSheet> {
  late Future<List<WorkspaceMember>> _members;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _members = ref
      .read(wattEngineClientProvider)
      .listWorkspaceMembers(widget.workspace.slug);

  Future<void> _invite() async {
    final account = await showModalBottomSheet<SnAccount>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _AccountPickerSheet(client: ref.read(wattEngineClientProvider)),
    );
    if (account == null || !mounted) return;
    final role = await _selectRole(
      context,
      title: 'Invite ${account.solWattDisplayName}',
    );
    if (role == null || !mounted) return;
    try {
      await ref
          .read(wattEngineClientProvider)
          .inviteWorkspaceMember(
            slug: widget.workspace.slug,
            accountId: account.id,
            role: role,
          );
      _refresh('Invitation sent.');
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  Future<void> _changeRole(WorkspaceMember member) async {
    final role = await _selectRole(
      context,
      title: 'Change role',
      selectedRole: member.role,
    );
    if (role == null || role == member.role || !mounted) return;
    try {
      await ref
          .read(wattEngineClientProvider)
          .updateWorkspaceMemberRole(
            slug: widget.workspace.slug,
            accountId: member.accountId,
            role: role,
          );
      _refresh('Member role updated.');
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  Future<void> _remove(WorkspaceMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove member?'),
        content: const Text('This member will lose access to the workspace.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(wattEngineClientProvider)
          .removeWorkspaceMember(
            slug: widget.workspace.slug,
            accountId: member.accountId,
          );
      _refresh('Member removed.');
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  void _refresh(String message) {
    setState(_reload);
    showSnackBar(message);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SheetScaffold(
      titleText: 'Members',
      heightFactor: 0.78,
      actions: [
        FilledButton.tonalIcon(
          onPressed: _invite,
          icon: const Icon(Symbols.person_add, size: 18),
          label: const Text('Invite'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.workspace.name,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<WorkspaceMember>>(
                future: _members,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return EmptyState(
                      icon: Symbols.error,
                      title: 'Could not load members',
                      message: snapshot.error.toString(),
                      action: FilledButton(
                        onPressed: () => setState(_reload),
                        child: const Text('Try again'),
                      ),
                    );
                  }
                  final members = snapshot.data ?? const [];
                  if (members.isEmpty) {
                    return const EmptyState(
                      icon: Symbols.group,
                      title: 'No members',
                      message:
                          'Invite people to collaborate in this workspace.',
                    );
                  }
                  return ListView.separated(
                    itemCount: members.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final member = members[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          child: Text(_memberInitial(member)),
                        ),
                        title: Text(
                          member.displayName ??
                              'Account ${_shortId(member.accountId)}',
                        ),
                        subtitle: Text(
                          '${_roleName(member.role)} · '
                          '${member.username == null ? member.accountId : '@${member.username}'}',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'role') _changeRole(member);
                            if (action == 'remove') _remove(member);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'role',
                              child: Text('Role: ${_roleName(member.role)}'),
                            ),
                            if (member.role != 100)
                              const PopupMenuItem(
                                value: 'remove',
                                child: Text('Remove member'),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<int?> _selectRole(
  BuildContext context, {
  required String title,
  int? selectedRole,
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  builder: (context) => SheetScaffold(
    titleText: title,
    heightFactor: 0.45,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      children: [
        for (final role in const [25, 50, 75, 100])
          ListTile(
            title: Text(_roleName(role)),
            trailing: selectedRole == role ? const Icon(Symbols.check) : null,
            onTap: () => Navigator.pop(context, role),
          ),
      ],
    ),
  ),
);

String _roleName(int role) => switch (role) {
  25 => 'Viewer',
  50 => 'Member',
  75 => 'Admin',
  100 => 'Owner',
  _ => 'Role $role',
};

String _shortId(String id) => id.length > 8 ? id.substring(0, 8) : id;
String _memberInitial(WorkspaceMember member) =>
    (member.displayName ?? member.username ?? member.accountId).isEmpty
    ? '?'
    : (member.displayName ?? member.username ?? member.accountId)[0]
          .toUpperCase();

class _AccountPickerSheet extends StatefulWidget {
  const _AccountPickerSheet({required this.client});

  final WattEngineClient client;

  @override
  State<_AccountPickerSheet> createState() => _AccountPickerSheetState();
}

class _AccountPickerSheetState extends State<_AccountPickerSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  Future<List<SnAccount>>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _results = widget.client.searchAccounts(query));
    });
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      titleText: 'Invite member',
      heightFactor: 0.7,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          children: [
            SearchBar(
              controller: _controller,
              hintText: 'Search accounts',
              leading: const Icon(Symbols.search),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _results == null
                  ? const Center(
                      child: Text('Search for an account to invite.'),
                    )
                  : FutureBuilder<List<SnAccount>>(
                      future: _results,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState !=
                            ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(snapshot.error.toString()),
                          );
                        }
                        final accounts = snapshot.data ?? const [];
                        if (accounts.isEmpty) {
                          return const Center(
                            child: Text('No accounts found.'),
                          );
                        }
                        return ListView.builder(
                          itemCount: accounts.length,
                          itemBuilder: (context, index) {
                            final account = accounts[index];
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  account.solWattDisplayName[0].toUpperCase(),
                                ),
                              ),
                              title: Text(account.solWattDisplayName),
                              subtitle: Text('@${account.name}'),
                              onTap: () => Navigator.pop(context, account),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

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
  return showModalBottomSheet<WorkspaceDraft>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _WorkspaceEditorSheet(
      workspace: workspace,
      profile: profile,
    ),
  );
}

class _WorkspaceEditorSheet extends ConsumerStatefulWidget {
  const _WorkspaceEditorSheet({this.workspace, this.profile});

  final Workspace? workspace;
  final SnAccount? profile;

  @override
  ConsumerState<_WorkspaceEditorSheet> createState() =>
      _WorkspaceEditorSheetState();
}

class _WorkspaceEditorSheetState extends ConsumerState<_WorkspaceEditorSheet> {
  late final TextEditingController _slug;
  late final TextEditingController _name;
  late final TextEditingController _description;
  var _type = 0;
  var _usePersonalDetails = false;
  SnCloudFileReference? _picture;
  SnCloudFileReference? _background;
  var _pictureChanged = false;
  var _backgroundChanged = false;

  @override
  void initState() {
    super.initState();
    final workspace = widget.workspace;
    _slug = TextEditingController(text: workspace?.slug ?? '');
    _name = TextEditingController(text: workspace?.name ?? '');
    _description = TextEditingController(text: workspace?.description ?? '');
    _type = workspace?.type ?? 0;
    _picture = workspace?.picture;
    _background = workspace?.background;
  }

  @override
  void dispose() {
    _slug.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickPicture() async {
    final file = await pickCloudImageReference(
      context,
      ref,
      usage: 'workspace.picture',
      title: 'Workspace icon',
    );
    if (file == null || !mounted) return;
    setState(() {
      _picture = file;
      _pictureChanged = true;
    });
  }

  Future<void> _pickBackground() async {
    final file = await pickCloudImageReference(
      context,
      ref,
      usage: 'workspace.background',
      title: 'Workspace background',
    );
    if (file == null || !mounted) return;
    setState(() {
      _background = file;
      _backgroundChanged = true;
    });
  }

  void _submit() {
    final slugText = _slug.text.trim();
    final nameText = _name.text.trim();
    if (widget.workspace == null && slugText.isEmpty) {
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
        slug: slugText,
        name: nameText,
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        type: _type,
        pictureId: _picture?.id,
        updatePicture: _pictureChanged,
        backgroundId: _background?.id,
        updateBackground: _backgroundChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final workspace = widget.workspace;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SheetScaffold(
      titleText: workspace == null ? 'New workspace' : 'Edit workspace',
      heightFactor: 0.82,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: _pickPicture,
                  borderRadius: BorderRadius.circular(16),
                  child: CloudFileAvatar(
                    file: _picture,
                    fallbackIcon: Symbols.workspaces,
                    size: 72,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Workspace icon', style: text.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'Shown in the workspace list and gate.',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: _pickPicture,
                            icon: const Icon(Symbols.upload, size: 18),
                            label: Text(
                              _picture == null ? 'Upload' : 'Change',
                            ),
                          ),
                          if (_picture != null)
                            TextButton(
                              onPressed: () => setState(() {
                                _picture = null;
                                _pictureChanged = true;
                              }),
                              child: const Text('Clear'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CloudFileAvatar(
                file: _background,
                fallbackIcon: Symbols.wallpaper,
                size: 40,
              ),
              title: const Text('Background image'),
              subtitle: Text(
                _background == null ? 'Optional' : _background!.name,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_background != null)
                    IconButton(
                      tooltip: 'Clear background',
                      icon: const Icon(Symbols.close),
                      onPressed: () => setState(() {
                        _background = null;
                        _backgroundChanged = true;
                      }),
                    ),
                  IconButton(
                    tooltip: 'Choose background',
                    icon: const Icon(Symbols.upload),
                    onPressed: _pickBackground,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (workspace == null) ...[
              TextField(
                controller: _slug,
                decoration: InputDecoration(
                  labelText: 'Slug',
                  hintText: 'my-team',
                  prefixIcon: inputPrefixIcon(Symbols.link),
                ),
              ),
              const SizedBox(height: 16),
              if (profile?.name.isNotEmpty == true) ...[
                Card(
                  child: CheckboxListTile(
                    value: _usePersonalDetails,
                    title: const Text('Use my personal workspace details'),
                    subtitle: Text(
                      'Uses @${profile!.name} and your profile nick.',
                    ),
                    onChanged: _type == 0
                        ? (selected) => setState(() {
                            _usePersonalDetails = selected ?? false;
                            if (_usePersonalDetails) {
                              _slug.text = profile.name;
                              _name.text = profile.solWattDisplayName;
                              _description.text =
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
              controller: _name,
              decoration: InputDecoration(
                labelText: 'Name',
                prefixIcon: inputPrefixIcon(Symbols.badge),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              decoration: InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
                prefixIcon: inputPrefixIcon(Symbols.notes),
              ),
              maxLines: 4,
            ),
            if (workspace == null) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: 'Workspace type',
                  prefixIcon: inputPrefixIcon(Symbols.category),
                ),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Individual')),
                  DropdownMenuItem(value: 1, child: Text('Organization')),
                ],
                onChanged: (value) => setState(() {
                  _type = value ?? 0;
                  if (_type != 0) _usePersonalDetails = false;
                }),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _submit,
              child: Text(
                workspace == null ? 'Create workspace' : 'Save changes',
              ),
            ),
          ],
        ),
      ),
    );
  }
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
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CloudFileAvatar(
                            file: workspace.picture,
                            fallbackIcon: Symbols.workspaces,
                            size: 44,
                            selected: isActive,
                          ),
                          if (isActive)
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Icon(
                                Symbols.check_circle,
                                size: 16,
                                color: scheme.primary,
                                fill: 1,
                              ),
                            ),
                        ],
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
                              case 'members':
                                showWorkspaceMembers(context, workspace);
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
                              value: 'members',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Symbols.group),
                                title: Text('Manage members'),
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
