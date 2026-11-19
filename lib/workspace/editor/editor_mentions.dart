/// `@` autocomplete for the block editor.
///
/// Ported from Solian's `BlockMentionAutocomplete`: the host watches the
/// editor's transaction stream, finds the `@query` token under the caret,
/// fetches workspace entities and replaces the token with `@[Title]` when one
/// is picked. The editor owns the document, so the replacement is a real
/// transaction (undoable) rather than a text-controller rewrite.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:island_editor/island_editor.dart';

import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/workspace_models.dart';

class EditorMention {
  const EditorMention({required this.entity, required this.keyword});

  final WorkspaceEntityRef entity;

  /// The text that replaces the `@query` token.
  final String keyword;
}

typedef EditorMentionFetcher =
    Future<List<WorkspaceEntityRef>> Function(String query);

/// Owns one popup per editor instance.
///
/// Call [onTransaction] from the controller's transaction stream, [handleKey]
/// from [SolarBlockEditor.onKeyEvent], and [dispose] when the widget unmounts.
class EditorMentions {
  EditorMentions(
    this._context,
    this._editorState, {
    required this.fetch,
    required this.isEnabled,
  });

  final BuildContext _context;
  final EditorState _editorState;
  final EditorMentionFetcher fetch;
  final bool Function() isEnabled;

  OverlayEntry? _entry;
  Timer? _debounce;
  int _generation = 0;
  Rect _anchor = Rect.zero;
  List<EditorMention> _items = const [];
  int _highlighted = 0;

  /// The `@query` token ending at the caret, or null when the caret is not in
  /// one. A token runs from the nearest `@` with no whitespace in between.
  ({int start, int end, String query})? _tokenAtCaret() {
    final selection = _editorState.selection;
    if (selection == null || !selection.isCollapsed) return null;
    final node = _editorState.getNodeAtPath(selection.start.path);
    final plain = node?.delta?.toPlainText();
    if (node == null || plain == null) return null;
    final caret = selection.start.offset.clamp(0, plain.length);

    var start = caret;
    while (start > 0 && plain[start - 1] != ' ' && plain[start - 1] != '\n') {
      start--;
    }
    if (start >= caret || plain[start] != '@') return null;
    final query = plain.substring(start + 1, caret);
    if (query.isEmpty || query.contains(RegExp(r'\s'))) return null;
    return (start: start, end: caret, query: query);
  }

  /// Called from the transaction stream: schedules a debounced fetch for the
  /// token under the caret.
  void onTransaction() {
    if (!isEnabled()) {
      close();
      return;
    }
    _debounce?.cancel();
    final token = _tokenAtCaret();
    if (token == null) {
      close();
      return;
    }
    final generation = ++_generation;
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      List<WorkspaceEntityRef> result;
      try {
        result = await fetch(token.query);
      } catch (_) {
        return;
      }
      if (generation != _generation || !isEnabled()) return;
      _items = [
        for (final entity in result)
          EditorMention(entity: entity, keyword: '@[${entity.title}] '),
      ];
      _highlighted = 0;
      _anchor = _caretRect();
      _show();
    });
  }

  Rect _caretRect() {
    final rects = _editorState.selectionRects();
    if (rects.isNotEmpty) return rects.first;
    final box = _editorState.renderBox;
    if (box != null) {
      final origin = box.localToGlobal(Offset.zero);
      return Rect.fromLTWH(origin.dx, origin.dy + box.size.height, 1, 1);
    }
    return Rect.zero;
  }

  void _show() {
    if (!mountedContext) return;
    if (_entry != null) {
      _entry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.maybeOf(_context);
    if (overlay == null) return;
    _entry = OverlayEntry(builder: _build);
    overlay.insert(_entry!);
  }

  bool get mountedContext => _context.mounted;

  Widget _build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(320.0, screen.width - 16);
    final maxLeft = math.max(8.0, screen.width - width - 8);
    final maxTop = math.max(8.0, screen.height - 280);
    final left = _anchor.left.clamp(8.0, maxLeft);
    final top = (_anchor.bottom + 4).clamp(8.0, maxTop);
    final scheme = Theme.of(context).colorScheme;

    return Positioned(
      left: left,
      top: top,
      width: width,
      child: Material(
        elevation: 6,
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(SolRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: ListView.builder(
            padding: const EdgeInsets.all(SolSpace.xs),
            shrinkWrap: true,
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final item = _items[index];
              final highlighted = index == _highlighted;
              return InkWell(
                borderRadius: BorderRadius.circular(SolRadius.xs),
                onTap: () => _select(item),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SolSpace.sm,
                    vertical: SolSpace.sm,
                  ),
                  decoration: BoxDecoration(
                    color: highlighted
                        ? scheme.secondaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(SolRadius.xs),
                  ),
                  child: Row(
                    children: [
                      Icon(item.entity.domain.icon, size: 18, color: scheme.primary),
                      const SizedBox(width: SolSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.entity.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              item.entity.domain.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Replaces the active token with the picked entity's keyword.
  void _select(EditorMention item) {
    final token = _tokenAtCaret();
    final selection = _editorState.selection;
    if (token == null || selection == null) {
      close();
      return;
    }
    final node = _editorState.getNodeAtPath(selection.start.path);
    if (node == null) {
      close();
      return;
    }
    final transaction = _editorState.transaction
      ..replaceText(node, token.start, token.end - token.start, item.keyword);
    _editorState.apply(transaction);
    close();
  }

  /// Consumes arrows/Enter/Escape while the popup is open.
  KeyEventResult? handleKey(KeyEvent event) {
    if (_entry == null || _items.isEmpty || event is! KeyDownEvent) {
      return null;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _highlighted = (_highlighted + 1) % _items.length;
        _entry?.markNeedsBuild();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _highlighted = (_highlighted - 1 + _items.length) % _items.length;
        _entry?.markNeedsBuild();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _select(_items[_highlighted.clamp(0, _items.length - 1)]);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        close();
        return KeyEventResult.handled;
      default:
        return null;
    }
  }

  void close() {
    _items = const [];
    _entry?.remove();
    _entry = null;
  }

  void dispose() {
    _debounce?.cancel();
    close();
  }
}
