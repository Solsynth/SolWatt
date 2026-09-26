import 'package:flutter/material.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/utils/file_types.dart';
import 'package:solwatt/core/widgets/content/cloud_file_lightbox.dart';
import 'package:solwatt/drive/widgets/cloud_files.dart';
import 'package:solwatt/ui/cloud_files.dart';

/// Attachments where they can show themselves.
///
/// Pictures and videos render an in-place preview — the Drive thumbnail, sized
/// by the file's own aspect ratio — so an attachment list reads as a strip of
/// what arrived instead of a row of filenames. Everything else (documents,
/// archives, audio) stays the compact chip: a PDF has no preview worth the
/// space. Tapping follows the file: images open in [CloudFileLightbox] with the
/// rest of the list as the gallery, and any other type opens the Drive file
/// detail page, where a video plays.
class CloudFileAttachmentList extends StatelessWidget {
  const CloudFileAttachmentList({
    super.key,
    required this.files,
    this.workspaceId,
    this.previewHeight = 132,
    this.maxPreviewWidth = 232,
  });

  final List<IDisplayableCloudFile> files;

  /// Workspace the files live in, required by the gateway for workspace files.
  final String? workspaceId;

  /// Height of a media preview; its width follows the file's aspect ratio.
  final double previewHeight;

  /// Widest a preview may get, so a panorama cannot swallow the row.
  final double maxPreviewWidth;

  bool _showsPreview(IDisplayableCloudFile file) =>
      isImageFile(file) || isVideoFile(file);

  void _open(BuildContext context, IDisplayableCloudFile file) =>
      openCloudFile(context, file, gallery: files, workspaceId: workspaceId);

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final file in files)
          if (_showsPreview(file))
            _CloudFilePreview(
              file: file,
              workspaceId: workspaceId,
              height: previewHeight,
              maxWidth: maxPreviewWidth,
              onTap: () => _open(context, file),
            )
          else
            CloudFileChip(
              file: file,
              onPressed: () => _open(context, file),
            ),
      ],
    );
  }
}

/// One thumbnail of [CloudFileAttachmentList].
class _CloudFilePreview extends StatelessWidget {
  const _CloudFilePreview({
    required this.file,
    required this.workspaceId,
    required this.height,
    required this.maxWidth,
    required this.onTap,
  });

  final IDisplayableCloudFile file;
  final String? workspaceId;
  final double height;
  final double maxWidth;
  final VoidCallback onTap;

  /// Aspect ratios outside this range are clamped: a 1×2000 crop should not
  /// render as a sliver.
  static const _minRatio = 0.6;
  static const _maxRatio = 2.4;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = (file.ratio ?? 1.0).clamp(_minRatio, _maxRatio);
    final isVideo = isVideoFile(file);

    return Tooltip(
      message: file.name,
      child: SizedBox(
        height: height,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: AspectRatio(
            aspectRatio: ratio,
            child: Material(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: isVideo
                    ? CloudVideoWidget(item: file, workspaceId: workspaceId)
                    : CloudImageWidget(
                        file: file,
                        fit: BoxFit.cover,
                        workspaceId: workspaceId,
                        imageOnly: true,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
