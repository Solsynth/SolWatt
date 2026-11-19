import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:island_editor/island_editor.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart';

import 'package:solwatt/drive/favorites.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/pages/pages_provider.dart';
import 'package:solwatt/route.dart';
import 'package:solwatt/shell/workspace_tabs.dart';
import 'package:solwatt/shared/widgets/alert.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/markdown.dart';
import 'package:solwatt/ui/page_scaffold.dart';
import 'package:solwatt/workspace/components/related_items_strip.dart';
import 'package:solwatt/workspace/editor/editor_mentions.dart';
import 'package:solwatt/workspace/editor/solar_editor.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_search.dart';
import 'package:solwatt/workspace/workspace_state.dart';

/// One Ideask page: the Markdown body of a broad of kind 1.
///
/// It lives in the boards tab's nested stack beside the board, because a page
/// and a board are the same kind of thing to the service — a broad with a
/// tree, a workspace, an icon and a cover. The page's payload is `content`;
/// the board's is its task list.
@RoutePage()
class BroadDocScreen extends ConsumerStatefulWidget {
  const BroadDocScreen({super.key, @PathParam('pageId') required this.pageId});

  final String pageId;

  @override
  ConsumerState<BroadDocScreen> createState() => _BroadDocScreenState();
}

class _BroadDocScreenState extends ConsumerState<BroadDocScreen> {
  final TextEditingController _title = TextEditingController();
  final FocusNode _bodyFocus = FocusNode();

  /// The block editor owns the body. Pages persist Markdown, which is what
  /// [SolarEditorController.markdown] mirrors on every transaction.
  late final SolarEditorController _body = createSolarEditor(
    ref: ref,
    placeholder: 'Write Markdown. Type @ to mention…',
  );
  EditorMentions? _mentions;
  StreamSubscription<EditorTransactionValue>? _transactions;

  /// The saved values the fields started from; dirtiness is a plain comparison
  /// so a reader who undoes their own edit is clean again.
  String _savedTitle = '';
  String _savedContent = '';
  bool _loaded = false;
  bool _saving = false;
  bool _preview = false;

