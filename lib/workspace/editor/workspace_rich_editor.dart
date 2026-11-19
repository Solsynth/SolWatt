import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/pages/pages_provider.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/components/entity_pill.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_search.dart';

enum WorkspaceEditorMode { pageBlocks, mailComposer, todoDescription }

enum SlashCommandType {
  task('/task', 'Insert or create a Todo task', Symbols.check_box_rounded),
  page('/page', 'Create or embed a linked Page', Symbols.article_rounded),
  file(
    '/file',
    'Embed a Drive file or attachment',
    Symbols.attach_file_rounded,
  ),
  email('/email', 'Embed an Email thread reference', Symbols.mail_rounded);

  final String trigger;
  final String description;
  final IconData icon;

  const SlashCommandType(this.trigger, this.description, this.icon);
}

enum _TriggerKind { none, mention, slash }

/// Shared rich-text editor reused across Notion-like Pages (full block mode),
/// Mail Composer (streamlined mode), and Todo Descriptions (compact mode).
///
/// Supports universal `@` cross-domain mentions and `/` cross-domain commands
/// with a platform-adaptive suggestion UI:
/// - Desktop: anchored floating popover navigable with Up/Down, Enter, Esc.
/// - Mobile: 44px horizontal scrollable suggestion bar docked above the
///   software keyboard (`MediaQuery.viewInsets.bottom`).
class WorkspaceRichEditor extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final WorkspaceEditorMode mode;
  final String hintText;
  final int? minLines;
  final int? maxLines;
  final List<WorkspaceEntityRef> mentions;
  final ValueChanged<String>? onChanged;
  final ValueChanged<WorkspaceEntityRef>? onMentionInserted;
  final ValueChanged<WorkspaceEntityRef>? onEmbedEntity;
  final ValueChanged<WorkspaceEntityRef>? onSwitchLens;

  const WorkspaceRichEditor({
    super.key,
    required this.controller,
    this.focusNode,
    this.mode = WorkspaceEditorMode.pageBlocks,
    this.hintText = 'Type @ to mention or / for commands...',
    this.minLines,
    this.maxLines,
    this.mentions = const [],
    this.onChanged,
    this.onMentionInserted,
    this.onEmbedEntity,
    this.onSwitchLens,
  });

  @override
  ConsumerState<WorkspaceRichEditor> createState() =>
      _WorkspaceRichEditorState();
}

class _WorkspaceRichEditorState extends ConsumerState<WorkspaceRichEditor> {
  final LayerLink _layerLink = LayerLink();
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  OverlayEntry? _desktopOverlay;
  OverlayEntry? _mobileBarOverlay;

