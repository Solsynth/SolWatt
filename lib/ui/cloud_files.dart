import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:logging/logging.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/tasks/app_task.dart';
import 'package:solwatt/tasks/tasks_notifier.dart';

final _uploadLog = Logger('SolWatt.Upload');

/// Thumbnail or placeholder for a cloud file icon (workspace / board pictures).
class CloudFileAvatar extends StatelessWidget {
  const CloudFileAvatar({
    super.key,
    this.file,
    this.fallbackIcon = Symbols.image,
    this.size = 40,
    this.selected = false,
    this.borderRadius,
  });

  final IDisplayableCloudFile? file;
  final IconData fallbackIcon;
  final double size;
  final bool selected;
  final BorderRadius? borderRadius;

  static const double _selectedBorderWidth = 1.5;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outerRadius = borderRadius ?? BorderRadius.circular(size * 0.28);
    final url = file == null ? null : cloudFileDisplayUrl(file!);
    // Profile pictures sometimes omit mime_type; treat empty mime as displayable.
    final mime = file?.mimeType ?? '';
    final isImage = mime.isEmpty || mime.startsWith('image/');
    final iconColor = selected ? scheme.onPrimaryContainer : scheme.primary;
    final fillColor = selected
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;

    // Keep the selection ring outside the clipped image. Putting border +
    // clipBehavior on the same box clips the stroke (and images can paint over it).
    final borderWidth = selected ? _selectedBorderWidth : 0.0;
    final innerRadius = _deflateBorderRadius(outerRadius, borderWidth);

    final content = url != null && isImage
        ? Image.network(
            url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, _, _) => Center(
              child: Icon(fallbackIcon, size: size * 0.45, color: iconColor),
            ),
          )
        : Center(
            child: Icon(fallbackIcon, size: size * 0.45, color: iconColor),
          );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: outerRadius,
        border: selected
            ? Border.all(
                color: scheme.primary.withValues(alpha: 0.55),
                width: _selectedBorderWidth,
              )
            : null,
      ),
      // Inset the clipped body so the ring sits fully outside it.
      padding: EdgeInsets.all(borderWidth),
      child: ClipRRect(
        borderRadius: innerRadius,
        child: ColoredBox(color: fillColor, child: content),
      ),
    );
  }
}

BorderRadius _deflateBorderRadius(BorderRadius radius, double delta) {
  if (delta <= 0) return radius;
  Radius deflate(Radius corner) {
    final x = (corner.x - delta).clamp(0.0, double.infinity);
    final y = (corner.y - delta).clamp(0.0, double.infinity);
    return Radius.elliptical(x, y);
  }

  return BorderRadius.only(
    topLeft: deflate(radius.topLeft),
    topRight: deflate(radius.topRight),
    bottomLeft: deflate(radius.bottomLeft),
    bottomRight: deflate(radius.bottomRight),
  );
}

/// Compact chip showing an attached cloud file with optional remove action.
class CloudFileChip extends StatelessWidget {
  const CloudFileChip({
    super.key,
    required this.file,
    this.displayUrl,
    this.onPressed,
    this.onRemove,
  });

  final IDisplayableCloudFile file;
  final String? displayUrl;
  final VoidCallback? onPressed;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isImage = file.mimeType.startsWith('image/');
    return InputChip(
      avatar: isImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                displayUrl ?? cloudFileDisplayUrl(file),
                width: 24,
                height: 24,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Icon(Symbols.attach_file, size: 16),
              ),
            )
          : const Icon(Symbols.attach_file, size: 16),
      label: Text(
        file.name.isEmpty ? file.id : file.name,
        overflow: TextOverflow.ellipsis,
      ),
      onPressed: onPressed,
      onDeleted: onRemove,
      deleteIconColor: scheme.onSurfaceVariant,
    );
  }
}

