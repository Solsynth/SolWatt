/// Boards tab.
///
/// The tab route ([BoardsPage]) is a router host: [BoardsListPage] is the root
/// of its nested stack and a single board is pushed on top of it, so opening a
/// board keeps the app shell's navigation rail / bottom bar in place and Back
/// returns to the list it came from.
///
/// The board detail and the board/task sheets live in part files so this
/// library keeps one private namespace while the files stay navigable.
library;

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:solwatt/boards/github_integration.dart';
import 'package:solwatt/boards/task_comments.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/route.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/alert.dart';
import 'package:solwatt/ui/cloud_files.dart';
import 'package:solwatt/ui/markdown.dart';
import 'package:solwatt/ui/name_sheet.dart';
import 'package:solwatt/ui/page_scaffold.dart';

part 'board_detail.dart';
part 'board_sheets.dart';

/// Boards tab shell. Navigation happens inside the nested stack: the list is
/// the root page, a board is pushed above it.
@RoutePage()
class BoardsPage extends StatelessWidget {
  const BoardsPage({super.key});

  @override
  Widget build(BuildContext context) => const AutoRouter();
}

/// All boards of the selected workspace; the root page of the boards tab.
@RoutePage()
class BoardsListPage extends ConsumerWidget {
  const BoardsListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boards = ref.watch(broadsProvider);
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final wide = isWideScreen(context);

    void createBoard() => _boardForm(context, ref);

    return PageScaffold(
      title: 'boards'.tr(),
      subtitle: workspace == null
          ? 'ideaskBoards'.tr()
          : 'inWorkspace'.tr(namedArgs: {'name': workspace.name}),
      // The app bar only carries room for a labelled button once the shell
      // rail has taken its share of the width; on a phone the icon stands in
      // and the empty state keeps the labelled action.
      action: wide
          ? FilledButton.tonalIcon(
              onPressed: createBoard,
              icon: const Icon(Symbols.add, size: 18),
              label: Text('newBoard'.tr()),
            )
          : IconButton.filledTonal(
              tooltip: 'newBoard'.tr(),
              onPressed: createBoard,
              icon: const Icon(Symbols.add),
            ),
      child: boards.when(
        loading: () => const PageLoading(),
        error: (error, _) => PageError(
          message: error.toString(),
          onRetry: () => ref.invalidate(broadsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Symbols.view_kanban,
              title: 'noBoardsEmpty'.tr(),
              message: 'createBoardToOrganize'.tr(),
              action: FilledButton.icon(
                onPressed: createBoard,
                icon: const Icon(Symbols.add),
                label: Text('newBoard'.tr()),
              ),
            );
          }
          return wide ? _BoardGrid(boards: items) : _BoardLedger(boards: items);
        },
      ),
    );
  }
}

void _openBoard(BuildContext context, Broad board) {
  context.router.push(TaskBoardRoute(broadId: board.id));
}

/// Cover-first board cards. Used on wide screens, where a 2–4 column grid
/// keeps the covers large enough to be recognisable.
class _BoardGrid extends ConsumerWidget {
  const _BoardGrid({required this.boards});

  final List<Broad> boards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 1.5,
      ),
      itemCount: boards.length,
      itemBuilder: (context, index) => _BoardCard(board: boards[index]),
    );
  }
}

class _BoardCard extends ConsumerWidget {
  const _BoardCard({required this.board});

  final Broad board;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final cover = board.backgroundImage == null
        ? null
        : cloudFileDisplayUrl(board.backgroundImage!);
    final description = board.description?.trim();
    final prefix = board.taskPrefix?.trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      // Cards here hold text on a near-page-coloured fill: the outline is what
      // makes them read as objects.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => _openBoard(context, board),
        onLongPress: () => _boardForm(context, ref, board: board),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The cover slot keeps its size without a cover image, so a board
            // reads the same whether or not anyone set one.
            if (cover == null)
              ColoredBox(color: scheme.surfaceContainerHigh)
            else
              Image.network(
                cover,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: scheme.surfaceContainerHigh),
              ),
            if (cover != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      scheme.surface.withValues(alpha: 0.12),
                      scheme.surface.withValues(alpha: 0.94),
                    ],
                    stops: const [0.25, 0.78],
                  ),
                ),
              )
            else
              // A board without a cover keeps the same visual weight as the
              // rest of the grid instead of reading as a hole.
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    Symbols.view_kanban,
                    size: 84,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.15),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CloudFileAvatar(
                        file: board.iconImage,
                        fallbackIcon: Symbols.view_kanban,
                        size: 36,
                      ),
                      const Spacer(),
                      _BoardMenu(board: board, compact: true),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          board.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (prefix?.isNotEmpty == true) ...[
                        const SizedBox(width: 8),
                        _PrefixStamp(prefix!),
                      ],
                    ],
                  ),
                  if (description?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ledger rows. Used on phones, where a cover grid would either overflow or
/// shrink the covers to thumbnails.
class _BoardLedger extends StatelessWidget {
  const _BoardLedger({required this.boards});

  final List<Broad> boards;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: boards.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _BoardRow(board: boards[index]),
    );
  }
}

