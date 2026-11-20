/// Ideask's document routes: one page, one folder's task list, one collection.
///
/// They live in the Todo lens' nested stack beside the browser, so Back walks
/// the way the reader walked and the app shell stays put.
library;

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/ideask/ideask_providers.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/route.dart';
import 'package:solwatt/shell/workspace_tabs.dart';
import 'package:solwatt/shared/widgets/alert.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/markdown.dart';
import 'package:solwatt/ui/page_scaffold.dart';
import 'package:solwatt/workspace/components/related_items_strip.dart';
import 'package:solwatt/workspace/editor/editor_mentions.dart';
import 'package:solwatt/workspace/editor/solar_editor.dart';
import 'package:solwatt/workspace/workspace_search.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';
import 'package:solwatt/drive/favorites.dart' show isFavoriteEntity;

/// One Markdown page. Its body is stored apart from its metadata, so the
/// editor loads both; saving writes the body and re-reads the metadata the
/// server re-derives from it.
@RoutePage()
class DocPage extends ConsumerStatefulWidget {
  const DocPage({super.key, @PathParam('pageId') required this.pageId});

  final String pageId;

  @override
  ConsumerState<DocPage> createState() => _DocPageState();
}

class _DocPageState extends ConsumerState<DocPage> {
  final TextEditingController _title = TextEditingController();
  final FocusNode _bodyFocus = FocusNode();

  /// The block editor owns the body. Pages persist Markdown, which is what
  /// [SolarEditorController.markdown] mirrors on every transaction.
  late final _body = createSolarEditor(
    ref: ref,
    placeholder: 'Write Markdown. Type @ to mention…',
  );
  EditorMentions? _mentions;
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
  }

  @override
  void dispose() {
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

  void _adopt(IdeaskPage page, IdeaskPageBody body) {
    if (_loaded) return;
    _loaded = true;
    _savedTitle = page.title;
    _savedContent = body.contentMd;
    _title.text = _savedTitle;
    _body.setMarkdown(_savedContent);
  }

  Future<void> _save(IdeaskPage page) async {
    if (_saving) return;
    setState(() => _saving = true);
    final actions = ref.read(ideaskActionsProvider);
    try {
      final title = _title.text.trim();
      if (title.isNotEmpty && title != page.title) {
        await actions.updatePage(pageId: _pageId, title: title);
      }
      final body = await actions.savePageBody(
        pageId: _pageId,
        contentMd: _body.markdown,
      );
      if (!mounted) return;
      setState(() {
        _savedTitle = title;
        _savedContent = body.contentMd;
      });
      ref.invalidate(ideaskPageProvider(_pageId));
      showSnackBar('pageSaved'.tr());
    } catch (error) {
      showSnackBar(wattApiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(IdeaskPage page) async {
    final confirmed = await showConfirmAlert(
      'deletePageConfirm'.tr(namedArgs: {'name': page.displayTitle}),
      'deletePageTitle'.tr(),
      icon: Symbols.delete,
      isDanger: true,
      confirmLabel: 'delete'.tr(),
    );
    if (!confirmed) return;
    try {
      await ref.read(ideaskActionsProvider).deletePage(page.id);
      if (mounted) context.router.maybePop();
    } catch (error) {
      showSnackBar(wattApiErrorMessage(error));
    }
  }

  void _openPeek(IdeaskPage page) =>
      ref.read(peekProvider.notifier).open(ideaskEntityRefForPage(page));

  @override
  Widget build(BuildContext context) {
    final pageAsync = ref.watch(ideaskPageProvider(_pageId));
    final bodyAsync = ref.watch(ideaskPageBodyProvider(_pageId));
    final scheme = Theme.of(context).colorScheme;
    final page = pageAsync.value;
    final body = bodyAsync.value;
    if (page != null && body != null) _adopt(page, body);
    final favorite = page == null
        ? false
        : isFavoriteEntity(ref, ideaskEntityRefForPage(page));
    final title = _loaded ? _title.text.trim() : (page?.title ?? '');
    final name = title.isEmpty ? 'untitledPage'.tr() : title;

    return WorkspaceDocumentScope(
      domain: WorkspaceDomain.pages,
      entityId: _pageId,
      title: name,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
            if (page != null) _save(page);
          },
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (page != null) _save(page);
          },
        },
        child: Scaffold(
          backgroundColor: scheme.surface,
          appBar: AppBar(
            titleSpacing: 0,
            leading: const IdeaskBackButton(),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              if (_dirty && page != null)
                IconButton(
                  tooltip: 'save'.tr(),
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Symbols.save),
                  onPressed: _saving ? null : () => _save(page),
                ),
              IconButton(
                tooltip: 'preview'.tr(),
                icon: Icon(
                  _preview ? Symbols.edit : Symbols.visibility,
                  size: 20,
                ),
                onPressed: () => setState(() => _preview = !_preview),
              ),
              if (page != null)
                IconButton(
                  tooltip: favorite ? 'removeFromFavorites' : 'addToFavorites',
                  icon: Icon(
                    favorite
                        ? Symbols.star_rounded
                        : Symbols.star_border_rounded,
                    size: 20,
                  ),
                  onPressed: () => ref
                      .read(ideaskActionsProvider)
                      .toggleFavorite(ideaskEntityRefForPage(page)),
                ),
              if (page != null)
                IconButton(
                  tooltip: 'Inspect in Peek',
                  icon: const Icon(Symbols.dock_to_right_rounded, size: 20),
                  onPressed: () => _openPeek(page),
                ),
              if (page != null)
                PopupMenuButton<String>(
                  tooltip: 'more'.tr(),
                  onSelected: (value) {
                    if (value == 'delete') _delete(page);
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
          body: pageAsync.when(
            loading: () => const PageLoading(),
            error: (error, _) => PageError(
              message: wattApiErrorMessage(error),
              onRetry: () => ref.invalidate(ideaskPageProvider(_pageId)),
            ),
            data: (page) {
              return bodyAsync.when(
                loading: () => const PageLoading(),
                error: (error, _) => PageError(
                  message: wattApiErrorMessage(error),
                  onRetry: () =>
                      ref.invalidate(ideaskPageBodyProvider(_pageId)),
                ),
                data: (_) => Align(
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
                                          ? 'This page is empty.'
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
                            entity: ideaskEntityRefForPage(page),
                          ),
                        ),
                      ],
                    ),
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

/// Back into the browser the document was opened from. A deep link that has
/// no browser behind it replaces the stack with the lens root.
class IdeaskBackButton extends StatelessWidget {
  const IdeaskBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'back'.tr(),
      icon: const Icon(Symbols.arrow_back),
      onPressed: () => popIdeaskDocument(context),
    );
  }
}

void popIdeaskDocument(BuildContext context) {
  final router = context.router;
  router.maybePop().then((popped) {
    if (!popped && context.mounted) router.replace(const IdeaskBrowserRoute());
  });
}