/// Opens a sheet to pick and upload local files to Solar Network Drive.
///
/// Inspired by Island's `CloudFilePicker`. Supports upload and link attachment
/// of existing workspace files. Returns [SnCloudFile] (single) or
/// `List<SnCloudFile>` when [allowMultiple].
///
/// When [workspaceId] is set, uploads are charged to the workspace plan and
/// stored with that `workspace_id` (see WORKSPACE_FILES.md).
Future<T?> showCloudFilePicker<T>({
  required BuildContext context,
  required WidgetRef ref,
  bool allowMultiple = false,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  String? usage,
  String? workspaceId,
  String? parentId,
  bool indexed = true,
  bool allowLinkAttachment = true,
  String title = 'Upload file',
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CloudFilePickerSheet(
      allowMultiple: allowMultiple,
      type: type,
      allowedExtensions: allowedExtensions,
      usage: usage,
      workspaceId: workspaceId,
      parentId: parentId,
      indexed: indexed,
      allowLinkAttachment: allowLinkAttachment,
      title: title,
    ),
  );
}

/// Opens the OS file picker immediately and uploads selected files to Drive.
///
/// Unlike [showCloudFilePicker], this does not show a sheet with link-attachment
/// options. Returns `null` if the user cancels. On failure, shows a snackbar
/// and returns `null`.
Future<List<SnCloudFile>?> uploadLocalCloudFiles(
  WidgetRef ref, {
  bool allowMultiple = true,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  String? usage,
  String? workspaceId,
  String? parentId,
  bool indexed = true,
  void Function(String status, double? progress)? onProgress,
}) async {
  List<PlatformFile> selected = const [];
  try {
    // file_picker 12: static pickFiles / pickFile; load via readAsBytes().
    if (allowMultiple) {
      final result = await FilePicker.pickFiles(
        type: type,
        allowedExtensions: allowedExtensions,
      );
      selected = result?.files ?? const [];
    } else {
      final file = await FilePicker.pickFile(
        type: type,
        allowedExtensions: allowedExtensions,
      );
      selected = file == null ? const [] : [file];
    }
  } catch (error, stack) {
    _uploadLog.warning('File picker failed', error, stack);
    showSnackBar('Could not open the file picker: $error');
    return null;
  }
  if (selected.isEmpty) {
    _uploadLog.info('File picker cancelled or returned no files.');
    return null;
  }

  final resolvedWorkspaceId =
      workspaceId ?? (await ref.read(selectedWorkspaceProvider.future))?.id;
  if (resolvedWorkspaceId == null || resolvedWorkspaceId.isEmpty) {
    showSnackBar(
      'Select a workspace first. SolWatt only uses workspace Drive.',
    );
    return null;
  }
  final tasks = ref.read(appTasksProvider.notifier);

  try {
    final client = ref.read(wattEngineClientProvider);
    final uploaded = <SnCloudFile>[];
    for (var i = 0; i < selected.length; i++) {
      final platformFile = selected[i];
      final bytes = await platformFile.readAsBytes();
      if (bytes.isEmpty) {
        throw const OAuthException(
          'Could not read the selected file. Try another file.',
        );
      }

      final taskId = tasks.addTask(
        title: platformFile.name,
        type: AppTaskType.driveUpload,
        status: AppTaskStatus.inProgress,
        metadata: {
          'fileSize': bytes.length,
          'transmissionProgress': 0.0,
          'workspaceId': resolvedWorkspaceId,
        },
      );
      tasks.updateTask(
        taskId,
        statusMessage: 'Uploading ${i + 1} of ${selected.length}…',
        progress: 0,
      );

      onProgress?.call(
        'Uploading ${i + 1} of ${selected.length}…',
        i / selected.length,
      );
      _uploadLog.info(
        'Uploading ${platformFile.name} '
        '(${bytes.length} bytes, workspace=$resolvedWorkspaceId)',
      );
      try {
        final cloudFile = await client.uploadCloudFile(
          bytes: bytes,
          fileName: platformFile.name,
          usage: usage,
          workspaceId: resolvedWorkspaceId,
          parentId: parentId,
          indexed: indexed,
          onSendProgress: (sent, total) {
            if (total <= 0) return;
            final fileProgress = sent / total;
            final overall = (i + fileProgress) / selected.length;
            tasks.updateTask(
              taskId,
              progress: fileProgress.clamp(0.0, 1.0),
              statusMessage: 'Uploading ${i + 1} of ${selected.length}…',
              metadata: {
                'fileSize': bytes.length,
                'transmissionProgress': fileProgress,
                'workspaceId': resolvedWorkspaceId,
              },
            );
            onProgress?.call(
              'Uploading ${i + 1} of ${selected.length}…',
              overall,
            );
          },
        );
        tasks.updateTask(
          taskId,
          status: AppTaskStatus.completed,
          progress: 1,
          statusMessage: 'Uploaded',
          result: {'fileId': cloudFile.id},
          metadata: {
            'fileSize': bytes.length,
            'transmissionProgress': 1.0,
            'workspaceId': resolvedWorkspaceId,
          },
        );
        uploaded.add(cloudFile);
      } catch (error) {
        tasks.updateTask(
          taskId,
          status: AppTaskStatus.failed,
          errorMessage: driveApiErrorMessage(error),
          statusMessage: 'Failed',
        );
        rethrow;
      }
    }
    invalidateWorkspaceDrive(ref);
    return uploaded;
  } catch (error, stack) {
    _uploadLog.warning('Upload failed', error, stack);
    showSnackBar(driveApiErrorMessage(error));
    return null;
  }
}