class _BoardRow extends ConsumerWidget {
  const _BoardRow({required this.board});

  final Broad board;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final description = board.description?.trim();
    final prefix = board.taskPrefix?.trim();

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        leading: CloudFileAvatar(
          file: board.iconImage,
          fallbackIcon: Symbols.view_kanban,
          size: 44,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                board.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (prefix?.isNotEmpty == true) ...[
              const SizedBox(width: 8),
              _PrefixStamp(prefix!),
            ],
          ],
        ),
        subtitle: description?.isNotEmpty == true
            ? Text(
                description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              )
            : null,
        trailing: _BoardMenu(board: board),
        onTap: () => _openBoard(context, board),
        onLongPress: () => _boardForm(context, ref, board: board),
      ),
    );
  }
}

/// Open / edit menu shared by the grid card and the ledger row.
class _BoardMenu extends ConsumerWidget {
  const _BoardMenu({required this.board, this.compact = false});

  final Broad board;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      icon: Icon(
        Symbols.more_vert,
        size: compact ? 20 : 24,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onSelected: (value) {
        if (value == 'open') _openBoard(context, board);
        if (value == 'edit') _boardForm(context, ref, board: board);
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'open', child: Text('open'.tr())),
        PopupMenuItem(value: 'edit', child: Text('edit'.tr())),
      ],
    );
  }
}

/// The board's task prefix (`SN`), the stamp its task keys (`SN-42`) are built
/// from. Rendered as a keycap so it reads as an identifier, not as prose.
class _PrefixStamp extends StatelessWidget {
  const _PrefixStamp(this.prefix);

  final String prefix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        prefix,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Surfaces that read as raised above the page background in both brightnesses
/// (`surfaceContainerLow`/`High` are *darker* than the page in light mode, but
/// *lighter* in dark mode, so the token has to flip).
Color _raisedSurface(ColorScheme scheme, Brightness brightness) =>
    brightness == Brightness.dark
    ? scheme.surfaceContainerHigh
    : scheme.surfaceContainerLowest;

Future<void> _boardForm(
  BuildContext context,
  WidgetRef ref, {
  Broad? board,
}) async {
  final workspace = await ref.read(selectedWorkspaceProvider.future);
  if (workspace == null) {
    showSnackBar('selectWorkspaceBeforeCreatingBoard'.tr());
    return;
  }
  if (!context.mounted) return;
  final draft = await showModalBottomSheet<_BoardDraft>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BoardEditorSheet(board: board),
  );
  if (draft == null) return;
  try {
    final client = ref.read(wattEngineClientProvider);
    if (board == null) {
      await client.createBroad(
        name: draft.name,
        description: draft.description,
        content: draft.content,
        workspaceId: workspace.id,
        iconImageId: draft.updateIconImage ? draft.iconImageId : null,
        backgroundImageId: draft.updateBackgroundImage
            ? draft.backgroundImageId
            : null,
        taskPrefix: draft.taskPrefix,
      );
    } else {
      await client.updateBroad(
        broadId: board.id,
        name: draft.name,
        description: draft.description,
        content: draft.content,
        workspaceId: workspace.id,
        iconImageId: draft.iconImageId,
        updateIconImage: draft.updateIconImage,
        backgroundImageId: draft.backgroundImageId,
        updateBackgroundImage: draft.updateBackgroundImage,
        taskPrefix: draft.taskPrefix,
        clearTaskPrefix: draft.clearTaskPrefix,
      );
    }
    ref.invalidate(broadsProvider);
    showSnackBar(board == null ? 'boardCreated'.tr() : 'boardUpdated'.tr());
  } catch (error) {
    showSnackBar(wattApiErrorMessage(error));
  }
}

class _BoardDraft {
  const _BoardDraft({
    required this.name,
    this.description,
    this.content,
    this.taskPrefix,
    this.clearTaskPrefix = false,
    this.iconImageId,
    this.updateIconImage = false,
    this.backgroundImageId,
    this.updateBackgroundImage = false,
  });

  final String name;
  final String? description;
  final String? content;
  final String? taskPrefix;
  final bool clearTaskPrefix;
  final String? iconImageId;
  final bool updateIconImage;
  final String? backgroundImageId;
  final bool updateBackgroundImage;
}

class _BoardEditorSheet extends ConsumerStatefulWidget {
  const _BoardEditorSheet({this.board});

  final Broad? board;