  String get _pageId => widget.pageId;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onEdited);
    _body.onChange = (_) => _onEdited();
    _mentions = EditorMentions(
      context,
      _body.editorState,
      fetch: (query) async =>
          searchWorkspaceEntities(ref, query, limitPerDomain: 4),
      isEnabled: () => !_preview,
    );
    _transactions = _body.editorState.transactionStream.listen(
      (_) => _mentions?.onTransaction(),
    );
  }

  @override
  void dispose() {
    _transactions?.cancel();
    _mentions?.dispose();
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _onEdited() => setState(() {});

  bool get _dirty =>
      _loaded &&
      (_title.text.trim() != _savedTitle.trim() ||
          _body.markdown != _savedContent);

  void _adopt(Broad page) {
    if (_loaded) return;
    _loaded = true;
    _savedTitle = page.name;
    _savedContent = page.content ?? '';
    _title.text = _savedTitle;
    _body.setMarkdown(_savedContent);
  }

  Future<void> _save() async {
    if (_saving) return;
    final page = ref.read(pageProvider(_pageId)).value;
    if (page == null) return;
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(pageActionsProvider)
          .savePage(page, name: _title.text, content: _body.markdown);
      if (!mounted) return;
      setState(() {
        _savedTitle = saved.name;
        _savedContent = saved.content ?? '';
        // The server normalizes the title; mirror it so dirtiness settles.
        _title.text = _savedTitle;
      });
      showSnackBar('pageSaved'.tr());
    } catch (error) {
      showSnackBar(wattApiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Broad page) async {
    final confirmed = await showConfirmAlert(
      'deletePageConfirm'.tr(namedArgs: {'name': page.name}),
      'deletePageTitle'.tr(),
      icon: Symbols.delete,
      isDanger: true,
      confirmLabel: 'delete'.tr(),
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(pageActionsProvider).deletePage(page);
      if (mounted) _popPage(context);
    } catch (error) {
      showSnackBar(wattApiErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(pageProvider(_pageId));
    final scheme = Theme.of(context).colorScheme;

    final loaded = page.value;
    if (loaded != null && !loaded.isPage) {
      // A board id behind the page route: send the reader to the board rather
      // than editing its task list as prose.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.router.replace(TaskBoardRoute(broadId: loaded.id));
        }
      });
    }
    if (loaded != null && loaded.isPage) _adopt(loaded);

    final title = _loaded ? _title.text.trim() : (loaded?.name ?? '');
    final name = title.isEmpty ? 'untitledPage'.tr() : title;
    final favorite = loaded == null
        ? false
        : isFavoriteEntity(ref, broadToEntityRef(loaded));

    return WorkspaceDocumentScope(
      domain: WorkspaceDomain.pages,
      entityId: _pageId,
      title: name,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        },
        child: Scaffold(
          backgroundColor: scheme.surface,
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'back'.tr(),
              icon: const Icon(Symbols.arrow_back),
              onPressed: () => _popPage(context),
            ),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              if (_dirty)
                IconButton(
                  tooltip: 'save'.tr(),
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Symbols.save),
                  onPressed: _saving ? null : _save,
                ),
              IconButton(
                tooltip: 'preview'.tr(),
                icon: Icon(
                  _preview ? Symbols.edit : Symbols.visibility,
                  size: 20,
                ),
                onPressed: () => setState(() => _preview = !_preview),
              ),
              IconButton(
                tooltip: favorite
                    ? 'Remove from Favorites'
                    : 'Add to Favorites',
                icon: Icon(
                  favorite ? Symbols.star_rounded : Symbols.star_border_rounded,
                  size: 20,
                ),
                onPressed: loaded == null
                    ? null
                    : () => toggleFavoriteEntity(
                        ref,
                        broadToEntityRef(loaded),
                      ),
              ),
              if (loaded != null)
                IconButton(
                  tooltip: 'Inspect in Peek',
                  icon: const Icon(Symbols.dock_to_right_rounded, size: 20),
                  onPressed: () => ref
                      .read(peekProvider.notifier)
                      .open(broadToEntityRef(loaded)),
                ),
              PopupMenuButton<String>(
                tooltip: 'more'.tr(),
                onSelected: (value) {
                  if (value == 'delete' && loaded != null) _delete(loaded);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'delete'.tr(),
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: page.when(
            loading: () => const PageLoading(),
            error: (error, _) => PageError(
              message: wattApiErrorMessage(error),
              onRetry: () => ref.invalidate(pageProvider(_pageId)),
            ),
            data: (page) {
              if (page == null) {
                return EmptyState(
                  icon: Symbols.article,
                  title: 'pageUnavailable'.tr(),
                  message: 'pageUnavailableDetail'.tr(),
                  action: FilledButton(
                    onPressed: () => _popPage(context),
                    child: Text('boards'.tr()),
                  ),
                );
              }
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SolSpace.xxl,
                          SolSpace.xl,
                          SolSpace.xxl,
                          SolSpace.sm,
                        ),
                        child: TextField(
                          controller: _title,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'untitledPage'.tr(),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SolSpace.xxl,
                          ),
                          child: _preview
                              ? SingleChildScrollView(
                                  child: MarkdownTextContent(
                                    content: _body.markdown.trim().isEmpty
                                        ? 'No content yet.'
                                        : _body.markdown,
                                  ),
                                )
                              : solarBlockEditor(
                                  _body,
                                  focusNode: _bodyFocus,
                                  onKeyEvent: (event) =>
                                      _mentions?.handleKey(event),
                                ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SolSpace.xxl,
                          SolSpace.md,
                          SolSpace.xxl,
                          SolSpace.xxl,
                        ),
                        child: RelatedItemsStrip(
                          entity: broadToEntityRef(page),
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
}

/// Back into the list the page was opened from. The nested stack normally
/// holds it; a deep link falls back to the list route.
void _popPage(BuildContext context) {
  final router = context.router;
  unawaited(
    router.maybePop().then((popped) {
      if (!popped && context.mounted) router.replace(const BoardsListRoute());
    }),
  );
}
