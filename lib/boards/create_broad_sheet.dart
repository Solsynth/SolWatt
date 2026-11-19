import 'package:easy_localization/easy_localization.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/route.dart';
import 'package:solwatt/shared/widgets/alert.dart';
import 'package:solwatt/theme.dart';

/// The one create action in the workspace: a task board or a page.
///
/// Boards and pages are both Ideask broads, so the reader should not have to
/// know which kind owns which lens. The sheet asks for the kind first, names
/// it, and opens the new document in the boards stack.
Future<void> showCreateBroadSheet(BuildContext context, WidgetRef ref) async {
  final workspace = await ref.read(selectedWorkspaceProvider.future);
  if (workspace == null) {
    showSnackBar('selectWorkspaceBeforeCreatingBoard'.tr());
    return;
  }
  if (!context.mounted) return;

  final kind = await showModalBottomSheet<int>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Symbols.view_kanban_rounded),
            title: Text('newBoard'.tr()),
            onTap: () => Navigator.of(ctx).pop(Broad.kindBoard),
          ),
          ListTile(
            leading: const Icon(Symbols.article_rounded),
            title: Text('newPage'.tr()),
            onTap: () => Navigator.of(ctx).pop(Broad.kindPage),
          ),
          const SizedBox(height: SolSpace.sm),
        ],
      ),
    ),
  );
  if (kind == null || !context.mounted) return;

  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => _NameDialog(
      title: (kind == Broad.kindPage ? 'newPage' : 'newBoard').tr(),
    ),
  );
  if (name == null || !context.mounted) return;

  try {
    final created = await ref
        .read(wattEngineClientProvider)
        .createBroad(
          name: name,
          workspaceId: workspace.id,
          kind: kind,
        );
    ref.invalidate(broadsProvider);
    if (!context.mounted) return;
    final router = context.router;
    if (kind == Broad.kindPage) {
      await router.push(BroadDocRoute(pageId: created.id));
    } else {
      await router.push(TaskBoardRoute(broadId: created.id));
    }
  } catch (error) {
    showSnackBar(wattApiErrorMessage(error));
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title});

  final String title;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: 'untitledPage'.tr()),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text('create'.tr()),
        ),
      ],
    );
  }
}
