import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/network.dart';

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = borderRadius ?? BorderRadius.circular(size * 0.28);
    final url = file == null ? null : cloudFileDisplayUrl(file!);
    final isImage = file?.mimeType.startsWith('image/') ?? false;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: radius,
        border: selected
            ? Border.all(color: scheme.primary.withValues(alpha: 0.5))
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && isImage
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(
                fallbackIcon,
                size: size * 0.45,
                color: selected ? scheme.onPrimaryContainer : scheme.primary,
              ),
            )
          : Icon(
              fallbackIcon,
              size: size * 0.45,
              color: selected ? scheme.onPrimaryContainer : scheme.primary,
            ),
    );
  }
}

/// Compact chip showing an attached cloud file with optional remove action.
class CloudFileChip extends StatelessWidget {
  const CloudFileChip({
    super.key,
    required this.file,
    this.onRemove,
  });

  final IDisplayableCloudFile file;
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
                cloudFileDisplayUrl(file),
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
      onDeleted: onRemove,
      deleteIconColor: scheme.onSurfaceVariant,
    );
  }
}

/// Opens a sheet to pick and upload local files to Solar Network Drive.
///
/// Inspired by Island's `CloudFilePicker`, simplified for SolWatt desktop use.
/// Returns [SnCloudFile] (single) or `List<SnCloudFile>` when [allowMultiple].
Future<T?> showCloudFilePicker<T>({
  required BuildContext context,
  required WidgetRef ref,
  bool allowMultiple = false,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  String? usage,
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
      title: title,
    ),
  );
}

/// Convenience: pick a single image and return it as [SnCloudFileReference].
Future<SnCloudFileReference?> pickCloudImageReference(
  BuildContext context,
  WidgetRef ref, {
  String? usage,
  String title = 'Choose image',
}) async {
  final file = await showCloudFilePicker<SnCloudFile>(
    context: context,
    ref: ref,
    type: FileType.image,
    usage: usage,
    title: title,
  );
  if (file == null) return null;
  return cloudFileToReference(file);
}

class _CloudFilePickerSheet extends ConsumerStatefulWidget {
  const _CloudFilePickerSheet({
    required this.allowMultiple,
    required this.type,
    required this.allowedExtensions,
    required this.usage,
    required this.title,
  });

  final bool allowMultiple;
  final FileType type;
  final List<String>? allowedExtensions;
  final String? usage;
  final String title;

  @override
  ConsumerState<_CloudFilePickerSheet> createState() =>
      _CloudFilePickerSheetState();
}

class _CloudFilePickerSheetState extends ConsumerState<_CloudFilePickerSheet> {
  bool _busy = false;
  double? _progress;
  String? _status;

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: widget.allowMultiple,
      type: widget.type,
      allowedExtensions: widget.allowedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Uploading…';
    });

    try {
      final client = ref.read(wattEngineClientProvider);
      final uploaded = <SnCloudFile>[];
      for (var i = 0; i < result.files.length; i++) {
        final platformFile = result.files[i];
        final bytes = platformFile.bytes;
        if (bytes == null) {
          throw const OAuthException(
            'Could not read the selected file. Try another file.',
          );
        }
        setState(() {
          _status = 'Uploading ${i + 1} of ${result.files.length}…';
          _progress = i / result.files.length;
        });
        final cloudFile = await client.uploadCloudFile(
          bytes: bytes,
          fileName: platformFile.name,
          usage: widget.usage,
          onSendProgress: (sent, total) {
            if (total <= 0 || !mounted) return;
            final fileProgress = sent / total;
            setState(() {
              _progress = (i + fileProgress) / result.files.length;
            });
          },
        );
        uploaded.add(cloudFile);
      }
      if (!mounted) return;
      if (widget.allowMultiple) {
        Navigator.pop(context, uploaded);
      } else {
        Navigator.pop(context, uploaded.isNotEmpty ? uploaded.first : null);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _status = null;
      });
      showSnackBar(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SheetScaffold(
      titleText: widget.title,
      heightFactor: 0.45,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          Text(
            widget.allowMultiple
                ? 'Select one or more files to upload to your Drive.'
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
                  subtitle: const Text('Upload from this device'),
                  enabled: !_busy,
                  onTap: _busy ? null : _pickAndUpload,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