  _TriggerKind _trigger = _TriggerKind.none;
  int _triggerStart = -1;
  String _query = '';
  int _highlightedIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant WorkspaceRichEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    _hideSuggestions();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted && !_focusNode.hasFocus) {
          _hideSuggestions();
        }
      });
    }
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final cursor = selection.baseOffset;
    if (cursor < 0 || cursor > text.length) {
      _hideSuggestions();
      return;
    }

    final beforeCursor = text.substring(0, cursor);
    final lastSpace = beforeCursor.lastIndexOf(RegExp(r'\s'));
    final tokenStart = lastSpace + 1;
    final token = beforeCursor.substring(tokenStart);

    if (token.startsWith('@')) {
      _trigger = _TriggerKind.mention;
      _triggerStart = tokenStart;
      _query = token.substring(1);
      _highlightedIndex = 0;
      _showOrUpdateSuggestions();
    } else if (token.startsWith('/')) {
      _trigger = _TriggerKind.slash;
      _triggerStart = tokenStart;
      _query = token.substring(1);
      _highlightedIndex = 0;
      _showOrUpdateSuggestions();
    } else {
      _hideSuggestions();
    }
  }

  bool get _isMobileLayout =>
      MediaQuery.sizeOf(context).width < SolWorkspaceGeometry.tabletBreakpoint;

  void _showOrUpdateSuggestions() {
    if (!mounted) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    if (_isMobileLayout) {
      _desktopOverlay?.remove();
      _desktopOverlay = null;
      if (_mobileBarOverlay == null) {
        _mobileBarOverlay = OverlayEntry(
          builder: (ctx) => _buildMobileBar(ctx),
        );
        overlay.insert(_mobileBarOverlay!);
      } else {
        _mobileBarOverlay!.markNeedsBuild();
      }
    } else {
      _mobileBarOverlay?.remove();
      _mobileBarOverlay = null;
      if (_desktopOverlay == null) {
        _desktopOverlay = OverlayEntry(
          builder: (ctx) => _buildDesktopPopover(ctx),
        );
        overlay.insert(_desktopOverlay!);
      } else {
        _desktopOverlay!.markNeedsBuild();
      }
    }
  }

  void _hideSuggestions() {
    _trigger = _TriggerKind.none;
    _triggerStart = -1;
    _query = '';
    _desktopOverlay?.remove();
    _desktopOverlay = null;
    _mobileBarOverlay?.remove();
    _mobileBarOverlay = null;
  }

  List<_SuggestionItem> _buildSuggestions() {
    if (_trigger == _TriggerKind.mention) {
      final entities = searchWorkspaceEntities(ref, _query, limitPerDomain: 4);
      return [
        for (final e in entities)
          _SuggestionItem(
            title: e.title,
            subtitle: e.domain.label,
            icon: e.domain.icon,
            entity: e,
          ),
      ];
    }
    if (_trigger == _TriggerKind.slash) {
      final q = _query.toLowerCase();
      return [
        for (final cmd in SlashCommandType.values)
          if (q.isEmpty || cmd.trigger.substring(1).contains(q))
            _SuggestionItem(
              title: cmd.trigger,
              subtitle: cmd.description,
              icon: cmd.icon,
              slashCommand: cmd,
            ),
      ];
    }
    return const [];
  }

  void _applySuggestion(_SuggestionItem item) {
    final text = widget.controller.text;
    final cursor = widget.controller.selection.baseOffset;
    final start = _triggerStart.clamp(0, text.length);
    final end = cursor.clamp(start, text.length);

    if (item.entity != null) {
      final replacement = '@[${item.entity!.title}] ';
      final nextText = text.replaceRange(start, end, replacement);
      widget.controller.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: start + replacement.length),
      );
      widget.onChanged?.call(nextText);
      widget.onMentionInserted?.call(item.entity!);
      _hideSuggestions();
      return;
    }

    if (item.slashCommand != null) {
      final nextText = text.replaceRange(start, end, '');
      widget.controller.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: start),
      );
      widget.onChanged?.call(nextText);
      final cmd = item.slashCommand!;
      _hideSuggestions();
      _executeSlashCommand(cmd);
    }
  }

  Future<void> _executeSlashCommand(SlashCommandType cmd) async {
    switch (cmd) {
      case SlashCommandType.task:
        // A page is a broad without tasks, so /task targets the first board.
        final boards = ref.read(taskBoardsProvider).value ?? const <Broad>[];
        final firstBoard = boards.firstOrNull;
        if (firstBoard == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Create a Todo board first to insert a task.'),
              ),
            );
          }
          return;
        }
        try {
          final createdTask = await ref
              .read(wattEngineClientProvider)
              .createTask(
                firstBoard.id,
                const WorkTaskDraft(name: 'Follow-up task'),
              );
          ref.invalidate(
            tasksProvider(TaskListRequest(broadId: firstBoard.id)),
          );
          widget.onEmbedEntity?.call(
            WorkspaceEntityRef(
              id: createdTask.id,
              domain: WorkspaceDomain.todo,
              title: createdTask.name,
              subtitle: firstBoard.name,
              status: createdTask.completedAt != null ? 'Completed' : 'Open',
              isCompleted: createdTask.completedAt != null,
              metadata: {'broadId': firstBoard.id},
            ),
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not create task: $e')),
            );
          }
        }
      case SlashCommandType.page:
        unawaited(() async {
          try {
            final page = await ref
                .read(pageActionsProvider)
                .createPage(title: 'Linked Sub-Page');
            widget.onEmbedEntity?.call(broadToEntityRef(page));
          } catch (error) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(wattApiErrorMessage(error))),
              );
            }
          }
        }());
      case SlashCommandType.file:
        final files = searchWorkspaceEntities(
          ref,
          '',
          domainFilter: WorkspaceDomain.drive,
          limitPerDomain: 1,
        );
        final file = files.firstOrNull;
        if (file == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No Drive files available to embed.'),
              ),
            );
          }
          return;
        }
        widget.onEmbedEntity?.call(file);
      case SlashCommandType.email:
        final emails = searchWorkspaceEntities(
          ref,
          '',
          domainFilter: WorkspaceDomain.mail,
          limitPerDomain: 1,
        );
        final mail = emails.firstOrNull;
        if (mail == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No Mail threads available to embed.'),
              ),
            );
          }
          return;
        }
        widget.onEmbedEntity?.call(mail);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_trigger == _TriggerKind.none || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final items = _buildSuggestions();
    if (items.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _highlightedIndex = (_highlightedIndex + 1) % items.length;
      });
      _desktopOverlay?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _highlightedIndex =
            (_highlightedIndex - 1 + items.length) % items.length;
      });
      _desktopOverlay?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _applySuggestion(items[_highlightedIndex.clamp(0, items.length - 1)]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _hideSuggestions();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildDesktopPopover(BuildContext context) {
    final items = _buildSuggestions();
    if (items.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Positioned(
      width: 320,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 44),
        child: Material(
          elevation: 6,
          color: scheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SolRadius.sm),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.builder(
              padding: const EdgeInsets.all(SolSpace.xs),
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final highlighted = index == _highlightedIndex;
                return InkWell(
                  borderRadius: BorderRadius.circular(SolRadius.xs),
                  onTap: () => _applySuggestion(item),
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
                        Icon(item.icon, size: 18, color: scheme.primary),
                        const SizedBox(width: SolSpace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                item.subtitle,
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
      ),
    );
  }

  /// Mobile: 44px horizontal scrollable suggestion bar docked directly above
  /// the software keyboard (`MediaQuery.viewInsets.bottom`).
  Widget _buildMobileBar(BuildContext context) {
    final items = _buildSuggestions();
    if (items.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Positioned(
      left: 0,
      right: 0,
      bottom: keyboardInset,
      child: Material(
        elevation: 6,
        color: scheme.surfaceContainerHigh,
        child: SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: SolSpace.sm,
              vertical: 6,
            ),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: SolSpace.xs),
            itemBuilder: (context, index) {
              final item = items[index];
              return ActionChip(
                avatar: Icon(item.icon, size: 15),
                label: Text(item.title),
                visualDensity: VisualDensity.compact,
                onPressed: () => _applySuggestion(item),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Suggestions read the boards/pages provider; when it resolves after the
    // reader already typed `@`, the open overlay has to be rebuilt.
    ref.listen(broadsProvider, (_, _) {
      if (_desktopOverlay != null || _mobileBarOverlay != null) {
        _showOrUpdateSuggestions();
      }
    });
    final minLines = switch (widget.mode) {
      WorkspaceEditorMode.pageBlocks => widget.minLines ?? 2,
      WorkspaceEditorMode.mailComposer => widget.minLines ?? 6,
      WorkspaceEditorMode.todoDescription => widget.minLines ?? 2,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CompositedTransformTarget(
          link: _layerLink,
          child: Focus(
            onKeyEvent: _handleKeyEvent,
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              minLines: minLines,
              maxLines: widget.maxLines,
              onChanged: widget.onChanged,
              decoration: InputDecoration(
                hintText: widget.hintText,
                border: widget.mode == WorkspaceEditorMode.pageBlocks
                    ? InputBorder.none
                    : const OutlineInputBorder(),
                isDense: widget.mode == WorkspaceEditorMode.pageBlocks,
              ),
            ),
          ),
        ),
        if (widget.mentions.isNotEmpty) ...[
          const SizedBox(height: SolSpace.xs),
          Wrap(
            spacing: SolSpace.xs,
            runSpacing: SolSpace.xs,
            children: [
              for (final mention in widget.mentions)
                EntityPill(entity: mention, onSwitchLens: widget.onSwitchLens),
            ],
          ),
        ],
      ],
    );
  }
}

class _SuggestionItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final WorkspaceEntityRef? entity;
  final SlashCommandType? slashCommand;

  const _SuggestionItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.entity,
    this.slashCommand,
  });
}
