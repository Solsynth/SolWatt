import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:solwatt/core/config.dart';
import 'package:solwatt/core/network.dart';
import 'package:solwatt/drive/file_permissions.dart';
import 'package:solwatt/shared/widgets/alert.dart';
import 'package:solwatt/shared/widgets/content/audio.dart';
import 'package:solwatt/shared/widgets/content/video.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart';
import 'package:solwatt/drive/widgets/cloud_files.dart';
import 'package:solwatt/core/widgets/content/exif_info_overlay.dart';
import 'package:solwatt/core/widgets/content/file_info_sheet.dart';
import 'package:solwatt/core/widgets/content/image_control_overlay.dart';
import 'package:solwatt/core/widgets/content/image_quality_loading.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:photo_view/photo_view.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';
import 'package:solwatt/ui/markdown.dart';

/// Text file viewer with an optional in-place editor.
///
/// Markdown files render through [MarkdownTextContent] and can be flipped to
/// their source. Saving replaces the file's bytes through
/// `PUT /drive/files/:id/content` (DysonFS `PUT /api/files/:id/content`): the
/// backing object is overwritten in place, so the file keeps its id, parent and
/// permissions, and the server queues a rehash to refresh hash/MIME/derived
/// content. The server stays the authority on writes — a rejected save (no
/// write permission, file locked by another editor) is surfaced, not hidden.
class TextFileContent extends HookConsumerWidget {
  final IDisplayableCloudFile item;

  /// Workspace the file is stored under, when it is a workspace file. Without
  /// it the gateway cannot resolve a workspace-scoped Drive file.
  final String? workspaceId;

  /// Whether the editor is offered. Read-only surfaces (attachment previews)
  /// pass `false` and keep the plain viewer.
  final bool editable;

  /// Handed the refreshed metadata after a successful save, for callers that
  /// hold their own copy of the file (tabs, inspector, list rows).
  final ValueChanged<SnCloudFile>? onSaved;

  const TextFileContent({
    super.key,
    required this.item,
    this.workspaceId,
    this.editable = true,
    this.onSaved,
  });

  bool get _isMarkdown {
    if (item.mimeType == 'text/markdown') return true;
    final name = item.name.toLowerCase();
    return name.endsWith('.md') || name.endsWith('.markdown');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(serverUrlProvider);
    final uri = Uri.parse('$serverUrl/drive/files/${item.id}')
        .replace(
          queryParameters: {
            if (workspaceId != null && workspaceId!.isNotEmpty)
              'workspace_id': workspaceId!,
          },
        )
        .toString();
    final client = ref.read(solarNetworkClientProvider);

    final text = useState<String?>(null);
    final loadError = useState<Object?>(null);
    final isLoading = useState(true);
    final isEditing = useState(false);
    final isSaving = useState(false);
    final showSource = useState(false);
    final controller = useTextEditingController();
    // Rebuild on every keystroke so the dirty marker and save button follow.
    useListenable(controller);

    useEffect(() {
      var cancelled = false;
      isLoading.value = true;
      loadError.value = null;
      client.dio
          .get<String>(uri, options: Options(responseType: ResponseType.plain))
          .then((response) {
            if (cancelled) return;
            final body = response.data ?? '';
            text.value = body;
            controller.text = body;
            isLoading.value = false;
          })
          .catchError((Object error) {
            if (cancelled) return;
            loadError.value = error;
            isLoading.value = false;
          });
      return () => cancelled = true;
    }, [uri]);

    Future<void> save() async {
      final content = controller.text;
      isSaving.value = true;
      try {
        final response = await client.dio.put<Map<String, dynamic>>(
          uri,
          data: content,
          options: Options(contentType: 'text/plain; charset=utf-8'),
        );
        text.value = content;
        isEditing.value = false;
        final payload = response.data;
        if (payload != null) {
          final updated = SnCloudFile.fromJson(payload);
          ref.invalidate(driveFileInfoProvider(updated.id));
          onSaved?.call(updated);
        }
        showSnackBar('fileSaved'.tr());
      } catch (error) {
        showSnackBar('fileSaveFailed'.tr(args: [_driveErrorLabel(error)]));
      } finally {
        isSaving.value = false;
      }
    }

    Future<void> discard() async {
      if (controller.text != (text.value ?? '')) {
        final confirmed = await showConfirmAlert(
          'discardChangesPrompt'.tr(),
          'discardChanges'.tr(),
          isDanger: true,
        );
        if (!confirmed) return;
      }
      controller.text = text.value ?? '';
      isEditing.value = false;
    }

    if (isLoading.value) {
      return const Center(child: CircularProgressIndicator());
    }
    if (loadError.value != null) {
      return Center(
        child: Text(
          'fileContentLoadFailed'.tr(args: [_driveErrorLabel(loadError.value!)]),
        ),
      );
    }

    final content = text.value ?? '';
    final isDirty = controller.text != content;

    Widget viewer;
    if (isEditing.value) {
      viewer = TextField(
        controller: controller,
        expands: true,
        maxLines: null,
        autofocus: true,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(16),
        ),
      );
    } else if (_isMarkdown && !showSource.value) {
      viewer = SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: MarkdownTextContent(content: content),
      );
    } else {
      viewer = SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: SelectableText(
          content,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final showToolbar = editable || _isMarkdown;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showToolbar)
          Material(
            color: scheme.surfaceContainerLow,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                ),
              ),
              child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    if (isEditing.value) ...[
                      const Gap(8),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        tooltip: 'cancel'.tr(),
                        onPressed: isSaving.value ? null : discard,
                        icon: const Icon(Symbols.close),
                      ),
                    ] else if (_isMarkdown)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        tooltip: showSource.value
                            ? 'markdownPreview'.tr()
                            : 'markdownSource'.tr(),
                        onPressed: () => showSource.value = !showSource.value,
                        icon: Icon(
                          showSource.value ? Symbols.visibility : Symbols.code,
                        ),
                      ),
                    const Spacer(),
                    if (isEditing.value) ...[
                      if (isDirty)
                        Tooltip(
                          message: 'unsavedChanges'.tr(),
                          child: Icon(
                            Symbols.circle,
                            size: 8,
                            color: scheme.primary,
                          ),
                        ),
                      const Gap(8),
                      TextButton.icon(
                        onPressed: isSaving.value ? null : save,
                        icon: isSaving.value
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Symbols.save, size: 18),
                        label: Text('save'.tr()),
                      ),
                    ] else if (editable)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        tooltip: 'editFileContent'.tr(),
                        onPressed: () => isEditing.value = true,
                        icon: const Icon(Symbols.edit),
                      ),
                    const Gap(4),
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: viewer),
      ],
    );

    if (!editable) return body;
    // ⌘S/Ctrl+S saves without leaving the keyboard.
    void saveNow() {
      if (isEditing.value && !isSaving.value) save();
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): saveNow,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): saveNow,
      },
      child: body,
    );
  }
}

