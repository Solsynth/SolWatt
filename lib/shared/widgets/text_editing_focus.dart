/// Tells the workspace shell when a keystroke is text rather than a command.
///
/// The shell binds bare keys (`Space`, `E`, `T`) to entity actions. Those are
/// also ordinary typing, and a key handler above a focused input halts the
/// event before the input sees it — so `e` would never reach the page editor
/// while it had focus. The grammar therefore has to step aside whenever the
/// focused widget takes text.
library;

import 'package:flutter/widgets.dart';

/// Marks a subtree as a text-editing surface.
///
/// [TextField]-based inputs already announce themselves through [EditableText].
/// Editors built on a custom render tree (the block editor) do not, so their
/// host wraps them in this marker; [isTextEditingFocused] can then recognise
/// the caret without knowing which editor package is in use.
class TextEditingSurface extends StatelessWidget {
  const TextEditingSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Whether the primary focus currently sits inside something that inserts the
/// characters it receives: a [TextField]/[EditableText], or a surface marked
/// with [TextEditingSurface].
bool isTextEditingFocused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.findAncestorWidgetOfExactType<EditableText>() != null ||
      context.findAncestorWidgetOfExactType<TextEditingSurface>() != null;
}