/// Convenience: pick a single image and return it as [SnCloudFileReference].
///
/// Defaults to [indexed] `false` so icons/backgrounds stay out of the folder
/// tree (workspace unindexed Drive), matching Island decoration uploads.
Future<SnCloudFileReference?> pickCloudImageReference(
  BuildContext context,
  WidgetRef ref, {
  String? usage,
  String? workspaceId,
  String title = 'Choose image',
  bool indexed = false,
}) async {
  final file = await showCloudFilePicker<SnCloudFile>(
    context: context,
    ref: ref,
    type: FileType.image,
    usage: usage,
    workspaceId: workspaceId,
    title: title,
    indexed: indexed,
  );
  if (file == null) return null;
  return cloudFileToReference(file);
}

/// Opens Island-style link attachment: browse recent / folders / paste file ID.
///
/// Returns a single [SnCloudFile], or `List<SnCloudFile>` when [allowMultiple]
/// selection mode is confirmed.
Future<T?> showWorkspaceLinkAttachment<T>({
  required BuildContext context,
  required WidgetRef ref,
  bool allowMultiple = false,
  String? workspaceId,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _WorkspaceLinkAttachmentSheet(
      allowMultiple: allowMultiple,
      workspaceId: workspaceId,
    ),
  );
}

class _CloudFilePickerSheet extends ConsumerStatefulWidget {
  const _CloudFilePickerSheet({
    required this.allowMultiple,
    required this.type,
    required this.allowedExtensions,
    required this.usage,
    required this.workspaceId,
    required this.parentId,
    required this.indexed,
    required this.allowLinkAttachment,
    required this.title,
  });

  final bool allowMultiple;
  final FileType type;
  final List<String>? allowedExtensions;
  final String? usage;
  final String? workspaceId;
  final String? parentId;
  final bool indexed;
  final bool allowLinkAttachment;
  final String title;

  @override
  ConsumerState<_CloudFilePickerSheet> createState() =>
      _CloudFilePickerSheetState();
}

class _CloudFilePickerSheetState extends ConsumerState<_CloudFilePickerSheet> {
  bool _busy = false;
  double? _progress;
  String? _status;

  Future<String?> _resolveWorkspaceId() async {
    if (widget.workspaceId != null && widget.workspaceId!.isNotEmpty) {
      return widget.workspaceId;
    }
    final selected = await ref.read(selectedWorkspaceProvider.future);
    return selected?.id;
  }