  @override
  ConsumerState<_BoardEditorSheet> createState() => _BoardEditorSheetState();
}

class _BoardEditorSheetState extends ConsumerState<_BoardEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _content;
  late final TextEditingController _taskPrefix;
  SnCloudFileReference? _icon;
  SnCloudFileReference? _background;
  var _iconChanged = false;
  var _backgroundChanged = false;

  @override
  void initState() {
    super.initState();
    final board = widget.board;
    _name = TextEditingController(text: board?.name ?? '');
    _description = TextEditingController(text: board?.description ?? '');
    _content = TextEditingController(text: board?.content ?? '');
    _taskPrefix = TextEditingController(text: board?.taskPrefix ?? '');
    _icon = board?.iconImage;
    _background = board?.backgroundImage;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _content.dispose();
    _taskPrefix.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final workspace = await ref.read(selectedWorkspaceProvider.future);
    if (!mounted) return;
    final file = await pickCloudImageReference(
      context,
      ref,
      usage: 'board.icon',
      workspaceId: workspace?.id,
      title: 'boardIcon'.tr(),
    );
    if (file == null || !mounted) return;
    setState(() {
      _icon = file;
      _iconChanged = true;
    });
  }

  Future<void> _pickBackground() async {
    final workspace = await ref.read(selectedWorkspaceProvider.future);
    if (!mounted) return;
    final file = await pickCloudImageReference(
      context,
      ref,
      usage: 'board.background',
      workspaceId: workspace?.id,
      title: 'backgroundImage'.tr(),
    );
    if (file == null || !mounted) return;
    setState(() {
      _background = file;
      _backgroundChanged = true;
    });
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      showSnackBar('nameIsRequired'.tr());
      return;
    }
    Navigator.pop(
      context,
      _BoardDraft(
        name: _name.text.trim(),
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        content: _content.text.trim().isEmpty ? null : _content.text.trim(),
        taskPrefix: _taskPrefix.text.trim().isEmpty
            ? null
            : _taskPrefix.text.trim(),
        clearTaskPrefix:
            widget.board?.taskPrefix != null && _taskPrefix.text.trim().isEmpty,
        iconImageId: _icon?.id,
        updateIconImage: _iconChanged,
        backgroundImageId: _background?.id,
        updateBackgroundImage: _backgroundChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final board = widget.board;

    return SheetScaffold(
      titleText: board == null ? 'newBoard'.tr() : 'editBoard'.tr(),
      heightFactor: 0.8,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: _pickIcon,
                  borderRadius: BorderRadius.circular(16),
                  child: CloudFileAvatar(
                    file: _icon,
                    fallbackIcon: Symbols.view_kanban,
                    size: 64,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('boardIcon'.tr(), style: text.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'boardIconDescription'.tr(),
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: _pickIcon,
                            icon: const Icon(Symbols.upload, size: 18),
                            label: Text(
                              _icon == null ? 'upload'.tr() : 'change'.tr(),
                            ),
                          ),
                          if (_icon != null)
                            TextButton(
                              onPressed: () => setState(() {
                                _icon = null;
                                _iconChanged = true;
                              }),
                              child: Text('clear'.tr()),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CloudFileAvatar(
                file: _background,
                fallbackIcon: Symbols.wallpaper,
                size: 40,
              ),
              title: Text('backgroundImage'.tr()),
              subtitle: Text(
                _background == null
                    ? 'optionalCoverImage'.tr()
                    : _background!.name,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_background != null)
                    IconButton(
                      tooltip: 'clearBackground'.tr(),
                      icon: const Icon(Symbols.close),
                      onPressed: () => setState(() {
                        _background = null;
                        _backgroundChanged = true;
                      }),
                    ),
                  IconButton(
                    tooltip: 'chooseBackground'.tr(),
                    icon: const Icon(Symbols.upload),
                    onPressed: _pickBackground,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: 'name'.tr(),
                prefixIcon: inputPrefixIcon(Symbols.title),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              decoration: InputDecoration(
                labelText: 'description'.tr(),
                alignLabelWithHint: true,
                prefixIcon: inputPrefixIcon(Symbols.notes, maxLines: 3),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _content,
              decoration: InputDecoration(
                labelText: 'content'.tr(),
                alignLabelWithHint: true,
                prefixIcon: inputPrefixIcon(Symbols.article, maxLines: 4),
                hintText: 'optionalLongFormDetail'.tr(),
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _taskPrefix,
              decoration: InputDecoration(
                labelText: 'taskPrefix'.tr(),
                hintText: 'SN',
                helperText: 'taskPrefixDescription'.tr(),
                prefixIcon: inputPrefixIcon(Symbols.tag),
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 32,
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _submit,
              child: Text(
                board == null ? 'createBoard'.tr() : 'saveChanges'.tr(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
