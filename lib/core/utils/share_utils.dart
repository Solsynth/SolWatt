import 'package:flutter/material.dart';

/// Wraps context-menu preview children in a plain surface so the drive's
/// `ContextMenuWidget(previewBuilder:)` previews render with a solid backdrop.
Widget contextMenuPreviewBuilder(BuildContext context, Widget child) {
  return Material(color: Theme.of(context).colorScheme.surface, child: child);
}