/// Human-readable label for a failed drive request: the server's `error` field
/// when present, else the HTTP status, else the raw error.
String _driveErrorLabel(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
    final status = error.response?.statusCode;
    if (status != null) return 'HTTP $status';
  }
  return error.toString();
}

class ImageFileContent extends HookConsumerWidget {
  final IDisplayableCloudFile item;

  /// Workspace the file is stored under, when it is a workspace file. Without
  /// it the gateway cannot resolve a workspace-scoped Drive file.
  final String? workspaceId;
  final double bottomInset;

  /// Zoom/rotation controller owned by the caller. The lightbox passes its own
  /// so it can tell a zoomed image (which pans on drag) from a resting one
  /// (which may be swiped away).
  final PhotoViewController? controller;

  /// Scale-state controller, exposed for the same reason as [controller].
  final PhotoViewScaleStateController? scaleStateController;

  const ImageFileContent({
    required this.item,
    this.workspaceId,
    this.bottomInset = 0,
    this.controller,
    this.scaleStateController,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownedController = useMemoized(() => PhotoViewController(), []);
    final photoViewController = controller ?? ownedController;
    final rotation = useState(0);

    final hasExifData = ExifInfoOverlay.precheck(item);
    final showOriginal = useState(false);
    final showExif = useState(hasExifData);
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final serverUrl = ref.watch(serverUrlProvider);
    final imageProvider = CloudImageWidget.provider(
      file: item,
      serverUrl: serverUrl,
      original: showOriginal.value,
      workspaceId: workspaceId,
    );
    final qualityLoad = useImageQualityLoad(
      provider: imageProvider,
      showOriginal: showOriginal.value,
      reloadToken: item.id,
    );

    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Positioned.fill(
            child: Listener(
              onPointerSignal: (pointerSignal) {
                try {
                  final delta =
                      (pointerSignal as dynamic).scrollDelta.dy as double?;
                  if (delta != null && delta != 0) {
                    final currentScale = photoViewController.scale ?? 1.0;
                    final newScale = delta > 0
                        ? currentScale * 0.9
                        : currentScale * 1.1;
                    final clampedScale = newScale.clamp(0.1, 10.0);
                    photoViewController.scale = clampedScale;
                  }
                } catch (_) {
                  // Ignore non-scroll events.
                }
              },
              child: PhotoView(
                backgroundDecoration: const BoxDecoration(
                  color: Colors.transparent,
                ),
                controller: photoViewController,
                scaleStateController: scaleStateController,
                imageProvider: imageProvider,
                customSize: Size(constraints.maxWidth, constraints.maxHeight),
                basePosition: Alignment.center,
                filterQuality: FilterQuality.high,
                minScale: PhotoViewComputedScale.contained * 0.9,
                maxScale: PhotoViewComputedScale.covered * 3,
                initialScale: PhotoViewComputedScale.contained,
                gaplessPlayback: true,
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ImageQualityProgressBar(
              isLoading: qualityLoad.isLoading,
              progress: qualityLoad.progress,
              loadingOriginal: showOriginal.value,
              // Body already sits below the app bar / status area.
              avoidTopSafeArea: false,
            ),
          ),
          if (showExif.value)
            Positioned(
              bottom: safeBottom + 68 + bottomInset,
              left: 16,
              right: 16,
              child: ExifInfoOverlay(item: item),
            ),
          ImageControlOverlay(
            photoViewController: photoViewController,
            rotation: rotation,
            showOriginal: showOriginal.value,
            isQualityLoading: qualityLoad.isLoading,
            onToggleQuality: () {
              qualityLoad.beginLoad();
              showOriginal.value = !showOriginal.value;
            },
            showExifInfo: showExif.value,
            onToggleExif: () {
              showExif.value = !showExif.value;
            },
            hasExifData: hasExifData,
            bottomOffset: bottomInset,
          ),
        ],
      ),
    );
  }
}

