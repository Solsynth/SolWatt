import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/ideask/ideask_providers.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/workspace/components/entity_card.dart';
import 'package:solwatt/workspace/components/workspace_header.dart';
import 'package:solwatt/workspace/workspace_models.dart';
import 'package:solwatt/workspace/workspace_state.dart';

/// Unified Today / Focus Landing View: combines real priority/unread Mail,
/// active Ideask Tasks, and user Pages into one structured morning workspace.
@RoutePage()
class TodayFocusPage extends ConsumerWidget {
  const TodayFocusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final mailboxId = ref.watch(selectedMailboxIdProvider);
    final folder = ref.watch(selectedFolderProvider);
    final threads =
        ref
            .watch(
              threadsProvider((
                filter: (
                  mailboxId: mailboxId,
                  folder: folder,
                  q: null,
                  status: null,
                  isFlagged: null,
                  from: null,
                  to: null,
                  hasAttachments: null,
                ),
                take: 25,
              )),
            )
            .value
            ?.items ??
        const <MailThread>[];
    final unreadMail = threads.where((t) => t.unreadCount > 0).take(5).toList();
    // Tasks live in the workspace; one request is the whole open-task rollup.
    final workspaceId = ref.watch(ideaskWorkspaceIdProvider);
    final openTasks = workspaceId == null
        ? const <WorkTask>[]
        : (ref
                      .watch(
                        tasksProvider(
                          TaskListRequest(
                            workspaceId: workspaceId,
                            filters: const TaskListFilters(
                              status: TaskStatus.open,
                            ),
                          ),
                        ),
                      )
                      .value ??
                  const <WorkTask>[])
              .take(8)
              .toList(growable: false);
    final pages =
        (ref
                    .watch(ideaskBrowserProvider)
                    .value
                    ?.pages ??
                const <IdeaskPage>[])
            .take(5)
            .toList();
    final pinned = ref.watch(favoritesProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Column(
        children: [
          WorkspaceCanvasHeader(
            leading: Icon(
              Symbols.star_rounded,
              color: scheme.primary,
              size: 20,
            ),
            title: const Text('Today / Focus'),
            subtitle: Text(
              '${unreadMail.length} unread mail · ${openTasks.length} open tasks · ${pages.length} pages',
            ),
            actions: [
              IconButton(
                tooltip: 'New Page',
                icon: const Icon(Symbols.note_add_rounded, size: 18),
                onPressed: () async {
                  try {
                    final page = await ref
                        .read(ideaskActionsProvider)
                        .createPage(title: 'Daily Note');
                    ref
                        .read(peekProvider.notifier)
                        .open(ideaskEntityRefForPage(page));
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(wattApiErrorMessage(error))),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: solPagePadding(
                context,
              ).add(const EdgeInsets.symmetric(vertical: SolSpace.xl)),
              children: [
                if (pinned.isNotEmpty) ...[
                  const _SectionHeader(
                    icon: Symbols.star_rounded,
                    title: 'Favorites',
                  ),
                  const SizedBox(height: SolSpace.sm),
                  Wrap(
                    spacing: SolSpace.sm,
                    runSpacing: SolSpace.sm,
                    children: [
                      for (final item in pinned)
                        ActionChip(
                          avatar: Icon(item.domain.icon, size: 16),
                          label: Text(item.title),
                          onPressed: () =>
                              ref.read(peekProvider.notifier).open(item),
                        ),
                    ],
                  ),
                  const SizedBox(height: SolSpace.section),
                ],
                const _SectionHeader(
                  icon: Symbols.mail_rounded,
                  title: 'Priority & Unread Mail',
                ),
                const SizedBox(height: SolSpace.sm),
                if (unreadMail.isEmpty)
                  const _EmptySectionCard(
                    message: 'Inbox zero — no unread threads right now.',
                  )
                else
                  for (final thread in unreadMail) ...[
                    EntityCard(
                      compact: true,
                      entity: WorkspaceEntityRef(
                        id: thread.id,
                        domain: WorkspaceDomain.mail,
                        title: thread.subject.isEmpty
                            ? 'noSubject'.tr()
                            : thread.subject,
                        subtitle:
                            thread.latestMessage.from?.name ??
                            thread.latestMessage.from?.address ??
                            thread.participants.firstOrNull,
                        status: '${thread.unreadCount} unread',
                        metadata: {'threadId': thread.id},
                      ),
                    ),
                    const SizedBox(height: SolSpace.sm),
                  ],
                const SizedBox(height: SolSpace.section),
                const _SectionHeader(
                  icon: Symbols.check_box_rounded,
                  title: 'Open Tasks',
                ),
                const SizedBox(height: SolSpace.sm),
                if (openTasks.isEmpty)
                  const _EmptySectionCard(
                    message: 'No open tasks in this workspace.',
                  )
                else
                  for (final task in openTasks) ...[
                    EntityCard(
                      compact: true,
                      entity: ideaskEntityRefForTask(task, fallbackTitle: null),
                    ),
                    const SizedBox(height: SolSpace.sm),
                  ],
                const SizedBox(height: SolSpace.section),
                const _SectionHeader(
                  icon: Symbols.article_rounded,
                  title: 'Pages',
                ),
                const SizedBox(height: SolSpace.sm),
                if (pages.isEmpty)
                  const _EmptySectionCard(
                    message: 'No pages yet. Tap + to create your first page.',
                  )
                else
                  for (final page in pages) ...[
                    EntityCard(
                      compact: true,
                      entity: ideaskEntityRefForPage(page),
                    ),
                    const SizedBox(height: SolSpace.sm),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: SolSpace.sm),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _EmptySectionCard extends StatelessWidget {
  final String message;

  const _EmptySectionCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(SolSpace.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SolRadius.md),
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
