import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/pages/page_models.dart';
import 'package:solwatt/pages/pages_provider.dart';
import 'package:solwatt/shell/workspace_tabs.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/components/entity_card.dart';
import 'package:solwatt/workspace/components/related_items_strip.dart';
import 'package:solwatt/workspace/components/workspace_header.dart';
import 'package:solwatt/workspace/editor/workspace_rich_editor.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';

@RoutePage()
class WorkspaceNotesScreen extends ConsumerStatefulWidget {
  const WorkspaceNotesScreen({super.key});

  @override
  ConsumerState<WorkspaceNotesScreen> createState() =>
      _WorkspaceNotesScreenState();
}

class _WorkspaceNotesScreenState extends ConsumerState<WorkspaceNotesScreen> {
  final TextEditingController _titleController = TextEditingController();
  final Map<String, TextEditingController> _blockControllers = {};
  String? _loadedPageId;

  @override
  void dispose() {
    _titleController.dispose();
    for (final c in _blockControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncControllers(WorkspacePageDoc page) {
    if (_loadedPageId == page.id) return;
    _loadedPageId = page.id;
    _titleController.text = page.title;
    for (final c in _blockControllers.values) {
      c.dispose();
    }
    _blockControllers.clear();
    for (final block in page.blocks) {
      _blockControllers[block.id] = TextEditingController(text: block.text);
    }
  }

  TextEditingController _controllerFor(PageBlock block) {
    return _blockControllers.putIfAbsent(
      block.id,
      () => TextEditingController(text: block.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = ref.watch(pagesProvider);
    final selectedId = ref.watch(selectedPageIdProvider);
    final activePage =
        pages.where((p) => p.id == selectedId).firstOrNull ?? pages.firstOrNull;

    if (activePage == null) {
      return Scaffold(
        body: Column(
          children: [
            WorkspaceCanvasHeader(
              title: const Text('Pages'),
              actions: [
                FilledButton.icon(
                  onPressed: () =>
                      ref.read(pagesProvider.notifier).createPage(),
                  icon: const Icon(Symbols.add_rounded, size: 18),
                  label: const Text('New Page'),
                ),
              ],
            ),
            const Expanded(
              child: Center(
                child: Text('No pages yet. Create your first page.'),
              ),
            ),
          ],
        ),
      );
    }

    _syncControllers(activePage);
    final entityRef = activePage.toEntityRef();
    final isPinned = ref
        .watch(pinnedItemsProvider)
        .any((p) => p.domain == WorkspaceDomain.pages && p.id == activePage.id);

    // The page on screen is a document: reading it puts its title on the bar,
    // and it reads in the lens pane, so the tab is a root tab of the lens.
    return WorkspaceDocumentScope(
      domain: WorkspaceDomain.pages,
      entityId: activePage.id,
      title: activePage.title.isEmpty ? 'Untitled Page' : activePage.title,
      // A page reads in the pages lens, so it labels the lens tab rather than
      // opening one of its own.
      fullScreen: false,
      child: Scaffold(
        body: Column(
          children: [
            WorkspaceCanvasHeader(
              leading: Text(
                activePage.icon,
                style: const TextStyle(fontSize: 18),
              ),
              title: Text(
                activePage.title.isEmpty ? 'Untitled Page' : activePage.title,
              ),
              subtitle: Text('${activePage.blocks.length} blocks'),
              actions: [
                IconButton(
                  tooltip: isPinned ? 'Unpin' : 'Pin to Favorites',
                  icon: Icon(
                    Symbols.push_pin_rounded,
                    fill: isPinned ? 1 : 0,
                    size: 18,
                  ),
                  onPressed: () => ref
                      .read(pinnedItemsProvider.notifier)
                      .togglePin(entityRef),
                ),
                IconButton(
                  tooltip: 'Inspect in Peek',
                  icon: const Icon(Symbols.dock_to_right_rounded, size: 18),
                  onPressed: () =>
                      ref.read(peekProvider.notifier).open(entityRef),
                ),
                IconButton(
                  tooltip: 'New Page',
                  icon: const Icon(Symbols.add_rounded, size: 18),
                  onPressed: () =>
                      ref.read(pagesProvider.notifier).createPage(),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: SolSpace.xxl,
                  vertical: SolSpace.xl,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _titleController,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Untitled Page',
                            ),
                            onChanged: (value) {
                              ref
                                  .read(pagesProvider.notifier)
                                  .updatePage(
                                    activePage.copyWith(title: value),
                                  );
                            },
                          ),
                          const SizedBox(height: SolSpace.md),
                          for (final block in activePage.blocks)
                            _buildBlock(context, activePage, block),
                          const SizedBox(height: SolSpace.md),
                          Wrap(
                            spacing: SolSpace.sm,
                            children: [
                              ActionChip(
                                avatar: const Icon(
                                  Symbols.add_rounded,
                                  size: 16,
                                ),
                                label: const Text('Add text'),
                                onPressed: () => _addBlock(
                                  activePage,
                                  PageBlockType.paragraph,
                                ),
                              ),
                              ActionChip(
                                avatar: const Icon(
                                  Symbols.check_box_rounded,
                                  size: 16,
                                ),
                                label: const Text('Add to-do'),
                                onPressed: () =>
                                    _addBlock(activePage, PageBlockType.todo),
                              ),
                              ActionChip(
                                avatar: const Icon(
                                  Symbols.title_rounded,
                                  size: 16,
                                ),
                                label: const Text('Add heading'),
                                onPressed: () => _addBlock(
                                  activePage,
                                  PageBlockType.heading2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: SolSpace.xxl),
                          RelatedItemsStrip(
                            entity: entityRef,
                            extraItems: activePage.mentions,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addBlock(WorkspacePageDoc page, PageBlockType type) {
    final block = PageBlock(
      id: 'b-${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      text: '',
    );
    ref
        .read(pagesProvider.notifier)
        .updatePage(page.copyWith(blocks: [...page.blocks, block]));
  }

  void _updateBlock(WorkspacePageDoc page, PageBlock updated) {
    final nextBlocks = page.blocks
        .map((b) => b.id == updated.id ? updated : b)
        .toList();
    ref
        .read(pagesProvider.notifier)
        .updatePage(page.copyWith(blocks: nextBlocks));
  }

  Widget _buildBlock(
    BuildContext context,
    WorkspacePageDoc page,
    PageBlock block,
  ) {
    if (block.type == PageBlockType.entityEmbed &&
        block.embeddedEntity != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: SolSpace.xs),
        child: EntityCard(
          entity: block.embeddedEntity!,
          onToggleComplete: block.embeddedEntity!.domain == WorkspaceDomain.todo
              ? () {
                  final toggled = block.embeddedEntity!.copyWith(
                    isCompleted: !block.embeddedEntity!.isCompleted,
                  );
                  _updateBlock(page, block.copyWith(embeddedEntity: toggled));
                }
              : null,
        ),
      );
    }

    final controller = _controllerFor(block);
    final editor = WorkspaceRichEditor(
      controller: controller,
      mode: WorkspaceEditorMode.pageBlocks,
      minLines: 1,
      hintText: block.type == PageBlockType.todo
          ? 'To-do item...'
          : 'Type @ to mention or / for commands...',
      onChanged: (value) => _updateBlock(page, block.copyWith(text: value)),
      onMentionInserted: (mention) {
        ref.read(pagesProvider.notifier).addMention(page.id, mention);
        ref.read(backlinksProvider.notifier).link(page.toEntityRef(), mention);
      },
      onEmbedEntity: (entity) {
        ref.read(pagesProvider.notifier).embedEntity(page.id, entity);
        ref.read(backlinksProvider.notifier).link(page.toEntityRef(), entity);
      },
    );

    if (block.type == PageBlockType.todo) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: block.checked,
              onChanged: (v) =>
                  _updateBlock(page, block.copyWith(checked: v ?? false)),
            ),
            Expanded(child: editor),
          ],
        ),
      );
    }

    if (block.type == PageBlockType.heading1 ||
        block.type == PageBlockType.heading2) {
      final style = block.type == PageBlockType.heading1
          ? Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)
          : Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
      return Padding(
        padding: const EdgeInsets.only(top: SolSpace.md, bottom: SolSpace.xs),
        child: DefaultTextStyle(
          style: style ?? const TextStyle(),
          child: editor,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: editor,
    );
  }
}
