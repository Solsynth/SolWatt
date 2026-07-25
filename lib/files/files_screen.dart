import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/ui/cloud_files.dart';
import 'package:solwatt/ui/page_scaffold.dart';

/// Workspace-scoped Drive browser, simplified from Island's file list screen.
///
/// Files and folders created here send `workspace_id` so storage is charged to
/// the workspace plan (see FileSystem `WORKSPACE_FILES.md`).
@RoutePage()
class FilesPage extends ConsumerStatefulWidget {
  const FilesPage({super.key});

  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage> {
  /// Empty stack = workspace root. Each entry is a folder breadcrumb.
  final List<({String id, String name})> _path = [];
  String? _query;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _parentId => _path.isEmpty ? '' : _path.last.id;

  void _invalidateFolder() {
    ref.invalidate(workspaceFolderChildrenProvider(_parentId));
    ref.invalidate(workspaceFilesProvider);
  }

  Future<void> _uploadFiles() async {
    final workspace = await ref.read(selectedWorkspaceProvider.future);
    if (workspace == null) {
      showSnackBar('Select a workspace first.');
      return;
    }
    if (!mounted) return;

    // OS file picker → background task overlay (Island-style).
    final files = await uploadLocalCloudFiles(
      ref,
      allowMultiple: true,
      workspaceId: workspace.id,
      parentId: _parentId.isEmpty ? null : _parentId,
      indexed: true,
    );
    if (files == null || files.isEmpty || !mounted) return;
    _invalidateFolder();
    showSnackBar(
      files.length == 1
          ? 'Uploaded ${files.first.name}.'
          : 'Uploaded ${files.length} files.',
    );
  }

  Future<void> _createFolder() async {
    final workspace = await ref.read(selectedWorkspaceProvider.future);
    if (workspace == null) {
      showSnackBar('Select a workspace first.');
      return;
    }
    if (!mounted) return;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _NameDialog(
        title: 'New folder',
        label: 'Folder name',
        confirmLabel: 'Create',
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await ref
          .read(wattEngineClientProvider)
          .createCloudFolder(
            name: name.trim(),
            workspaceId: workspace.id,
            parentId: _parentId.isEmpty ? null : _parentId,
          );
      _invalidateFolder();
      showSnackBar('Folder created.');
    } catch (error) {
      showSnackBar(driveApiErrorMessage(error));
    }
  }

  Future<void> _rename(DriveFileEntry entry) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(
        title: entry.isFolder ? 'Rename folder' : 'Rename file',
        label: 'Name',
        confirmLabel: 'Save',
        initialValue: entry.name,
      ),
    );
    if (name == null || name.trim().isEmpty || name.trim() == entry.name) {
      return;
    }
    try {
      await ref
          .read(wattEngineClientProvider)
          .renameCloudFile(entry.id, name.trim());
      _invalidateFolder();
      showSnackBar('Renamed.');
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  Future<void> _delete(DriveFileEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.isFolder ? 'Delete folder?' : 'Delete file?'),
        content: Text(
          'Permanently delete “${entry.name.isEmpty ? entry.id : entry.name}”? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(wattEngineClientProvider).deleteCloudFile(entry.id);
      _invalidateFolder();
      showSnackBar('Deleted.');
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  void _openFolder(DriveFileEntry entry) {
    setState(() {
      _path.add((id: entry.id, name: entry.name));
      _query = null;
      _searchController.clear();
    });
  }

  Future<void> _inspect(DriveFileEntry entry) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FileDetailSheet(
        entry: entry,
        onRename: () {
          Navigator.pop(context);
          _rename(entry);
        },
        onDelete: () {
          Navigator.pop(context);
          _delete(entry);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final children = ref.watch(workspaceFolderChildrenProvider(_parentId));
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return PageScaffold(
      title: 'Files',
      subtitle: workspace == null
          ? 'Workspace Drive'
          : 'Workspace files in ${workspace.name}',
      maxContentWidth: 1100,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _invalidateFolder,
          icon: const Icon(Symbols.refresh),
        ),
        IconButton(
          tooltip: 'New folder',
          onPressed: workspace == null ? null : _createFolder,
          icon: const Icon(Symbols.create_new_folder),
        ),
        FilledButton.tonalIcon(
          onPressed: workspace == null ? null : _uploadFiles,
          icon: const Icon(Symbols.upload, size: 18),
          label: const Text('Upload'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        TextButton.icon(
                          onPressed: _path.isEmpty
                              ? null
                              : () => setState(() {
                                  _path.clear();
                                  _query = null;
                                  _searchController.clear();
                                }),
                          icon: const Icon(Symbols.home, size: 18),
                          label: const Text('Root'),
                        ),
                        for (var i = 0; i < _path.length; i++) ...[
                          Icon(
                            Symbols.chevron_right,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                          TextButton(
                            onPressed: i == _path.length - 1
                                ? null
                                : () => setState(() {
                                    _path.removeRange(i + 1, _path.length);
                                    _query = null;
                                    _searchController.clear();
                                  }),
                            child: Text(_path[i].name),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Filter in this folder',
                      prefixIcon: const Icon(Symbols.search),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: _query == null || _query!.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Symbols.close, size: 18),
                              onPressed: () => setState(() {
                                _query = null;
                                _searchController.clear();
                              }),
                            ),
                    ),
                    onChanged: (value) => setState(() {
                      _query = value.trim().isEmpty ? null : value.trim();
                    }),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: children.when(
              loading: () => const PageLoading(),
              error: (error, _) => PageError(
                message: error.toString(),
                onRetry: _invalidateFolder,
              ),
              data: (items) {
                var visible = items;
                if (_query != null && _query!.isNotEmpty) {
                  final q = _query!.toLowerCase();
                  visible = items
                      .where((e) => e.name.toLowerCase().contains(q))
                      .toList(growable: false);
                }
                // Folders first, then by name.
                final sorted = [...visible]
                  ..sort((a, b) {
                    if (a.isFolder != b.isFolder) {
                      return a.isFolder ? -1 : 1;
                    }
                    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                  });

                if (workspace == null) {
                  return const EmptyState(
                    icon: Symbols.folder_off,
                    title: 'No workspace selected',
                    message: 'Choose a workspace to browse its files.',
                  );
                }

                if (sorted.isEmpty) {
                  return EmptyState(
                    icon: Symbols.folder_open,
                    title: _path.isEmpty
                        ? 'No workspace files yet'
                        : 'This folder is empty',
                    message:
                        'Upload files or create a folder. Storage uses the '
                        'workspace plan quota, not your personal Drive quota.',
                    action: FilledButton.icon(
                      onPressed: _uploadFiles,
                      icon: const Icon(Symbols.upload),
                      label: const Text('Upload files'),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => _invalidateFolder(),
                  child: ListView.separated(
                    itemCount: sorted.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = sorted[index];
                      return _FileListTile(
                        entry: entry,
                        onOpen: () {
                          if (entry.isFolder) {
                            _openFolder(entry);
                          } else {
                            _inspect(entry);
                          }
                        },
                        onRename: () => _rename(entry),
                        onDelete: () => _delete(entry),
                        onInspect: () => _inspect(entry),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Workspace files keep the uploader for audit, but ownership and '
              'storage quota follow the workspace.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileListTile extends StatelessWidget {
  const _FileListTile({
    required this.entry,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onInspect,
  });

  final DriveFileEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onInspect;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CloudFileAvatar(
        file: entry.file,
        fallbackIcon: entry.isFolder ? Symbols.folder : Symbols.description,
        size: 44,
      ),
      title: Text(
        entry.name.isEmpty ? 'Untitled' : entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(entry.isFolder ? 'Folder' : formatByteSize(entry.size)),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'open':
              onOpen();
            case 'inspect':
              onInspect();
            case 'rename':
              onRename();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'open',
            child: Text(entry.isFolder ? 'Open' : 'View'),
          ),
          const PopupMenuItem(value: 'inspect', child: Text('Details')),
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: onOpen,
      onLongPress: onInspect,
    );
  }
}

class _FileDetailSheet extends StatelessWidget {
  const _FileDetailSheet({
    required this.entry,
    required this.onRename,
    required this.onDelete,
  });

  final DriveFileEntry entry;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isImage = entry.mimeType.startsWith('image/');
    final url = cloudFileDisplayUrl(entry.file);

    return SheetScaffold(
      titleText: entry.name.isEmpty ? 'File details' : entry.name,
      heightFactor: 0.65,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          if (isImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: entry.file.ratio ?? 16 / 9,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: const Center(child: Icon(Symbols.broken_image)),
                  ),
                ),
              ),
            )
          else
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(
                  entry.isFolder ? Symbols.folder : Symbols.description,
                  size: 48,
                  color: scheme.primary,
                ),
              ),
            ),
          const SizedBox(height: 16),
          _DetailRow(label: 'ID', value: entry.id, copyable: true),
          _DetailRow(
            label: 'Type',
            value: entry.isFolder ? 'Folder' : entry.mimeType,
          ),
          if (!entry.isFolder)
            _DetailRow(label: 'Size', value: formatByteSize(entry.size)),
          if (entry.workspaceId != null)
            _DetailRow(label: 'Workspace', value: entry.workspaceId!),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!entry.isFolder)
                FilledButton.tonalIcon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    showSnackBar('Link copied.');
                  },
                  icon: const Icon(Symbols.link, size: 18),
                  label: const Text('Copy link'),
                ),
              OutlinedButton.icon(
                onPressed: onRename,
                icon: const Icon(Symbols.edit, size: 18),
                label: const Text('Rename'),
              ),
              OutlinedButton.icon(
                onPressed: onDelete,
                icon: Icon(Symbols.delete, size: 18, color: scheme.error),
                label: Text('Delete', style: TextStyle(color: scheme.error)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Workspace-owned files retain the uploader account for audit while '
            'storage is billed to the workspace plan.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: SelectableText(value, style: text.bodyMedium)),
          if (copyable)
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Symbols.content_copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                showSnackBar('Copied.');
              },
            ),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.confirmLabel,
    this.initialValue,
  });

  final String title;
  final String label;
  final String confirmLabel;
  final String? initialValue;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
