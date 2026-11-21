/// SolWatt's editor wiring for `island_editor` (via `solar_network_foundation`).
///
/// Pages persist Markdown; mail persists `text/html`. The controller owns both
/// forms, so this file only adds the host seams:
///
/// - remote images are capped to the reading column instead of rendering at
///   their natural size;
/// - the editor's image entry uploads to the workspace Drive instead of
///   asking for a bare URL.
library;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_editor/island_editor.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart';

import 'package:solwatt/shared/widgets/text_editing_focus.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/cloud_files.dart';

/// Builds a controller with the host's image seams wired.
///
SolarEditorController createSolarEditor({
  String? initialMarkdown,
  String placeholder = 'Write something…',
  WidgetRef? ref,
  String? workspaceId,
  Map<String, BlockComponentBuilder> blockComponentBuilders = const {},
  bool Function()? onEscape,
}) {
  return SolarEditorController(
    initialMarkdown: initialMarkdown,
    config: SolarEditorConfig(
      placeholder: placeholder,
      blockComponentBuilders: blockComponentBuilders,
      onEscape: onEscape,
      onPickImage: ref == null
          ? null
          : () => pickImageUrl(ref, workspaceId: workspaceId),
      imageUrlResolver: _resolveImage,
    ),
  );
}

/// Picks an image, uploads it to the workspace Drive and returns the URL the
/// document stores. Null when the picker was cancelled.
Future<String?> pickImageUrl(WidgetRef ref, {String? workspaceId}) async {
  final files = await uploadLocalCloudFiles(
    ref,
    allowMultiple: false,
    workspaceId: workspaceId,
  );
  final file = files?.firstOrNull;
  if (file == null) return null;
  // The signed storage URL when the service gave one, otherwise the id, which
  // the reader resolves through the workspace Drive.
  final storageUrl = file.storageUrl?.trim();
  return storageUrl != null && storageUrl.isNotEmpty ? storageUrl : file.id;
}

/// The editor surface for SolWatt: the shared Solar block editor with the
/// app's theme already applied by the controller.
Widget solarBlockEditor(
  SolarEditorController controller, {
  bool editable = true,
  bool shrinkWrap = false,
  FocusNode? focusNode,
  KeyEventResult? Function(KeyEvent event)? onKeyEvent,
}) {
  return TextEditingSurface(
    child: SolarBlockEditor(
      controller: controller,
      editable: editable,
      shrinkWrap: shrinkWrap,
      focusNode: focusNode,
      onKeyEvent: onKeyEvent,
    ),
  );
}

/// A remote image at reading size. Unknown schemes return null so the editor
/// falls back to its own base64/file handling.
Widget? _resolveImage(BuildContext context, String src) {
  final uri = Uri.tryParse(src);
  if (uri == null || uri.scheme != 'http' && uri.scheme != 'https') {
    return null;
  }
  return ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 360, maxWidth: 640),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(SolRadius.sm),
      child: Image.network(
        src,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _BrokenImage(src: src),
      ),
    ),
  );
}

class _BrokenImage extends StatelessWidget {
  const _BrokenImage({required this.src});

  final String src;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            src,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