  Future<void> _pickAndUpload() async {
    final workspaceId = await _resolveWorkspaceId();
    final uploaded = await uploadLocalCloudFiles(
      ref,
      allowMultiple: widget.allowMultiple,
      type: widget.type,
      allowedExtensions: widget.allowedExtensions,
      usage: widget.usage,
      workspaceId: workspaceId,
      parentId: widget.parentId,
      indexed: widget.indexed,
      onProgress: (status, progress) {
        if (!mounted) return;
        setState(() {
          _busy = true;
          _status = status;
          _progress = progress;
        });
      },
    );

    if (!mounted) return;
    if (uploaded == null || uploaded.isEmpty) {
      setState(() {
        _busy = false;
        _progress = null;
        _status = null;
      });
      return;
    }
    if (widget.allowMultiple) {
      Navigator.pop(context, uploaded);
    } else {
      Navigator.pop(context, uploaded.first);
    }
  }

  Future<void> _pickLinkAttachment() async {
    final workspaceId = await _resolveWorkspaceId();
    if (!mounted) return;
    if (widget.allowMultiple) {
      final files = await showWorkspaceLinkAttachment<List<SnCloudFile>>(
        context: context,
        ref: ref,
        allowMultiple: true,
        workspaceId: workspaceId,
      );
      if (files == null || files.isEmpty || !mounted) return;
      Navigator.pop(context, files);
    } else {
      final file = await showWorkspaceLinkAttachment<SnCloudFile>(
        context: context,
        ref: ref,
        workspaceId: workspaceId,
      );
      if (file == null || !mounted) return;
      Navigator.pop(context, file);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasWorkspaceScope =
        widget.workspaceId != null ||
        ref.watch(selectedWorkspaceProvider).value != null;

    return SheetScaffold(
      titleText: widget.title,
      heightFactor: 0.45,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          Text(
            widget.allowMultiple
                ? hasWorkspaceScope
                      ? 'Select files to upload to this workspace, or link existing workspace files.'
                      : 'Select one or more files to upload to your Drive.'
                : hasWorkspaceScope
                ? 'Select a file to upload to this workspace, or link an existing workspace file.'
                : 'Select a file to upload to your Drive.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          if (_busy) ...[
            if (_status != null) Text(_status!, style: text.bodySmall),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 20),
          ],
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                if (widget.allowLinkAttachment)
                  ListTile(
                    leading: const Icon(Symbols.link),
                    title: const Text('Link existing file'),
                    subtitle: Text(
                      hasWorkspaceScope
                          ? 'Browse workspace Drive files'
                          : 'Browse files already on Drive',
                    ),
                    enabled: !_busy,
                    onTap: _busy ? null : _pickLinkAttachment,
                  ),
                ListTile(
                  leading: Icon(
                    widget.type == FileType.image
                        ? Symbols.photo
                        : Symbols.upload_file,
                  ),
                  title: Text(
                    widget.type == FileType.image
                        ? 'Choose image'
                        : 'Choose file',
                  ),
                  subtitle: Text(
                    hasWorkspaceScope
                        ? 'Upload from this device (workspace storage)'
                        : 'Requires an active workspace',
                  ),
                  enabled: !_busy && hasWorkspaceScope,
                  onTap: _busy || !hasWorkspaceScope ? null : _pickAndUpload,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceLinkAttachmentSheet extends ConsumerStatefulWidget {
  const _WorkspaceLinkAttachmentSheet({
    required this.allowMultiple,
    required this.workspaceId,
  });

  final bool allowMultiple;
  final String? workspaceId;

  @override
  ConsumerState<_WorkspaceLinkAttachmentSheet> createState() =>
      _WorkspaceLinkAttachmentSheetState();
}

class _WorkspaceLinkAttachmentSheetState
    extends ConsumerState<_WorkspaceLinkAttachmentSheet> {
  bool _selectionMode = false;
  final Map<String, SnCloudFile> _selected = {};
  final _idController = TextEditingController();
  String? _manualError;
  bool _manualBusy = false;

  /// Folder path as stack of (id, name). Empty = workspace root.
  final List<({String id, String name})> _folderStack = [];

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  void _toggleSelection(SnCloudFile file) {
    setState(() {
      if (_selected.containsKey(file.id)) {
        _selected.remove(file.id);
      } else {
        _selected[file.id] = file;
      }
    });
  }

  void _handleSelected(SnCloudFile file) {
    if (_selectionMode) {
      _toggleSelection(file);
      return;
    }
    Navigator.pop(context, file);
  }

  Future<void> _submitManualId() async {
    final fileId = _idController.text.trim();
    if (fileId.isEmpty) {
      setState(() => _manualError = 'File ID cannot be empty.');
      return;
    }
    setState(() {
      _manualBusy = true;
      _manualError = null;
    });
    try {
      final cloudFile = await ref
          .read(wattEngineClientProvider)
          .getCloudFileInfo(fileId);
      if (!mounted) return;
      if (_selectionMode) {
        _toggleSelection(cloudFile);
        setState(() => _manualBusy = false);
      } else {
        Navigator.pop(context, cloudFile);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _manualBusy = false;
        _manualError = 'Could not load file: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      heightFactor: 0.7,
      titleText: 'Link attachment',
      actions: [
        if (widget.allowMultiple && _selectionMode)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text('${_selected.length} selected'),
            ),
          ),
        if (widget.allowMultiple && _selectionMode)
          TextButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.pop(
                    context,
                    _selected.values.toList(growable: false),
                  ),
            child: const Text('Done'),
          ),
        if (widget.allowMultiple)
          IconButton(
            onPressed: () => setState(() {
              _selectionMode = !_selectionMode;
              if (!_selectionMode) _selected.clear();
            }),
            tooltip: _selectionMode ? 'Exit selection' : 'Select multiple',
            icon: Icon(
              _selectionMode
                  ? Symbols.check_box_outline_blank
                  : Symbols.select_check_box,
            ),
          ),
      ],
      child: DefaultTabController(
        length: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Recent'),
                Tab(text: 'Folders'),
                Tab(text: 'By ID'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _RecentWorkspaceFiles(
                    workspaceId: widget.workspaceId,
                    selectedIds: _selected.keys.toSet(),
                    selectionMode: _selectionMode,
                    onSelected: _handleSelected,
                    onToggle: _toggleSelection,
                  ),
                  _WorkspaceFolderBrowser(
                    workspaceId: widget.workspaceId,
                    folderStack: _folderStack,
                    selectedIds: _selected.keys.toSet(),
                    selectionMode: _selectionMode,
                    onSelected: _handleSelected,
                    onToggle: _toggleSelection,
                    onNavigate: (stack) => setState(() {
                      _folderStack
                        ..clear()
                        ..addAll(stack);
                    }),
                  ),
                  _ManualFileIdForm(
                    controller: _idController,
                    errorText: _manualError,
                    busy: _manualBusy,
                    onSubmit: _submitManualId,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentWorkspaceFiles extends ConsumerWidget {
  const _RecentWorkspaceFiles({
    required this.workspaceId,
    required this.selectedIds,
    required this.selectionMode,
    required this.onSelected,
    required this.onToggle,
  });

  final String? workspaceId;
  final Set<String> selectedIds;
  final bool selectionMode;
  final ValueChanged<SnCloudFile> onSelected;
  final ValueChanged<SnCloudFile> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(workspaceFilesProvider);
    return files.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error.toString()),
        ),
      ),
      data: (items) {
        final filtered = workspaceId == null
            ? items
            : items
                  .where((e) => e.belongsToWorkspace(workspaceId!))
                  .toList(growable: false);
        if (filtered.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No workspace files yet. Upload one first.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: filtered.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final entry = filtered[index];
            final selected = selectedIds.contains(entry.id);
            return ListTile(
              leading: CloudFileAvatar(
                file: entry.file,
                fallbackIcon: entry.isFolder
                    ? Symbols.folder
                    : Symbols.description,
                selected: selected,
              ),
              selected: selected,
              title: Text(
                entry.name.isEmpty ? 'Untitled' : entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                entry.isFolder ? 'Folder' : formatByteSize(entry.size),
              ),
              trailing: selectionMode
                  ? Icon(
                      selected
                          ? Symbols.check_circle
                          : Symbols.radio_button_unchecked,
                    )
                  : null,
              onTap: () =>
                  selectionMode ? onToggle(entry.file) : onSelected(entry.file),
            );
          },
        );
      },
    );
  }
}

class _WorkspaceFolderBrowser extends ConsumerWidget {
  const _WorkspaceFolderBrowser({
    required this.workspaceId,
    required this.folderStack,
    required this.selectedIds,
    required this.selectionMode,
    required this.onSelected,
    required this.onToggle,
    required this.onNavigate,
  });

  final String? workspaceId;
  final List<({String id, String name})> folderStack;
  final Set<String> selectedIds;
  final bool selectionMode;
  final ValueChanged<SnCloudFile> onSelected;
  final ValueChanged<SnCloudFile> onToggle;
  final ValueChanged<List<({String id, String name})>> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parentId = folderStack.isEmpty ? '' : folderStack.last.id;
    final children = ref.watch(workspaceFolderChildrenProvider(parentId));
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              TextButton(
                onPressed: folderStack.isEmpty
                    ? null
                    : () => onNavigate(const []),
                child: const Text('Root'),
              ),
              for (var i = 0; i < folderStack.length; i++) ...[
                Icon(
                  Symbols.chevron_right,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                TextButton(
                  onPressed: i == folderStack.length - 1
                      ? null
                      : () => onNavigate(folderStack.sublist(0, i + 1)),
                  child: Text(folderStack[i].name),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: children.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text(error.toString())),
            data: (items) {
              final filtered = workspaceId == null
                  ? items
                  : items
                        .where((e) => e.belongsToWorkspace(workspaceId!))
                        .toList(growable: false);
              if (filtered.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'This folder is empty.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final entry = filtered[index];
                  final selected = selectedIds.contains(entry.id);
                  if (entry.isFolder) {
                    return ListTile(
                      leading: Icon(
                        selected ? Symbols.check_box : Symbols.folder,
                      ),
                      selected: selected,
                      title: Text(
                        entry.name.isEmpty ? 'Untitled' : entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: const Text('Folder'),
                      trailing: IconButton(
                        icon: Icon(
                          selectionMode
                              ? (selected
                                    ? Symbols.check_box
                                    : Symbols.check_box_outline_blank)
                              : Symbols.add,
                        ),
                        tooltip: selectionMode ? 'Select' : 'Link this folder',
                        onPressed: () => selectionMode
                            ? onToggle(entry.file)
                            : onSelected(entry.file),
                      ),
                      onTap: () => onNavigate([
                        ...folderStack,
                        (id: entry.id, name: entry.name),
                      ]),
                    );
                  }
                  return ListTile(
                    leading: Icon(
                      selected ? Symbols.check_box : Symbols.description,
                    ),
                    selected: selected,
                    title: Text(
                      entry.name.isEmpty ? 'Untitled' : entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(formatByteSize(entry.size)),
                    onTap: () => selectionMode
                        ? onToggle(entry.file)
                        : onSelected(entry.file),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ManualFileIdForm extends StatelessWidget {
  const _ManualFileIdForm({
    required this.controller,
    required this.errorText,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String? errorText;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      children: [
        TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'File ID',
            helperText:
                'Paste a cloud file ID to attach an existing Drive object.',
            helperMaxLines: 3,
            errorText: errorText,
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          onSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: busy ? null : onSubmit,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Symbols.add),
            label: const Text('Add'),
          ),
        ),
      ],
    );
  }
}

/// Human-readable byte size (Island-style helper, local copy).
String formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