class VideoFileContent extends HookConsumerWidget {
  final SnCloudFile item;
  final String uri;
  final double bottomInset;

  const VideoFileContent({
    required this.item,
    required this.uri,
    this.bottomInset = 0,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var ratio = item.ratio;
    if (ratio == 0 || ratio == null) ratio = 16 / 9;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = math.max(
          160.0,
          constraints.maxHeight - bottomInset - 24,
        );
        final availableWidth = constraints.maxWidth - 32;
        final widthByHeight = availableHeight * ratio!;
        final heightByWidth = availableWidth / ratio;
        final useWidthBound = heightByWidth <= availableHeight;
        final videoWidth = useWidthBound ? availableWidth : widthByHeight;
        final videoHeight = useWidthBound ? heightByWidth : availableHeight;

        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset > 0 ? 8 : 0),
          child: Center(
            child: SizedBox(
              width: videoWidth.clamp(120.0, availableWidth),
              height: videoHeight.clamp(120.0, availableHeight),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: UniversalVideo(
                  uri: uri,
                  autoplay: true,
                  aspectRatio: ratio,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class AudioFileContent extends HookConsumerWidget {
  final SnCloudFile item;
  final String uri;

  const AudioFileContent({required this.item, required this.uri, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(360, MediaQuery.of(context).size.width * 0.8),
        ),
        child: UniversalAudio(uri: uri, filename: item.name),
      ),
    );
  }
}

class GenericFileContent extends HookConsumerWidget {
  final SnCloudFile item;

  const GenericFileContent({required this.item, super.key});

  void _openWebPreview(BuildContext context) {
    final url = 'https://solian.app/files/${item.id}';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            AppBar(
              title: Text(item.name),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
              actions: [
                IconButton(icon: const Icon(Symbols.refresh), onPressed: () {}),
              ],
            ),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(url)),
                initialSettings: InAppWebViewSettings(
                  useShouldOverrideUrlLoading: true,
                  mediaPlaybackRequiresUserGesture: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.insert_drive_file,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const Gap(16),
          Text(
            item.name,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const Gap(8),
          Text(
            formatFileSize(item.size),
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const Gap(24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: () => ref
                    .read(driveFileDownloaderProvider)
                    .downloadFile(
                      item,
                      useDownloadsFolder:
                          HardwareKeyboard.instance.isShiftPressed,
                    ),
                icon: const Icon(Symbols.download),
                label: Text('download').tr(),
              ),
              const Gap(12),
              FilledButton.tonalIcon(
                onPressed: () => _openWebPreview(context),
                icon: const Icon(Symbols.open_in_browser),
                label: Text('previewInWeb').tr(),
              ),
              const Gap(12),
              OutlinedButton.icon(
                onPressed: () {
                  showModalBottomSheet(
                    useRootNavigator: true,
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => FileInfoSheet(item: item),
                  );
                },
                icon: const Icon(Symbols.info),
                label: Text('info').tr(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
