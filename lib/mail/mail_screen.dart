import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';
import 'package:super_context_menu/super_context_menu.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import 'package:solwatt/core/utils/file_types.dart';
import 'package:solwatt/core/widgets/content/cloud_file_attachment_list.dart';
import 'package:solwatt/core/widgets/content/cloud_file_lightbox.dart';
import 'package:solwatt/mail/email_contrast.dart';
import 'package:solwatt/mail/mail_address_suggestion.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/ui/alert.dart';
import 'package:solwatt/ui/cloud_files.dart';
import 'package:solwatt/ui/page_scaffold.dart';
import 'package:solwatt/route.dart';
import 'package:solwatt/theme.dart';
import 'package:url_launcher/url_launcher.dart';

@RoutePage()
class MailPage extends StatelessWidget {
  const MailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    if (!wide) return const AutoRouter();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(width: 420, child: _MailListWidget()),
            const SizedBox(width: 8),
            const Expanded(child: AutoRouter()),
          ],
        ),
      ),
    );
  }
}

@RoutePage()
class MailListPage extends StatelessWidget {
  const MailListPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (isWideScreen(context)) return const SizedBox.shrink();
    // The list brings its own app bar on phones and runs edge to edge: the
    // card-like pane only reads as a pane next to the detail view on wide
    // screens.
    return const _MailListWidget();
  }
}

@RoutePage()
class MailComposePage extends ConsumerWidget {
  const MailComposePage({
    super.key,
    @QueryParam('replyTo') this.replyToId,
    @QueryParam('replyAll') this.replyAll = false,
    @QueryParam('forward') this.forwardId,
  });

  final String? replyToId;
  final bool replyAll;
  final String? forwardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mailboxes = ref.watch(mailboxesProvider);
    final mailHost = ref.watch(mailHostProvider).value;
    final sourceEmail = replyToId ?? forwardId;
    final source = sourceEmail == null
        ? null
        : ref.watch(emailProvider(sourceEmail));

    if (source != null) {
      return source.when(
        loading: () => _composeLoading(context),
        error: (error, _) => _composeError(context, error, ref),
        data: (email) => _buildComposer(
          context,
          ref,
          mailboxes,
          mailHost,
          source: email,
          isReply: replyToId != null,
          replyAll: replyAll,
        ),
      );
    }
    return _buildComposer(context, ref, mailboxes, mailHost);
  }

  Widget _buildComposer(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<MailMailbox>> mailboxes,
    String? mailHost, {
    MailEmail? source,
    bool isReply = false,
    bool replyAll = false,
  }) {
    return mailboxes.when(
      loading: () => _composeLoading(context),
      error: (error, _) => _composeError(context, error, ref),
      data: (items) {
        if (items.isEmpty) {
          return Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            child: EmptyState(
              icon: Symbols.mail,
              title: 'noMailboxes'.tr(),
              message: 'createMailboxFirst'.tr(),
            ),
          );
        }
        final mailbox = items.firstWhere(
          (item) => item.id == source?.mailboxId,
          orElse: () => items.firstWhere(
            (item) => item.isDefault,
            orElse: () => items.first,
          ),
        );
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: _ComposeSheet(
            mailbox: mailbox,
            mailboxes: items,
            mailHost: mailHost,
            replyingTo: isReply ? source : null,
            replyAll: replyAll,
            forwarding: isReply ? null : source,
            onSubmitted: (draft) => _sendDraft(context, ref, draft),
            onClose: () => context.router.pop(),
          ),
        );
      },
    );
  }

  Widget _composeLoading(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(8),
    child: const PageLoading(),
  );

  Widget _composeError(BuildContext context, Object error, WidgetRef ref) =>
      Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        child: PageError(
          message: error.toString(),
          onRetry: () {
            ref.invalidate(mailboxesProvider);
            final source = replyToId ?? forwardId;
            if (source != null) ref.invalidate(emailProvider(source));
          },
        ),
      );

  Future<void> _sendDraft(
    BuildContext context,
    WidgetRef ref,
    _MailDraft draft,
  ) async {
    try {
      await ref
          .read(wattEngineClientProvider)
          .sendEmail(
            mailboxId: draft.mailboxId,
            to: draft.to,
            cc: draft.cc,
            bcc: draft.bcc,
            subject: draft.subject,
            body: draft.body,
            attachmentIds: draft.attachmentIds,
            isDraft: draft.isDraft,
            contentType: draft.contentType,
            replyToId: draft.replyToId,
          );
      _invalidateMail(ref);
      if (context.mounted) {
        context.router.pop();
        showSnackBar(draft.isDraft ? 'draftSaved'.tr() : 'emailSent'.tr());
      }
    } catch (error) {
      showSnackBar(error.toString());
    }
  }
}

class _MailListWidget extends ConsumerStatefulWidget {
  const _MailListWidget();

  @override
  ConsumerState<_MailListWidget> createState() => _MailListWidgetState();
}

class _MailListWidgetState extends ConsumerState<_MailListWidget> {
  String? _deliveryStatus;
  bool? _isFlagged;
  String? _from;
  String? _to;
  bool? _hasAttachments;
  /// Conversation the detail pane is showing, for row highlighting.
  String? _selectedThreadId;
  /// Conversations requested from the server. "Load more" grows this instead of
  /// paging offsets, so every fetch is a superset of the previous listing:
  /// whole-conversation counts stay consistent and no page can go missing.
  int _take = kThreadPageSize;
  final _searchController = TextEditingController();
  bool _searchOpen = false;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Resets the list state when the mailbox, folder, or query changes.
  void _resetList() {
    setState(() {
      _selectedThreadId = null;
      _take = kThreadPageSize;
    });
  }

  void _selectMailbox(String id) {
    if (ref.read(selectedMailboxIdProvider) == id) return;
    ref.read(selectedMailboxIdProvider.notifier).select(id);
    _resetList();
    ref.invalidate(threadsProvider);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _resetList();
      ref.invalidate(threadsProvider);
    });
  }

  /// Opens the inbox picker from the app bar title, so a phone can switch
  /// inboxes without giving up a bottom-bar slot.
  Future<void> _openMailboxPickerSheet(
    List<MailMailbox> mailboxes, {
    required String? mailHost,
    required String? mailboxId,
  }) async {
    final result = await showMailboxPickerSheet(
      context,
      mailboxes: mailboxes,
      mailHost: mailHost,
      selectedId: mailboxId,
    );
    if (result == null || !mounted) return;
    if (result.createNew) {
      await _createMailbox(context);
    } else if (result.mailboxId != null) {
      _selectMailbox(result.mailboxId!);
    }
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) _searchController.clear();
    });
    if (!_searchOpen) _resetList();
    ref.invalidate(threadsProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedMailboxIdProvider, (previous, next) {
      if (previous == next || !mounted) return;
      _resetList();
    });
    ref.listen(selectedFolderProvider, (previous, next) {
      if (previous == next || !mounted) return;
      _resetList();
      ref.invalidate(threadsProvider);
    });
    final mailboxes = ref.watch(mailboxesProvider);
    final mailHost = ref.watch(mailHostProvider);
    final selectedMailboxId = ref.watch(selectedMailboxIdProvider);
    final folder = ref.watch(selectedFolderProvider);
    final mailboxId = _effectiveMailboxId(mailboxes.value, selectedMailboxId);
    return _buildEmailList(
      mailHost.value,
      mailboxId: mailboxId,
      folder: folder,
      mailboxSelector: _buildMailboxSelector(
        mailboxes,
        mailHost: mailHost.value,
        mailboxId: mailboxId,
      ),
    );
  }

  Widget _buildMailboxSelector(
    AsyncValue<List<MailMailbox>> mailboxes, {
    required String? mailHost,
    required String? mailboxId,
  }) {
    return mailboxes.when(
      loading: () => const SizedBox(
        height: 40,
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (error, _) => _MailboxError(
        message: error.toString(),
        onRetry: () => ref.invalidate(mailboxesProvider),
      ),
      data: (items) {
        // A phone shows the inbox as the app bar title and switches through
        // the picker sheet, because the bottom bar carries the folders.
        if (!isWideScreen(context)) {
          final current = items.isEmpty
              ? null
              : items.where((m) => m.id == mailboxId).firstOrNull ??
                    items.firstWhere(
                      (m) => m.isDefault,
                      orElse: () => items.first,
                    );
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _openMailboxPickerSheet(
              items,
              mailHost: mailHost,
              mailboxId: mailboxId,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      current?.displayName ?? 'noMailboxes'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Symbols.expand_more, size: 20),
                ],
              ),
            ),
          );
        }
        return _MailboxSelector(
          mailboxes: items,
          mailHost: mailHost,
          selectedId: mailboxId,
          onSelected: (id) {
            if (id != null) _selectMailbox(id);
          },
          onCreate: () => _createMailbox(context),
        );
      },
    );
  }

  String? _effectiveMailboxId([
    List<MailMailbox>? mailboxes,
    String? selectedId,
  ]) {
    final items = mailboxes ?? ref.read(mailboxesProvider).value;
    if (items == null || items.isEmpty) return null;
    if (items.any((mailbox) => mailbox.id == selectedId)) {
      return selectedId;
    }
    return items
        .firstWhere((mailbox) => mailbox.isDefault, orElse: () => items.first)
        .id;
  }

  bool get _hasDiscoveryFilters =>
      _deliveryStatus != null ||
      _isFlagged != null ||
      _from != null ||
      _to != null ||
      _hasAttachments != null;

  EmailListFilter _emailFilter({
    String? mailboxId,
    required String folder,
  }) => (
    mailboxId: mailboxId,
    folder: folder,
    q: _searchController.text.trim().isEmpty
        ? null
        : _searchController.text.trim(),
    status: _deliveryStatus,
    isFlagged: _isFlagged,
    from: _from,
    to: _to,
    hasAttachments: _hasAttachments,
  );

  Future<void> _showEmailFilters(BuildContext context) async {
    final filter = await showDialog<_EmailDiscoveryFilter>(
      context: context,
      builder: (_) => _EmailFilterSheet(
        initial: _EmailDiscoveryFilter(
          status: _deliveryStatus,
          isFlagged: _isFlagged,
          from: _from,
          to: _to,
          hasAttachments: _hasAttachments,
        ),
      ),
    );
    if (filter == null || !mounted) return;
    setState(() {
      _deliveryStatus = filter.status;
      _isFlagged = filter.isFlagged;
      _from = filter.from;
      _to = filter.to;
      _hasAttachments = filter.hasAttachments;
      _selectedThreadId = null;
      _take = kThreadPageSize;
    });
    ref.invalidate(threadsProvider);
  }

  Widget _buildEmailList(
    String? mailHost, {
    String? mailboxId,
    required String folder,
    required Widget mailboxSelector,
  }) {
    final wide = isWideScreen(context);
    final compose = FloatingActionButton(
      heroTag: 'mail-compose-fab',
      tooltip: 'compose'.tr(),
      onPressed: () => _compose(context),
      child: const Icon(Symbols.edit),
    );
    final list = Column(
      children: [
        if (wide) ...[
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _MailListHeader(
                mailboxSelector: mailboxSelector,
                searchField: _buildSearchField(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                searchOpen: _searchOpen,
                onToggleSearch: _toggleSearch,
                hasDiscoveryFilters: _hasDiscoveryFilters,
                onOpenSettings: () => _openSettings(context),
                onShowFilters: () => _showEmailFilters(context),
              ),
            ),
          ),
        ],
        Expanded(
          // Crossfade between lists when the rail (or bottom bar) switches
          // mailbox or folder, so the reload doesn't blink from a stale list
          // to a spinner.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _EmailThreadList(
              key: ValueKey('$mailboxId/$folder'),
              query: (
                filter: _emailFilter(mailboxId: mailboxId, folder: folder),
                take: _take,
              ),
              mailHost: mailHost,
              selectedThreadId: _selectedThreadId,
              onOpen: (thread) => _openThread(context, thread),
              onToggleStar: _toggleThreadStar,
              onToggleRead: _toggleThreadRead,
              onDelete: (context, thread) => _deleteThread(context, thread),
              onMove: (thread, folder) => _moveThread(thread, folder),
              onRefresh: () => _refreshEmails(ref),
              onLoadMore: _loadMoreThreads,
            ),
          ),
        ),
      ],
    );

    // A phone gets the bare list under an app bar: the inset card only reads
    // as a pane when the detail view sits next to it.
    if (!wide) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: _buildMailAppBar(mailboxSelector),
        body: list,
        floatingActionButton: compose,
      );
    }
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          list,
          Positioned(right: 16, bottom: 16, child: compose),
        ],
      ),
    );
  }

  /// Search input, decorated for the wide header box or bare for the app bar.
  Widget _buildSearchField({InputBorder? border}) => TextField(
    controller: _searchController,
    onChanged: _onSearchChanged,
    autofocus: true,
    decoration: InputDecoration(
      isDense: true,
      hintText: 'searchEmailsHint'.tr(),
      prefixIcon: const Icon(Symbols.search, size: 20),
      border: border,
    ),
  );

  /// Phone chrome: the drawer, the active inbox and the header actions live in
  /// an app bar instead of the wide header row.
  PreferredSizeWidget _buildMailAppBar(Widget mailboxSelector) => AppBar(
    leading: _searchOpen
        ? IconButton(
            tooltip: 'clearSearch'.tr(),
            onPressed: _toggleSearch,
            icon: const Icon(Symbols.close),
          )
        : appBarDrawerButton(context),
    titleSpacing: 0,
    title: _searchOpen
        ? _buildSearchField(border: InputBorder.none)
        : mailboxSelector,
    actions: _searchOpen
        ? const []
        : [
            IconButton(
              tooltip: 'searchEmails'.tr(),
              onPressed: _toggleSearch,
              icon: const Icon(Symbols.search, size: 20),
            ),
            IconButton(
              tooltip: 'mailSettings'.tr(),
              onPressed: () => _openSettings(context),
              icon: const Icon(Symbols.settings, size: 20),
            ),
            IconButton(
              tooltip: 'emailFilters'.tr(),
              onPressed: () => _showEmailFilters(context),
              icon: Badge(
                isLabelVisible: _hasDiscoveryFilters,
                child: const Icon(Symbols.filter_alt, size: 20),
              ),
            ),
          ],
  );

  Future<void> _refreshEmails(WidgetRef ref) async {
    setState(() => _take = kThreadPageSize);
    ref.invalidate(threadsProvider);
  }

  /// Grows the conversation page. ElecPostal clamps `take` above
  /// [kMaxThreadTake] back to its default, so the list stops there.
  void _loadMoreThreads() {
    final next = _take + kThreadPageSize;
    setState(() => _take = next > kMaxThreadTake ? kMaxThreadTake : next);
  }

  void _openThread(BuildContext context, MailThread thread) {
    final wide = isWideScreen(context);
    setState(() => _selectedThreadId = thread.id);
    if (thread.unreadCount > 0) {
      unawaited(_markThreadRead(thread));
    }
    final route = MailDetailRoute(emailId: thread.latestMessage.id);
    if (wide) {
      context.router.navigate(route);
    } else {
      context.router.push(route);
    }
  }

  /// Reading a conversation marks all of it read, so the unread count on the
  /// row cannot survive the tap that opened it.
  Future<void> _markThreadRead(MailThread thread) async {
    try {
      final client = ref.read(wattEngineClientProvider);
      final messages = await _threadMessages(ref, thread);
      await Future.wait(
        messages
            .where((message) => !message.isRead)
            .map((message) => client.markEmailRead(message.id)),
      );
      _invalidateMail(ref);
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  Future<void> _toggleThreadStar(MailThread thread) async {
    final starred = !thread.latestMessage.isStarred;
    await _applyToThread(
      ref,
      thread,
      (client, message) => client.starEmail(message.id, starred: starred),
    );
  }

  Future<void> _toggleThreadRead(MailThread thread) async {
    final markRead = thread.unreadCount > 0;
    await _applyToThread(
      ref,
      thread,
      (client, message) => markRead
          ? client.markEmailRead(message.id)
          : client.markEmailUnread(message.id),
    );
  }

  Future<void> _moveThread(MailThread thread, String folder) async {
    await _applyToThread(
      ref,
      thread,
      (client, message) => client.moveEmail(message.id, folder),
    );
    showSnackBar(
      'movedToFolder'.tr(namedArgs: {'folder': mailFolderLabel(folder)}),
    );
  }

  Future<void> _deleteThread(BuildContext context, MailThread thread) async {
    final confirmed = await showConfirmAlert(
      'deleteThreadConfirm'.tr(
        namedArgs: {
          'subject': thread.displaySubject,
          'count': thread.messageCount.toString(),
        },
      ),
      'delete'.tr(),
      icon: Symbols.delete,
      isDanger: true,
      confirmLabel: 'delete'.tr(),
    );
    if (!confirmed) return;
    await _applyToThread(
      ref,
      thread,
      (client, message) => client.deleteEmail(message.id),
    );
    if (!context.mounted) return;
    showSnackBar('emailDeleted'.tr());
  }

  void _compose(BuildContext context, {MailEmail? replyingTo}) {
    final route = MailComposeRoute(replyToId: replyingTo?.id);
    if (isWideScreen(context)) {
      context.router.navigate(route);
    } else {
      context.router.push(route);
    }
  }

  Future<void> _createMailbox(BuildContext context) =>
      createMailboxAction(context, ref);

  void _openSettings(BuildContext context) {
    final route = MailSettingsRoute();
    if (isWideScreen(context)) {
      context.router.navigate(route);
    } else {
      context.router.push(route);
    }
  }
}

/// Result of the inbox picker sheet: either a mailbox to switch to, or a
/// request to create a new mailbox.
class MailboxPickerResult {
  const MailboxPickerResult.mailbox(this.mailboxId) : createNew = false;

  const MailboxPickerResult.createNew() : mailboxId = null, createNew = true;

  final String? mailboxId;
  final bool createNew;
}

/// Creates a new ElecPostal mailbox in the active workspace.
Future<void> createMailboxAction(BuildContext context, WidgetRef ref) async {
  final workspace = await ref.read(selectedWorkspaceProvider.future);
  if (!context.mounted) return;
  if (workspace == null) {
    showSnackBar('selectAWorkspaceFirst'.tr());
    return;
  }
  final draft = await showModalBottomSheet<_MailboxDraft>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CreateMailboxSheet(),
  );
  if (draft == null) return;
  try {
    await ref
        .read(wattEngineClientProvider)
        .createMailbox(
          address: draft.address,
          name: draft.name,
          workspaceId: workspace.id,
          isDefault: draft.isDefault,
        );
    ref.invalidate(mailboxesProvider);
    if (context.mounted) showSnackBar('mailboxCreated'.tr());
  } catch (error) {
    showSnackBar(error.toString());
  }
}

/// Shows a bottom sheet listing every mailbox so the user can switch inboxes
/// when they do not all fit in the bottom navigation bar.
Future<MailboxPickerResult?> showMailboxPickerSheet(
  BuildContext context, {
  required List<MailMailbox> mailboxes,
  required String? mailHost,
  required String? selectedId,
}) {
  return showModalBottomSheet<MailboxPickerResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MailboxPickerSheet(
      mailboxes: mailboxes,
      mailHost: mailHost,
      selectedId: selectedId,
    ),
  );
}

class _MailboxPickerSheet extends StatelessWidget {
  const _MailboxPickerSheet({
    required this.mailboxes,
    required this.mailHost,
    required this.selectedId,
  });

  final List<MailMailbox> mailboxes;
  final String? mailHost;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SheetScaffold(
      titleText: 'allInboxes'.tr(),
      heightFactor: 0.7,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          for (final mailbox in mailboxes)
            ListTile(
              leading: Icon(
                mailbox.id == selectedId ? Symbols.mail : Symbols.mail_outline,
                color: mailbox.id == selectedId
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
                fill: mailbox.id == selectedId ? 1 : 0,
              ),
              title: Text(
                mailbox.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                mailbox.fullAddress(mailHost),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: mailbox.id == selectedId
                  ? Icon(Symbols.check, color: scheme.primary)
                  : null,
              onTap: () => Navigator.of(
                context,
              ).pop(MailboxPickerResult.mailbox(mailbox.id)),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Symbols.add),
            title: Text('newMailbox'.tr()),
            onTap: () => Navigator.of(
              context,
            ).pop(const MailboxPickerResult.createNew()),
          ),
        ],
      ),
    );
  }
}

@RoutePage()
class MailDetailPage extends ConsumerWidget {
  const MailDetailPage({super.key, @PathParam('id') required this.emailId});

  final String emailId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(emailProvider(emailId));
    final mailHost = ref.watch(mailHostProvider).value;

    return email.when(
      loading: () => Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: const PageLoading(),
      ),
      error: (error, _) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: PageError(
          message: error.toString(),
          onRetry: () => ref.invalidate(emailProvider(emailId)),
        ),
      ),
      data: (value) {
        // The conversation is fetched separately: the route carries one
        // message, and a thread's older messages live behind `GET /threads/:id`.
        final conversation = ref.watch(threadProvider(value.threadKey));
        return _EmailDetailPanel(
          key: ValueKey(value.threadKey),
          email: value,
          conversation: conversation.value,
          mailHost: mailHost,
          workspaceId:
              value.mailbox?.workspaceId ??
              ref.watch(selectedWorkspaceProvider).value?.id,
          onReply: (message) => _composeEmail(context, message),
          onReplyAll: (message) =>
              _composeEmail(context, message, replyAll: true),
          onForward: (message) => _forwardEmail(context, message),
          onResend: (message) => _resendEmail(ref, message),
          onToggleRead: (message) => _toggleEmailRead(ref, message),
          onToggleStar: (message) => _toggleEmailStar(ref, message),
          onMove: (message, folder) => _moveEmail(context, ref, message, folder),
          onDownloadEml: (message) =>
              _downloadEmailEml(context, ref, message),
          onDelete: (message) => _deleteEmail(context, ref, message),
          onClose: () => context.router.pop(),
        );
      },
    );
  }
}

/// Marks every mail surface stale after a write: the conversation list, the
/// conversations the detail pane can open, and the message detail itself.
void _invalidateMail(WidgetRef ref) {
  ref.invalidate(threadsProvider);
  ref.invalidate(threadProvider);
  ref.invalidate(emailProvider);
}

/// Every message of [thread]. Single-message conversations come straight from
/// the list payload; longer ones are fetched once and cached per thread id.
Future<List<MailEmail>> _threadMessages(
  WidgetRef ref,
  MailThread thread,
) async {
  if (!thread.isMultiMessage) {
    final message = thread.latestMessage;
    return message.id.isEmpty ? const [] : [message];
  }
  return ref.read(threadProvider(thread.id).future);
}

/// Runs a per-message mutation across a whole conversation, so an action on a
/// row applies to the conversation and not only to its newest message.
Future<void> _applyToThread(
  WidgetRef ref,
  MailThread thread,
  Future<void> Function(WattEngineClient client, MailEmail message) action,
) async {
  try {
    final client = ref.read(wattEngineClientProvider);
    final messages = await _threadMessages(ref, thread);
    await Future.wait(messages.map((message) => action(client, message)));
    _invalidateMail(ref);
  } catch (error) {
    showSnackBar(error.toString());
  }
}

Future<void> _toggleEmailStar(WidgetRef ref, MailEmail email) async {
  try {
    await ref
        .read(wattEngineClientProvider)
        .starEmail(email.id, starred: !email.isStarred);
    _invalidateMail(ref);
  } catch (error) {
    showSnackBar(error.toString());
  }
}

/// Fetches a freshly serialized `.eml` and opens the platform save dialog.
Future<void> _downloadEmailEml(
  BuildContext context,
  WidgetRef ref,
  MailEmail email,
) async {
  try {
    final bytes = await ref
        .read(wattEngineClientProvider)
        .downloadEmailEml(email.id);
    final subject = email.subject.trim();
    final name = subject.isEmpty
        ? 'email-${email.id}'
        : subject.replaceAll(RegExp(r'[/\\:*?"<>|\s]+'), ' ');

    await FileSaver.instance.saveAs(
      name: name,
      bytes: bytes,
      fileExtension: 'eml',
      mimeType: MimeType.custom,
      customMimeType: 'message/rfc822',
      dialogTitle: 'downloadEml'.tr(),
    );
  } catch (error) {
    showSnackBar(error.toString());
  }
}

Future<void> _moveEmail(
  BuildContext context,
  WidgetRef ref,
  MailEmail email,
  String folder,
) async {
  try {
    await ref.read(wattEngineClientProvider).moveEmail(email.id, folder);
    _invalidateMail(ref);
    if (context.mounted) context.router.pop();
    showSnackBar(
      'movedToFolder'.tr(namedArgs: {'folder': mailFolderLabel(folder)}),
    );
  } catch (error) {
    showSnackBar(error.toString());
  }
}

void _forwardEmail(BuildContext context, MailEmail email) {
  final route = MailComposeRoute(forwardId: email.id);
  if (isWideScreen(context)) {
    context.router.navigate(route);
  } else {
    context.router.push(route);
  }
}

void _composeEmail(
  BuildContext context,
  MailEmail replyingTo, {
  bool replyAll = false,
}) {
  final route = MailComposeRoute(replyToId: replyingTo.id, replyAll: replyAll);
  if (isWideScreen(context)) {
    context.router.navigate(route);
  } else {
    context.router.push(route);
  }
}

Future<void> _resendEmail(WidgetRef ref, MailEmail email) async {
  try {
    await ref.read(wattEngineClientProvider).resendEmail(email.id);
    _invalidateMail(ref);
    showSnackBar('emailResent'.tr());
  } catch (error) {
    showSnackBar(error.toString());
  }
}

Future<void> _toggleEmailRead(WidgetRef ref, MailEmail email) async {
  try {
    if (email.isRead) {
      await ref.read(wattEngineClientProvider).markEmailUnread(email.id);
    } else {
      await ref.read(wattEngineClientProvider).markEmailRead(email.id);
    }
    _invalidateMail(ref);
  } catch (error) {
    showSnackBar(error.toString());
  }
}

Future<void> _deleteEmail(
  BuildContext context,
  WidgetRef ref,
  MailEmail email,
) async {
  final confirmed = await showConfirmAlert(
    'deleteEmailConfirm'.tr(namedArgs: {'subject': email.displaySubject}),
    'deleteEmail'.tr(),
    icon: Symbols.delete,
    isDanger: true,
    confirmLabel: 'delete'.tr(),
  );
  if (!confirmed) return;
  try {
    await ref.read(wattEngineClientProvider).deleteEmail(email.id);
    _invalidateMail(ref);
    if (context.mounted) context.router.pop();
    showSnackBar('emailDeleted'.tr());
  } catch (error) {
    showSnackBar(error.toString());
  }
}

class _MailListHeader extends StatelessWidget {
  const _MailListHeader({
    required this.mailboxSelector,
    required this.searchField,
    required this.searchOpen,
    required this.onToggleSearch,
    required this.hasDiscoveryFilters,
    required this.onOpenSettings,
    required this.onShowFilters,
  });

  final Widget mailboxSelector;
  final Widget searchField;
  final bool searchOpen;
  final VoidCallback onToggleSearch;
  final bool hasDiscoveryFilters;
  final VoidCallback onOpenSettings;
  final VoidCallback onShowFilters;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(child: mailboxSelector),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'searchEmails'.tr(),
                onPressed: onToggleSearch,
                icon: Icon(
                  searchOpen ? Symbols.close : Symbols.search,
                  size: 20,
                ),
              ),
              IconButton(
                tooltip: 'mailSettings'.tr(),
                onPressed: onOpenSettings,
                icon: const Icon(Symbols.settings, size: 20),
              ),
              IconButton(
                tooltip: 'emailFilters'.tr(),
                onPressed: onShowFilters,
                icon: Badge(
                  isLabelVisible: hasDiscoveryFilters,
                  child: const Icon(Symbols.filter_alt, size: 20),
                ),
              ),
            ],
          ),
        ),
        if (searchOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: searchField,
          ),
      ],
    );
  }
}

/// Localized label for a mail folder id.
String mailFolderLabel(String folder) => switch (folder) {
  'sent' => 'folderSent'.tr(),
  'drafts' => 'folderDrafts'.tr(),
  'spam' => 'folderSpam'.tr(),
  'trash' => 'folderTrash'.tr(),
  'archive' => 'folderArchive'.tr(),
  _ => 'folderInbox'.tr(),
};

class _MailboxError extends StatelessWidget {
  const _MailboxError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Symbols.error,
          color: Theme.of(context).colorScheme.error,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        if (onRetry != null)
          IconButton(
            tooltip: 'retry'.tr(),
            onPressed: onRetry,
            icon: const Icon(Symbols.refresh, size: 20),
          ),
      ],
    );
  }
}

class _MailboxInvalidBanner extends StatelessWidget {
  const _MailboxInvalidBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Symbols.error, color: scheme.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _MailboxSelector extends StatelessWidget {
  const _MailboxSelector({
    required this.mailboxes,
    required this.mailHost,
    required this.selectedId,
    required this.onSelected,
    required this.onCreate,
  });

  final List<MailMailbox> mailboxes;
  final String? mailHost;
  final String? selectedId;
  final ValueChanged<String?> onSelected;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (mailboxes.isEmpty) {
      return Row(
        children: [
          Icon(Symbols.mail, color: scheme.onSurfaceVariant, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'noMailboxes'.tr(),
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: onCreate,
            icon: const Icon(Symbols.add, size: 18),
            label: Text('newMailbox'.tr()),
          ),
        ],
      );
    }

    final selected =
        mailboxes.where((m) => m.id == selectedId).firstOrNull ??
        mailboxes.firstWhere((m) => m.isDefault, orElse: () => mailboxes.first);

    return DropdownButtonFormField<String>(
      initialValue: selected.id,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: 'mailbox'.tr(),
        prefixIcon: const Icon(Symbols.mail),
        suffixIcon: IconButton(
          tooltip: 'newMailbox'.tr(),
          onPressed: onCreate,
          icon: const Icon(Symbols.add),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: [
        for (final mailbox in mailboxes)
          DropdownMenuItem(
            value: mailbox.id,
            child: Text(mailbox.fullAddress(mailHost)),
          ),
      ],
      onChanged: onSelected,
    );
  }
}

class _EmailDiscoveryFilter {
  const _EmailDiscoveryFilter({
    this.status,
    this.isFlagged,
    this.from,
    this.to,
    this.hasAttachments,
  });

  final String? status;
  final bool? isFlagged;
  final String? from;
  final String? to;
  final bool? hasAttachments;
}

class _EmailFilterSheet extends StatefulWidget {
  const _EmailFilterSheet({required this.initial});

  final _EmailDiscoveryFilter initial;

  @override
  State<_EmailFilterSheet> createState() => _EmailFilterSheetState();
}

class _EmailFilterSheetState extends State<_EmailFilterSheet> {
  late String? _status = widget.initial.status;
  late bool? _isFlagged = widget.initial.isFlagged;
  late bool? _hasAttachments = widget.initial.hasAttachments;
  late final _fromController = TextEditingController(text: widget.initial.from);
  late final _toController = TextEditingController(text: widget.initial.to);

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  void _apply() => Navigator.of(context).pop(
    _EmailDiscoveryFilter(
      status: _status,
      isFlagged: _isFlagged,
      from: _fromController.text.trim().isEmpty
          ? null
          : _fromController.text.trim(),
      to: _toController.text.trim().isEmpty ? null : _toController.text.trim(),
      hasAttachments: _hasAttachments,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'emailFilters'.tr(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _FilterFieldLabel(label: 'deliveryStatus'.tr()),
                const SizedBox(height: 6),
                DropdownButtonFormField<String?>(
                  initialValue: _status,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    DropdownMenuItem(value: null, child: Text('any'.tr())),
                    DropdownMenuItem(
                      value: 'sent',
                      child: Text('deliveryStatusSent'.tr()),
                    ),
                    DropdownMenuItem(
                      value: 'pending',
                      child: Text('deliveryStatusPending'.tr()),
                    ),
                    DropdownMenuItem(
                      value: 'failed',
                      child: Text('deliveryStatusFailed'.tr()),
                    ),
                    DropdownMenuItem(
                      value: 'not_configured',
                      child: Text('deliveryStatusNotConfigured'.tr()),
                    ),
                  ],
                  onChanged: (value) => setState(() => _status = value),
                ),
                const SizedBox(height: 12),
                _FilterFieldLabel(label: 'emailFromFilter'.tr()),
                const SizedBox(height: 6),
                TextField(
                  controller: _fromController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(isDense: true),
                ),
                const SizedBox(height: 12),
                _FilterFieldLabel(label: 'emailToFilter'.tr()),
                const SizedBox(height: 6),
                TextField(
                  controller: _toController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(isDense: true),
                ),
                const SizedBox(height: 16),
                _BooleanFilterField(
                  label: 'flagged'.tr(),
                  value: _isFlagged,
                  onChanged: (value) => setState(() => _isFlagged = value),
                ),
                const SizedBox(height: 12),
                _BooleanFilterField(
                  label: 'hasAttachments'.tr(),
                  value: _hasAttachments,
                  onChanged: (value) => setState(() => _hasAttachments = value),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(const _EmailDiscoveryFilter()),
                      child: Text('clear'.tr()),
                    ),
                    const Spacer(),
                    FilledButton(onPressed: _apply, child: Text('apply'.tr())),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterFieldLabel extends StatelessWidget {
  const _FilterFieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text(label, style: Theme.of(context).textTheme.labelLarge);
}

class _BooleanFilterField extends StatelessWidget {
  const _BooleanFilterField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FilterFieldLabel(label: label),
        const SizedBox(height: 6),
        DropdownButtonFormField<bool?>(
          initialValue: value,
          decoration: const InputDecoration(isDense: true),
          items: [
            DropdownMenuItem(value: null, child: Text('any'.tr())),
            DropdownMenuItem(value: true, child: Text('yes'.tr())),
            DropdownMenuItem(value: false, child: Text('no'.tr())),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Conversations per fetch, and ElecPostal's cap on `take`: anything above the
/// cap is clamped back to its default, so the list stops asking there.
const kThreadPageSize = 20;
const kMaxThreadTake = 200;

/// Compact list timestamp: time of day for today, month/day otherwise.
String _mailTimestamp(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
}

/// The mail list is a list of conversations: one row per thread, with the
/// newest message's sender, subject and preview, and a badge for the number of
/// messages behind it.
class _EmailThreadList extends ConsumerStatefulWidget {
  const _EmailThreadList({
    super.key,
    required this.query,
    required this.mailHost,
    required this.selectedThreadId,
    required this.onOpen,
    required this.onToggleStar,
    required this.onToggleRead,
    required this.onDelete,
    required this.onMove,
    required this.onRefresh,
    required this.onLoadMore,
  });

  final MailThreadsQuery query;
  final String? mailHost;
  final String? selectedThreadId;
  final ValueChanged<MailThread> onOpen;
  final ValueChanged<MailThread> onToggleStar;
  final ValueChanged<MailThread> onToggleRead;
  final Future<void> Function(BuildContext, MailThread) onDelete;
  final Future<void> Function(MailThread, String) onMove;
  final VoidCallback onRefresh;
  final VoidCallback onLoadMore;

  @override
  ConsumerState<_EmailThreadList> createState() => _EmailThreadListState();
}

class _EmailThreadListState extends ConsumerState<_EmailThreadList> {
  /// Distance from the end of the list that triggers the next page.
  static const _loadMoreExtent = 320.0;

  /// Last listing rendered for [widget.query]'s filter. Growing the page size
  /// re-fetches the same conversations, so the previous listing stays on screen
  /// while the larger one loads instead of flashing a spinner over the list.
  PaginatedResult<MailThread>? _cached;
  EmailListFilter? _cachedFilter;

  @override
  Widget build(BuildContext context) {
    final listing = ref.watch(threadsProvider(widget.query));
    final loaded = listing.value;
    if (loaded != null) {
      _cached = loaded;
      _cachedFilter = widget.query.filter;
    }
    // While a larger page (or a refresh) is in flight, keep the previous
    // listing — but never conversations from a filter the user has left.
    final page = loaded ?? (_cachedFilter == widget.query.filter ? _cached : null);
    ref.listen(threadsProvider(widget.query), (previous, next) {
      final error = next.error;
      // A failure with rows on screen keeps them; say what went wrong rather
      // than blanking the list. Without rows the error page below speaks.
      if (error != null && _cachedFilter == widget.query.filter) {
        showSnackBar(error.toString());
      }
    });
    if (page == null) {
      if (listing.hasError) {
        return PageError(
          message: listing.error.toString(),
          onRetry: widget.onRefresh,
        );
      }
      return const PageLoading();
    }
    final items = page.items;
    if (items.isEmpty) {
      return EmptyState(
        icon: Symbols.mail_outline,
        title: 'noEmails'.tr(),
        message: 'noEmailsDescription'.tr(),
      );
    }
    final senders =
        ref.watch(mailSenderIndexProvider).value ??
        const <String, MailAddressSuggestion>{};
    final canLoadMore =
        widget.query.take < kMaxThreadTake && items.length < page.totalCount;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Only the reader's own scrolling extends the page, and only once the
        // current page has settled, so one flick cannot chain requests.
        if (!listing.isLoading &&
            canLoadMore &&
            notification.metrics.extentAfter < _loadMoreExtent) {
          widget.onLoadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () async => widget.onRefresh(),
        child: ListView.builder(
          itemCount: items.length + (canLoadMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == items.length) {
              return _ThreadListFooter(
                loading: listing.isLoading,
                shown: items.length,
                total: page.totalCount,
              );
            }
            final thread = items[index];
            return _EmailThreadTile(
              thread: thread,
              mailHost: widget.mailHost,
              senders: senders,
              selected: thread.id == widget.selectedThreadId,
              onTap: () => widget.onOpen(thread),
              onToggleStar: () => widget.onToggleStar(thread),
              onToggleRead: () => widget.onToggleRead(thread),
              onDelete: () => widget.onDelete(context, thread),
              onMove: (folder) => widget.onMove(thread, folder),
            );
          },
        ),
      ),
    );
  }
}

/// End-of-list row: a spinner while the next page loads, otherwise how much of
/// the conversation list is on screen.
class _ThreadListFooter extends StatelessWidget {
  const _ThreadListFooter({
    required this.loading,
    required this.shown,
    required this.total,
  });

  final bool loading;
  final int shown;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (!loading) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'threadsShown'.tr(
              namedArgs: {'shown': '$shown', 'total': '$total'},
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _EmailThreadTile extends StatelessWidget {
  const _EmailThreadTile({
    required this.thread,
    required this.mailHost,
    required this.senders,
    required this.onTap,
    required this.onToggleStar,
    required this.onToggleRead,
    required this.onDelete,
    required this.onMove,
    this.selected = false,
  });

  final MailThread thread;
  final String? mailHost;
  final Map<String, MailAddressSuggestion> senders;
  final VoidCallback onTap;
  final VoidCallback onToggleStar;
  final VoidCallback onToggleRead;
  final VoidCallback onDelete;
  final ValueChanged<String> onMove;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final latest = thread.latestMessage;
    final fromAddress = latest.from?.fullAddress(mailHost) ?? '';
    final fromName = latest.from?.displayName ?? '';
    final from = fromName.isNotEmpty ? fromName : fromAddress;
    final unread = !thread.isRead;
    final weight = unread ? FontWeight.w600 : FontWeight.normal;
    final timestamp = _mailTimestamp(thread.latestAt ?? latest.createdAt);

    return ContextMenuWidget(
      menuProvider: (_) => Menu(
        children: emailContextMenuItems(
          // The actions cover the conversation, so the read state is the
          // thread's — not the newest message's — to keep the labels honest.
          isRead: thread.isRead,
          isStarred: latest.isStarred,
          onToggleRead: onToggleRead,
          onToggleStar: onToggleStar,
          onMove: onMove,
          onDelete: onDelete,
        ),
      ),
      child: ListTile(
        selected: selected,
        selectedTileColor: scheme.secondaryContainer.withValues(alpha: 0.3),
        shape: const RoundedRectangleBorder(),
        leading: _SenderAvatar(
          url: emailAvatarUrl(senders[fromAddress.trim().toLowerCase()]),
          name: from,
          unread: unread,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                from,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(fontWeight: weight),
              ),
            ),
            if (thread.isMultiMessage) ...[
              _ThreadCountBadge(count: thread.messageCount),
              const SizedBox(width: 6),
            ],
            if (timestamp.isNotEmpty)
              Text(
                timestamp,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              thread.displaySubject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(fontWeight: weight),
            ),
            if (latest.previewText.isNotEmpty)
              Text(
                latest.previewText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            if (latest.hasDeliveryStatus && !latest.isDraft) ...[
              const SizedBox(height: 6),
              _DeliveryStatusChip(status: latest.deliveryStatus!),
            ],
          ],
        ),
        isThreeLine: false,
        onTap: onTap,
      ),
    );
  }
}

/// How many messages a conversation holds, on rows with more than one.
class _ThreadCountBadge extends StatelessWidget {
  const _ThreadCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'threadMessageCount'.plural(count),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$count',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Sender avatar for a mail list row: network image when the senders index
/// has one, initials otherwise. An unread message gets a dot so the read
/// state survives the switch from the mail-glyph leading.
class _SenderAvatar extends StatelessWidget {
  const _SenderAvatar({
    required this.url,
    required this.name,
    this.unread = false,
  });

  final String? url;
  final String name;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallbackText = _senderInitials(name);
    final fallbackStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: scheme.onPrimaryContainer,
    );

    final Widget avatar;
    if (url == null || url!.isEmpty) {
      avatar = CircleAvatar(
        radius: 18,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: Text(fallbackText, style: fallbackStyle),
      );
    } else {
      avatar = ClipOval(
        child: Image.network(
          url!,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => CircleAvatar(
            radius: 18,
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: Text(fallbackText, style: fallbackStyle),
          ),
        ),
      );
    }

    if (!unread) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.surface, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// Initials for the sender-avatar fallback: first grapheme, uppercase, '?'
/// for an empty name. Matches the app's other avatar fallbacks (gate page,
/// boards picker); the CJK/emoji-aware variant lives in the uncommitted
/// drive port and is not reachable from tracked code.
String _senderInitials(String name) {
  final normalized = name.trim();
  if (normalized.isEmpty) return '?';
  return normalized.characters.first.toUpperCase();
}

/// Menu items shown when a message tile or its detail view is right-clicked.
///
/// Kept as a plain function so the menu contract (destructive delete, star
/// check state, folder moves) is unit-testable without a native menu.
List<MenuElement> emailContextMenuItems({
  required bool isRead,
  required bool isStarred,
  required VoidCallback onToggleRead,
  required VoidCallback onToggleStar,
  required ValueChanged<String> onMove,
  required VoidCallback onDelete,
}) => [
  MenuAction(
    title: (isRead ? 'markUnread' : 'markRead').tr(),
    image: MenuImage.icon(
      isRead ? Symbols.mark_email_unread : Symbols.mark_email_read,
    ),
    callback: onToggleRead,
  ),
  MenuAction(
    title: (isStarred ? 'unstar' : 'star').tr(),
    image: MenuImage.icon(isStarred ? Symbols.star : Symbols.star_outline),
    state: isStarred ? MenuActionState.checkOn : MenuActionState.none,
    callback: onToggleStar,
  ),
  MenuSeparator(),
  MenuAction(
    title: 'folderArchive'.tr(),
    image: MenuImage.icon(Symbols.archive),
    callback: () => onMove('archive'),
  ),
  MenuAction(
    title: 'folderSpam'.tr(),
    image: MenuImage.icon(Symbols.report),
    callback: () => onMove('spam'),
  ),
  MenuAction(
    title: 'folderTrash'.tr(),
    image: MenuImage.icon(Symbols.delete_outline),
    callback: () => onMove('trash'),
  ),
  MenuSeparator(),
  MenuAction(
    title: 'delete'.tr(),
    image: MenuImage.icon(Symbols.delete),
    attributes: const MenuActionAttributes(destructive: true),
    callback: onDelete,
  ),
];

class _DeliveryStatusChip extends StatelessWidget {
  const _DeliveryStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (tone, labelKey, icon) = switch (status.toLowerCase()) {
      'sent' => (StatusChipTone.secondary, 'deliveryStatusSent', Symbols.check),
      'pending' => (
        StatusChipTone.primary,
        'deliveryStatusPending',
        Symbols.schedule,
      ),
      'failed' => (StatusChipTone.error, 'deliveryStatusFailed', Symbols.error),
      'not_configured' => (
        StatusChipTone.neutral,
        'deliveryStatusNotConfigured',
        Symbols.block,
      ),
      _ => (StatusChipTone.neutral, 'deliveryStatusUnknown', Symbols.help),
    };
    return StatusChip(label: labelKey.tr(), icon: icon, tone: tone);
  }
}

class _EmailDetailPanel extends StatefulWidget {
  const _EmailDetailPanel({
    super.key,
    required this.email,
    required this.conversation,
    required this.mailHost,
    required this.workspaceId,
    required this.onReply,
    required this.onReplyAll,
    required this.onForward,
    required this.onResend,
    required this.onToggleRead,
    required this.onToggleStar,
    required this.onMove,
    required this.onDelete,
    required this.onDownloadEml,
    required this.onClose,
  });

  /// The message the route opened; the conversation starts selected on it.
  final MailEmail email;

  /// Every message of the conversation, oldest first. Null while it loads or
  /// when the message has no conversation behind it, in which case the pane
  /// shows [email] on its own.
  final List<MailEmail>? conversation;
  final String? mailHost;
  final String? workspaceId;
  final ValueChanged<MailEmail> onReply;
  final ValueChanged<MailEmail> onReplyAll;
  final ValueChanged<MailEmail> onForward;
  final ValueChanged<MailEmail> onResend;
  final ValueChanged<MailEmail> onToggleRead;
  final ValueChanged<MailEmail> onToggleStar;
  final void Function(MailEmail message, String folder) onMove;
  final ValueChanged<MailEmail> onDelete;
  final ValueChanged<MailEmail> onDownloadEml;
  final VoidCallback onClose;

  @override
  State<_EmailDetailPanel> createState() => _EmailDetailPanelState();
}

class _EmailDetailPanelState extends State<_EmailDetailPanel> {
  /// Initial header height before the summary is measured; replaced by the
  /// exact content height after the first layout so the expanded header
  /// hugs the summary with no dead space.
  static const _estimateSummaryHeight = 180.0;

  /// Window after the pane resizes itself during which the body's offset is
  /// only re-based, never read as a scroll direction.
  static const _layoutSettleWindow = Duration(milliseconds: 250);

  final _summaryKey = GlobalKey();
  double? _summaryHeight;
  DateTime? _layoutChangedAt;

  /// Message of the conversation the pane is reading.
  String? _selectedId;

  /// The message body is its own scroll surface, so the header follows the
  /// direction of that scroll: down hides it, up (or reaching the top) brings
  /// it back.
  final _header = HeaderCollapseController();

  /// Attachments are revealed once the reader reaches the end of the message.
  final _footer = BodyFooterRevealController();

  List<MailEmail> get _conversation {
    final conversation = widget.conversation;
    if (conversation == null || conversation.isEmpty) return [widget.email];
    return conversation;
  }

  /// The message the toolbar, header and action bar act on.
  MailEmail get _selected {
    final selectedId = _selectedId;
    if (selectedId != null) {
      for (final message in _conversation) {
        if (message.id == selectedId) return message;
      }
    }
    return widget.email;
  }

  @override
  void initState() {
    super.initState();
    _selectedId = widget.email.id;
  }

  @override
  void didUpdateWidget(_EmailDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.email.id != widget.email.id) {
      _selectedId = widget.email.id;
      _resetBody();
      return;
    }
    // A freshly loaded conversation can retire the selected message id; fall
    // back to the one the route opened rather than showing a blank pane.
    if (!_conversation.any((message) => message.id == _selectedId)) {
      _selectedId = widget.email.id;
    }
  }

  /// Reading a different message resets the header, scroll and footer state,
  /// which belong to the body that was on screen.
  void _resetBody() {
    _header.reset();
    _footer.reset();
    _summaryHeight = null;
  }

  void _selectMessage(MailEmail message) {
    if (message.id == _selectedId) return;
    setState(() {
      _selectedId = message.id;
      _resetBody();
    });
    _remeasureSummary();
  }

  void _onBodyScroll(EmailBodyScroll sample) {
    final changedAt = _layoutChangedAt;
    if (changedAt != null &&
        DateTime.now().difference(changedAt) < _layoutSettleWindow) {
      // We just resized the pane, so WebKit may have clamped the offset. Re-base
      // both controllers instead of reading that jump as reader input.
      _header.adoptOrigin(sample.y);
      _footer.adoptOrigin(sample.y);
      return;
    }
    final headerChanged = _header.update(sample.y);
    final footerChanged = _footer.update(sample);
    if (headerChanged || footerChanged) {
      _layoutChangedAt = DateTime.now();
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _remeasureSummary();
  }

  void _remeasureSummary() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = _summaryKey.currentContext?.size;
      if (size == null || size.height <= 0) return;
      if (size.height != _summaryHeight) {
        setState(() => _summaryHeight = size.height);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final conversation = _conversation;
    final selected = _selected;
    final summaryHeight = _summaryHeight ?? _estimateSummaryHeight;
    final resendable =
        !selected.isDraft &&
        selected.deliveryStatus?.toLowerCase() == 'failed';

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EmailToolbar(
            email: selected,
            onClose: widget.onClose,
            onToggleStar: () => widget.onToggleStar(selected),
            onToggleRead: () => widget.onToggleRead(selected),
            onMove: (folder) => widget.onMove(selected, folder),
            onDelete: () => widget.onDelete(selected),
            onDownloadEml: () => widget.onDownloadEml(selected),
          ),
          // The summary slides up under the toolbar as the body is scrolled
          // down and back out when it is scrolled up. OverflowBox keeps the
          // summary laid out at its own height while the clip animates, so it
          // is cropped instead of squeezed into a RenderFlex overflow — and
          // the height stays measurable for the next toggle.
          ClipRect(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: _header.expanded ? summaryHeight : 0,
              child: OverflowBox(
                alignment: Alignment.bottomCenter,
                minHeight: 0,
                maxHeight: double.infinity,
                child: _EmailSummary(
                  key: _summaryKey,
                  email: selected,
                  mailHost: widget.mailHost,
                ),
              ),
            ),
          ),
          // A conversation gets a switcher: only one body is mounted at a time,
          // because the message body owns the mouse wheel over its own area.
          if (conversation.length > 1)
            _ThreadMessageStrip(
              messages: conversation,
              selectedId: selected.id,
              mailHost: widget.mailHost,
              onSelect: _selectMessage,
            ),
          Expanded(
            child: _EmailDetailContent(
              key: ValueKey(selected.id),
              email: selected,
              workspaceId: widget.workspaceId,
              onBodyScroll: _onBodyScroll,
              // A footer with nothing to show would expand blank padding when
              // the reader reaches the end; keep it collapsed for emails
              // without attachments or delivery state.
              showFooter: _footer.visible && emailHasFooterContent(selected),
            ),
          ),
          _EmailActionBar(
            onReply: () => widget.onReply(selected),
            onReplyAll: () => widget.onReplyAll(selected),
            onForward: () => widget.onForward(selected),
            onResend: resendable ? () => widget.onResend(selected) : null,
          ),
        ],
      ),
    );
  }
}

/// Message switcher for a conversation, oldest first. The body below shows the
/// picked message, so a long thread stays readable one message at a time.
class _ThreadMessageStrip extends ConsumerWidget {
  const _ThreadMessageStrip({
    required this.messages,
    required this.selectedId,
    required this.mailHost,
    required this.onSelect,
  });

  final List<MailEmail> messages;
  final String selectedId;
  final String? mailHost;
  final ValueChanged<MailEmail> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final senders =
        ref.watch(mailSenderIndexProvider).value ??
        const <String, MailAddressSuggestion>{};

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SizedBox(
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: messages.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final message = messages[index];
            final address = message.from?.fullAddress(mailHost) ?? '';
            final name = message.from?.displayName ?? '';
            final from = name.isNotEmpty ? name : address;
            final timestamp = _mailTimestamp(message.createdAt);
            return ChoiceChip(
              selected: message.id == selectedId,
              showCheckmark: false,
              avatar: _SenderAvatar(
                url: emailAvatarUrl(senders[address.trim().toLowerCase()]),
                name: from,
                unread: !message.isRead,
              ),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  timestamp.isEmpty ? from : '$from · $timestamp',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              onSelected: (_) => onSelect(message),
            );
          },
        ),
      ),
    );
  }
}

/// Decides when the message header hides or comes back from the vertical
/// offset of the message body's own scroll surface.
///
/// Scrolling down past [threshold] hides it, scrolling up past the threshold
/// brings it back, and returning to the very top always restores it. Only the
/// movement in the current direction counts, so a trackpad jitter — or the
/// body reflowing because the header changed size — cannot flap the header.
class HeaderCollapseController {
  HeaderCollapseController({this.threshold = 24});

  /// Scroll distance in one direction before the header flips.
  final double threshold;

  double _lastY = 0;
  double _run = 0;
  bool _expanded = true;

  /// False right after [reset]: the next offset is adopted as the origin
  /// instead of being measured against a stale document position.
  bool _hasOrigin = true;

  bool get expanded => _expanded;

  /// Feeds the body's scroll offset; returns true when [expanded] changed.
  bool update(double y) {
    if (!_hasOrigin) {
      _hasOrigin = true;
      _lastY = y;
      return false;
    }
    final delta = y - _lastY;
    _lastY = y;
    if (delta == 0) return false;
    if (y <= 0) {
      _run = 0;
      if (!_expanded) {
        _expanded = true;
        return true;
      }
      return false;
    }
    // Accumulate only while the direction holds; a reversal starts over.
    _run = _run.sign == delta.sign ? _run + delta : delta;
    if (_run > threshold && _expanded) {
      _expanded = false;
      return true;
    }
    if (_run < -threshold && !_expanded) {
      _expanded = true;
      return true;
    }
    return false;
  }

  void reset() {
    _lastY = 0;
    _run = 0;
    _expanded = true;
    _hasOrigin = false;
  }

  /// Re-bases the scroll origin without changing [expanded]. Used when the pane
  /// resizes and WebKit clamps the offset — that jump is not the reader
  /// scrolling.
  void adoptOrigin(double y) {
    _hasOrigin = true;
    _lastY = y;
    _run = 0;
  }
}

/// One sample of the message body's own scroll position.
class EmailBodyScroll {
  const EmailBodyScroll({required this.y, this.maxY});

  /// How far the document has scrolled, in CSS pixels.
  final double y;

  /// Scrollable extent, `scrollHeight - innerHeight` — 0 means the message
  /// already fits the pane. Null until the first measurement lands.
  final double? maxY;

  /// Slack, so a body resting a pixel short of its end still counts as the end.
  static const _slack = 8.0;

  bool get atBottom => maxY != null && y >= maxY! - _slack;
}

/// Decides when the attachment footer is shown, from the body's scroll
/// position: it appears once the reader reaches the end of the message and goes
/// away again when the body is scrolled back up.
///
/// Only a *downward* arrival at the end reveals it. Revealing shrinks the body,
/// which moves the document's end back under the viewport — without the
/// direction check the footer would re-reveal itself the instant it hid.
class BodyFooterRevealController {
  BodyFooterRevealController({this.threshold = 24});

  /// Upward scroll distance before the footer goes away again.
  final double threshold;

  bool _visible = false;
  double _lastY = 0;
  double _run = 0;
  int _lastDirection = 0;

  bool get visible => _visible;

  /// Feeds a scroll sample; returns true when [visible] changed.
  bool update(EmailBodyScroll sample) {
    final delta = sample.y - _lastY;
    _lastY = sample.y;
    if (delta > 0) {
      _lastDirection = 1;
    } else if (delta < 0) {
      _lastDirection = -1;
    }

    if (sample.atBottom) {
      _run = 0;
      if (!_visible && _lastDirection >= 0) {
        _visible = true;
        return true;
      }
      return false;
    }

    _run = _run.sign == delta.sign ? _run + delta : delta;
    if (_run < -threshold && _visible) {
      _visible = false;
      return true;
    }
    return false;
  }

  void reset() {
    _visible = false;
    _lastY = 0;
    _run = 0;
    _lastDirection = 0;
  }

  /// Re-bases the scroll origin without changing [visible] or the remembered
  /// direction, for offset jumps caused by the pane resizing.
  void adoptOrigin(double y) {
    _lastY = y;
    _run = 0;
  }
}

/// Always-visible action row of the message pane. It stays put while
/// [_EmailSummary] slides away underneath it.
class _EmailToolbar extends StatelessWidget {
  const _EmailToolbar({
    required this.email,
    required this.onClose,
    required this.onToggleStar,
    required this.onToggleRead,
    required this.onMove,
    required this.onDelete,
    required this.onDownloadEml,
  });

  static const height = 56.0;

  final MailEmail email;
  final VoidCallback onClose;
  final VoidCallback onToggleStar;
  final VoidCallback onToggleRead;
  final ValueChanged<String> onMove;
  final VoidCallback onDelete;
  final VoidCallback onDownloadEml;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: height,
      child: Padding(
        padding: isWideScreen(context) ? const EdgeInsets.symmetric(horizontal: 8) : .zero,
        child: Row(
          children: [
            IconButton(
              tooltip: 'close'.tr(),
              onPressed: onClose,
              icon: const Icon(Symbols.close),
            ),
            const Spacer(),
            IconButton(
              tooltip: email.isStarred ? 'unstar'.tr() : 'star'.tr(),
              onPressed: onToggleStar,
              icon: Icon(
                email.isStarred ? Symbols.star : Symbols.star_outline,
                color: email.isStarred
                    ? Colors.amber.shade600
                    : scheme.onSurfaceVariant,
                fill: email.isStarred ? 1 : 0,
              ),
            ),
            IconButton(
              tooltip: email.isRead ? 'markUnread'.tr() : 'markRead'.tr(),
              onPressed: onToggleRead,
              icon: Icon(email.isRead ? Symbols.mail : Symbols.drafts),
            ),
            PopupMenuButton<String>(
              tooltip: 'more'.tr(),
              icon: const Icon(Symbols.more_vert),
              onSelected: (value) {
                if (value == 'archive') onMove('archive');
                if (value == 'spam') onMove('spam');
                if (value == 'trash') onMove('trash');
                if (value == 'download-eml') onDownloadEml();
              },
              itemBuilder: (_) => [
                if (email.folder != 'archive')
                  PopupMenuItem(
                    value: 'archive',
                    child: Text('folderArchive'.tr()),
                  ),
                if (email.folder != 'spam')
                  PopupMenuItem(value: 'spam', child: Text('folderSpam'.tr())),
                if (email.folder != 'trash')
                  PopupMenuItem(value: 'trash', child: Text('folderTrash'.tr())),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'download-eml',
                  child: Text('downloadEml'.tr()),
                ),
              ],
            ),
            IconButton(
              tooltip: 'delete'.tr(),
              onPressed: onDelete,
              icon: Icon(Symbols.delete, color: scheme.error),
            ),
          ],
        ),
      ),
    );
  }
}

/// Subject and recipient metadata, collapsed away as the body scrolls down.
class _EmailSummary extends StatelessWidget {
  const _EmailSummary({super.key, required this.email, required this.mailHost});

  final MailEmail email;
  final String? mailHost;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            email.displaySubject,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (email.summary case final summary?) ...[
            const SizedBox(height: 12),
            _EmailAiSummary(summary: summary),
          ],
          const SizedBox(height: 12),
          _EmailMetadata(
            email: email,
            mailHost: mailHost,
            dateStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// The assistant's summary of the message, above the recipient metadata.
///
/// ElecPostal generates it with the account's summarizer agent and stores it on
/// the message; the same text is the message's list preview. It reads here as a
/// distinct surface rather than as more header copy, so a reader can take in
/// what the mail says before scrolling into the (uncollapsed) body.
class _EmailAiSummary extends StatelessWidget {
  const _EmailAiSummary({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Symbols.auto_awesome, size: 15, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                'aiSummary'.tr(),
                style: text.labelMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            summary,
            style: text.bodyMedium?.copyWith(
              color: scheme.onSecondaryContainer,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Scroll surface for a plain-text message body.
///
/// It reports the body's metrics the way the web view reports its own: once
/// after the first layout, then on every scroll. Without the first report the
/// pane would never learn that the message already fits, and text-only mail
/// would hide its attachments behind a footer nothing can reveal.
class _PlainTextBodyScroll extends StatefulWidget {
  const _PlainTextBodyScroll({required this.onScroll, required this.child});

  final ValueChanged<EmailBodyScroll>? onScroll;
  final Widget child;

  @override
  State<_PlainTextBodyScroll> createState() => _PlainTextBodyScrollState();
}

class _PlainTextBodyScrollState extends State<_PlainTextBodyScroll> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _report() {
    final onScroll = widget.onScroll;
    if (onScroll == null || !mounted || !_controller.hasClients) return;
    final position = _controller.position;
    onScroll(
      EmailBodyScroll(
        y: position.pixels,
        maxY: position.maxScrollExtent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _report();
        return false;
      },
      child: SingleChildScrollView(
        controller: _controller,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: widget.child,
      ),
    );
  }
}

class _EmailDetailContent extends StatelessWidget {
  const _EmailDetailContent({
    super.key,
    required this.email,
    required this.workspaceId,
    this.onBodyScroll,
    this.showFooter = false,
  });

  final MailEmail email;
  final String? workspaceId;

  /// Scroll samples from the HTML body, used to collapse the header and to
  /// reveal the footer at the end of the message.
  final ValueChanged<EmailBodyScroll>? onBodyScroll;

  /// Whether the attachment footer is revealed below the body.
  final bool showFooter;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final attachmentWorkspaceId = email.mailbox?.workspaceId ?? workspaceId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        // The message body fills the remaining pane and scrolls itself: the
        // web view is a platform view that owns the mouse wheel over its whole
        // area, so nothing can sit below it and still be reachable by wheel.
        Expanded(
          child: email.isHtml
              ? _HtmlBodyViewer(
                  html: email.body,
                  attachments: email.attachments,
                  inlineAttachments: email.inlineAttachments,
                  workspaceId: attachmentWorkspaceId,
                  onScroll: onBodyScroll,
                )
              : _PlainTextBodyScroll(
                  onScroll: onBodyScroll,
                  child: EmailPlainTextBody(
                    body: email.body,
                    attachments: email.attachments,
                    workspaceId: attachmentWorkspaceId,
                    style: text.bodyLarge,
                  ),
                ),
        ),
        // Attachments and delivery state live below the body: nothing under a
        // platform view can be reached by wheel, so they are revealed once the
        // reader reaches the end of the message — or straight away when it
        // already fits.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: showFooter
              ? _EmailFooter(email: email, workspaceId: attachmentWorkspaceId)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _EmailActionBar extends StatelessWidget {
  const _EmailActionBar({
    required this.onReply,
    required this.onReplyAll,
    required this.onForward,
    this.onResend,
  });

  final VoidCallback onReply;
  final VoidCallback onReplyAll;
  final VoidCallback onForward;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const .symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (onResend != null) ...[
              OutlinedButton.icon(
                onPressed: onResend,
                icon: const Icon(Symbols.refresh, size: 12),
                label: Text('resend'.tr()),
                style: OutlinedButton.styleFrom(
                  visualDensity: .compact,
                  padding: .symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
            IconButton(
              tooltip: 'replyAll'.tr(),
              onPressed: onReplyAll,
              icon: const Icon(Symbols.reply_all, size: 14),
              visualDensity: .compact,
            ),
            IconButton(
              tooltip: 'forward'.tr(),
              onPressed: onForward,
              icon: const Icon(Symbols.forward, size: 14),
              visualDensity: .compact,
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: onReply,
              icon: const Icon(Symbols.reply, size: 12),
              label: Text('reply'.tr()),
              style: FilledButton.styleFrom(
                visualDensity: .compact,
                padding: .symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resolves a Drive URL with the workspace context required for workspace files.
Uri _cloudFileUri(IDisplayableCloudFile file, String? workspaceId) {
  final workspace = workspaceId?.trim();
  final baseUri = Uri.parse(cloudFileDisplayUrl(file));
  if (workspace == null || workspace.isEmpty) return baseUri;
  return baseUri.replace(
    queryParameters: {...baseUri.queryParameters, 'workspace_id': workspace},
  );
}

/// Whether the end-of-message footer has anything to show: attachment chips
/// or delivery state for a sent message. Emails with neither get no footer,
/// so reaching the end of a plain message does not expand blank space.
bool emailHasFooterContent(MailEmail email) =>
    email.attachments.isNotEmpty ||
    (email.hasDeliveryStatus && !email.isDraft);

/// Attachments and delivery state for the open message, shown below the body.
class _EmailFooter extends StatelessWidget {
  const _EmailFooter({required this.email, required this.workspaceId});

  final MailEmail email;
  final String? workspaceId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (email.attachments.isNotEmpty) ...[
            Text('attachments'.tr(), style: text.titleSmall),
            const SizedBox(height: 8),
            // Media shows itself here; documents stay chips. Both kinds open
            // the way their type reads (see [CloudFileAttachmentList]).
            CloudFileAttachmentList(
              files: email.attachments,
              workspaceId: workspaceId,
            ),
          ],
          if (email.hasDeliveryStatus && !email.isDraft) ...[
            if (email.attachments.isNotEmpty) const SizedBox(height: 24),
            Row(
              children: [
                _DeliveryStatusChip(status: email.deliveryStatus!),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'deliveryAttempts'.tr(
                      namedArgs: {'count': email.deliveryAttempts.toString()},
                    ),
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (email.lastDeliveryAttemptAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'lastDeliveryAttempt'.tr(
                    namedArgs: {
                      'date': email.lastDeliveryAttemptAt!.toLocal().toString(),
                    },
                  ),
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (email.deliveryError?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(
                  email.deliveryError!,
                  style: text.bodySmall?.copyWith(color: scheme.error),
                ),
              ),
          ],
        ],
      ),
    );
  }

}

/// One run of a plain-text message body: literal copy, or a link.
///
/// [text] is what the reader sees verbatim; [uri] is what a tap opens, and is
/// null for ordinary copy.
class EmailTextRun {
  const EmailTextRun.text(this.text) : uri = null;

  const EmailTextRun.link({required this.text, required this.uri});

  final String text;
  final Uri? uri;

  bool get isLink => uri != null;

  @override
  bool operator ==(Object other) =>
      other is EmailTextRun && other.text == text && other.uri == uri;

  @override
  int get hashCode => Object.hash(text, uri);

  @override
  String toString() => uri == null ? 'text($text)' : 'link($text -> $uri)';
}

/// The two link shapes worth recognising in plain-text copy: an explicit
/// `http(s)://` or `www.` URL, and a bare email address.
///
/// Bare hostnames (`notes.md`, `v1.2.3`) are deliberately left alone: a
/// plain-text body carries no markup saying which dotted word is a host, and a
/// wrong guess turns a filename into a click target.
final _plainTextLinkPattern = RegExp(
  "(?<url>(?:https?://|www\\.)[^\\s<>\"']+)"
  "|(?<email>[A-Za-z0-9._%+\\-]+@[A-Za-z0-9\\-]+(?:\\.[A-Za-z0-9\\-]+)+)",
  caseSensitive: false,
);

/// Splits [text] into the runs a plain-text body renders: literal copy plus
/// the links and addresses in it.
///
/// Concatenating the runs' [EmailTextRun.text] reproduces [text] exactly, so
/// the sentence punctuation that follows a link stays in the message instead of
/// being swallowed by it, and no character of the sender's copy is lost.
List<EmailTextRun> emailPlainTextRuns(String text) {
  final runs = <EmailTextRun>[];
  var cursor = 0;
  for (final match in _plainTextLinkPattern.allMatches(text)) {
    final isUrl = match.namedGroup('url') != null;
    final label = isUrl ? _trimUrlTail(match.group(0)!) : match.group(0)!;
    final uri = label.isEmpty ? null : _plainTextLinkUri(label, isUrl: isUrl);
    // A shape that is not a usable target (`https://` on its own, say) stays
    // part of the surrounding copy.
    if (uri == null) continue;
    if (match.start > cursor) {
      runs.add(EmailTextRun.text(text.substring(cursor, match.start)));
    }
    runs.add(EmailTextRun.link(text: label, uri: uri));
    cursor = match.start + label.length;
  }
  if (cursor < text.length) {
    runs.add(EmailTextRun.text(text.substring(cursor)));
  }
  return runs;
}

/// Drops the punctuation a sentence puts after a URL: closing `.`, `,`, `;`,
/// `:`, `!`, `?` and any bracket the URL itself does not open.
///
/// A URL is matched greedily from a character class, so the tail is the only
/// place a sentence can bleed into it.
String _trimUrlTail(String url) {
  var end = url.length;
  while (end > 0 && '.,;:!?'.contains(url[end - 1])) {
    end--;
  }
  for (final pair in const [('(', ')'), ('[', ']'), ('{', '}')]) {
    while (end > 0 && url[end - 1] == pair.$2) {
      final candidate = url.substring(0, end);
      if (pair.$2.allMatches(candidate).length <=
          pair.$1.allMatches(candidate).length) {
        break;
      }
      end--;
    }
  }
  return url.substring(0, end);
}

/// Builds the target of a recognised link, or null when the match cannot be
/// opened — the caller keeps such text as copy.
Uri? _plainTextLinkUri(String label, {required bool isUrl}) {
  if (!isUrl) {
    final uri = Uri.tryParse('mailto:$label');
    return uri == null || uri.path.isEmpty ? null : uri;
  }
  // `www.` is a host, not a scheme: the reader's browser needs one.
  final candidate = label.toLowerCase().startsWith('www.')
      ? 'https://$label'
      : label;
  final uri = Uri.tryParse(candidate);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri.host.isEmpty ? null : uri;
}

/// Opens a link from message copy in the user's own browser — or mail client,
/// for `mailto:` — the same way the HTML viewer opens a sender's link.
Future<void> openEmailLink(Uri uri) async {
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // No handler for the scheme: the tap simply does nothing.
  }
}

/// Renders a plain-text message body, highlighting and linking the URLs and
/// addresses in it.
///
/// The body arrives as text, so links are recognised by shape
/// ([emailPlainTextRuns]) and drawn in the theme's link colour; a tap opens
/// them like a link in an HTML message. Runs stay inside one [SelectableText]
/// per copy block, so selection copies the message, link text included, in one
/// sweep.
class EmailPlainTextBody extends StatefulWidget {
  const EmailPlainTextBody({
    super.key,
    required this.body,
    required this.attachments,
    required this.workspaceId,
    this.style,
    this.onOpenLink,
  });

  final String body;
  final List<SnCloudFileReference> attachments;
  final String? workspaceId;
  final TextStyle? style;

  /// How a tapped link is opened; defaults to [openEmailLink].
  final Future<void> Function(Uri uri)? onOpenLink;

  @override
  State<EmailPlainTextBody> createState() => _EmailPlainTextBodyState();
}

class _EmailPlainTextBodyState extends State<EmailPlainTextBody> {
  static final _imageMarker = RegExp(
    r'\[image:\s*([^\]\r\n]+)\]',
    caseSensitive: false,
  );

  /// One recognizer per target, kept across builds: the body rebuilds on every
  /// scroll report from its ancestors, and a fresh recognizer each build would
  /// strand one gesture-arena entry per rebuild.
  final _linkRecognizers = <Uri, TapGestureRecognizer>{};

  @override
  void didUpdateWidget(EmailPlainTextBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body) _disposeRecognizers();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _linkRecognizers.values) {
      recognizer.dispose();
    }
    _linkRecognizers.clear();
  }

  TapGestureRecognizer _recognizerFor(Uri uri) => _linkRecognizers.putIfAbsent(
    uri,
    () => TapGestureRecognizer()
      ..onTap = () => unawaited((widget.onOpenLink ?? openEmailLink)(uri)),
  );

  /// Renders one stretch of copy between inline images as a single selectable
  /// text, with its links as tappable spans.
  Widget _textBlock(BuildContext context, String block) {
    final style = widget.style;
    final runs = emailPlainTextRuns(block);
    if (runs.length == 1 && !runs.single.isLink) {
      return SelectableText(runs.single.text, style: style);
    }
    final scheme = Theme.of(context).colorScheme;
    final linkStyle = (style ?? const TextStyle()).copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary.withValues(alpha: .4),
    );
    return SelectableText.rich(
      TextSpan(
        style: style,
        children: [
          for (final run in runs)
            TextSpan(
              text: run.text,
              style: run.isLink ? linkStyle : null,
              recognizer: run.isLink ? _recognizerFor(run.uri!) : null,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.body;
    if (body.isEmpty) return SelectableText('(no body)', style: widget.style);

    final children = <Widget>[];
    var cursor = 0;
    for (final match in _imageMarker.allMatches(body)) {
      if (match.start > cursor) {
        children.add(_textBlock(context, body.substring(cursor, match.start)));
      }
      final filename = match.group(1)!.trim().toLowerCase();
      final attachment = _imageAttachmentForFilename(
        widget.attachments,
        filename,
      );
      // Drop markers with no matching attachment instead of showing the raw
      // preview-generation syntax in the message.
      if (attachment != null) {
        children.add(
          _InlineEmailImage(
            file: attachment,
            workspaceId: widget.workspaceId,
            gallery: widget.attachments,
          ),
        );
      }
      cursor = match.end;
    }
    if (cursor < body.length) {
      children.add(_textBlock(context, body.substring(cursor)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _InlineEmailImage extends StatelessWidget {
  const _InlineEmailImage({
    required this.file,
    required this.workspaceId,
    required this.gallery,
  });

  final SnCloudFileReference file;
  final String? workspaceId;

  /// The message's attachments, so a tapped image can be paged through with
  /// the rest of the pictures it arrived with.
  final List<IDisplayableCloudFile> gallery;

  @override
  Widget build(BuildContext context) {
    final displayUrl = _cloudFileUri(file, workspaceId).toString();
    void open() => openCloudFile(
      context,
      file,
      gallery: gallery,
      workspaceId: workspaceId,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onTap: open,
          child: Image.network(
            displayUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                CloudFileChip(file: file, displayUrl: displayUrl, onPressed: open),
          ),
        ),
      ),
    );
  }
}

/// Whether a web-view navigation should leave the app for the system browser
/// (or mail app) instead of loading inside the message pane.
///
/// Only user-activated links qualify. The initial document load, server
/// redirects and meta refreshes report their own navigation types (the
/// document load's URL is the webview base URL) and must stay in the pane —
/// cancelling those leaves the message blank.
bool shouldOpenEmailLinkExternally(NavigationAction navigationAction) {
  if (!navigationAction.isForMainFrame) return false;
  if (navigationAction.navigationType != NavigationType.LINK_ACTIVATED) {
    return false;
  }
  final scheme = navigationAction.request.url?.scheme;
  return scheme == 'http' || scheme == 'https' || scheme == 'mailto';
}

class _HtmlBodyViewer extends ConsumerStatefulWidget {
  const _HtmlBodyViewer({
    required this.html,
    required this.attachments,
    required this.inlineAttachments,
    required this.workspaceId,
    this.onScroll,
  });

  final String html;
  final List<SnCloudFileReference> attachments;
  final Map<String, SnCloudFileReference> inlineAttachments;
  final String? workspaceId;

  /// Reports the body's own scroll position as it moves.
  final ValueChanged<EmailBodyScroll>? onScroll;

  @override
  ConsumerState<_HtmlBodyViewer> createState() => _HtmlBodyViewerState();
}

class _HtmlBodyViewerState extends ConsumerState<_HtmlBodyViewer> {
  /// How often the scrollable extent may be re-read while scrolling.
  static const _metricsInterval = Duration(milliseconds: 200);

  /// `scrollHeight - innerHeight` is only reachable through JavaScript.
  static const _maxScrollScript =
      'Math.max(document.documentElement.scrollHeight - window.innerHeight, 0)';

  /// Bundled Nunito faces served to the web view through the `appfont://`
  /// scheme, keyed by the lowercase name referenced in [emailTypographyCss].
  static const _appFontAssets = <String, String>{
    'nunito-regular': 'assets/fonts/Nunito-Regular.ttf',
    'nunito-bold': 'assets/fonts/Nunito-Bold.ttf',
    'nunito-italic': 'assets/fonts/Nunito-Italic.ttf',
  };

  /// Decoded once per app run; the web view requests each face per document
  /// and WebKit caches them for the document's lifetime.
  static final _appFontCache = <String, Uint8List>{};

  String? _preparedHtml;
  InAppWebViewController? _controller;
  double? _maxScrollY;
  bool _atBottom = false;
  double? _viewportHeight;
  DateTime? _lastMetricsAt;
  Brightness? _lastBrightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The first prepare happens here, not in initState: _prepareHtml reads
    // Theme.of, which is only legal once inherited lookups are allowed. Later
    // theme switches (brightness flip) rebuild the document with fresh colors.
    final brightness = Theme.of(context).brightness;
    if (brightness == _lastBrightness && _preparedHtml != null) return;
    _lastBrightness = brightness;
    _prepareHtml();
  }

  @override
  void didUpdateWidget(_HtmlBodyViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html ||
        oldWidget.inlineAttachments != widget.inlineAttachments ||
        oldWidget.workspaceId != widget.workspaceId) {
      _preparedHtml = null;
      _maxScrollY = null;
      _atBottom = false;
      _lastMetricsAt = null;
      _prepareHtml();
    }
  }

  Future<void> _prepareHtml() async {
    final imageFiles = <String, SnCloudFileReference>{
      for (final attachment in widget.attachments)
        if (isImageFile(attachment)) attachment.id: attachment,
      for (final attachment in widget.inlineAttachments.values)
        if (isImageFile(attachment)) attachment.id: attachment,
    };
    final urls = <String, String>{};
    await Future.wait(
      imageFiles.values.map((attachment) async {
        try {
          urls[attachment.id] = await ref
              .read(wattEngineClientProvider)
              .resolveCloudFileUrl(
                attachment.id,
                workspaceId: widget.workspaceId,
              );
        } catch (_) {
          // Keep a usable fallback URL if a signed redirect cannot be resolved.
          urls[attachment.id] = _cloudFileUri(
            attachment,
            widget.workspaceId,
          ).toString();
        }
      }),
    );
    if (!mounted) return;
    setState(() {
      _preparedHtml = readerEmailDocument(
        sanitizeEmailHtml(
          _replaceInlineImageReferences(
            widget.html,
            widget.attachments,
            widget.inlineAttachments,
            widget.workspaceId,
            resolvedImageUrls: urls,
          ),
        ),
        // The document mirrors the app theme at render time; a theme switch
        // while reading re-prepares it through [didChangeDependencies].
        Theme.of(context),
      );
    });
  }

  void _onScrollChanged(InAppWebViewController controller, int x, int y) {
    final sample = EmailBodyScroll(y: y.toDouble(), maxY: _maxScrollY);
    _atBottom = sample.atBottom;
    widget.onScroll?.call(sample);
    _refreshScrollMetrics(controller);
  }

  /// The extent changes as images decode and as the pane resizes, so it is
  /// re-read while scrolling rather than once per document.
  void _refreshScrollMetrics(
    InAppWebViewController controller, {
    bool force = false,
  }) {
    final now = DateTime.now();
    if (!force &&
        _lastMetricsAt != null &&
        now.difference(_lastMetricsAt!) < _metricsInterval) {
      return;
    }
    _lastMetricsAt = now;
    unawaited(_readScrollMetrics(controller));
  }

  Future<void> _readScrollMetrics(InAppWebViewController controller) async {
    try {
      final raw = await controller.evaluateJavascript(source: _maxScrollScript);
      final max = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (max == null || !mounted) return;
      _maxScrollY = max;
    } catch (_) {
      // Leave the previous extent in place.
    }
  }

  Future<void> _stickToBottom() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.evaluateJavascript(
        source: 'window.scrollTo(0, document.documentElement.scrollHeight)',
      );
    } catch (_) {}
    if (mounted) _refreshScrollMetrics(controller, force: true);
  }

  /// Serves a bundled Nunito face for an `appfont://` request from the
  /// typography stylesheet. Unknown faces return `null`, so the font stack in
  /// [emailTypographyCss] falls back to the system sans.
  static Future<CustomSchemeResponse?> _serveAppFont(
    InAppWebViewController controller,
    WebResourceRequest request,
  ) async {
    final host = request.url.host;
    final asset = _appFontAssets[host.toLowerCase()];
    if (asset == null) return null;
    var bytes = _appFontCache[asset];
    if (bytes == null) {
      final data = await rootBundle.load(asset);
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      _appFontCache[asset] = bytes;
    }
    return CustomSchemeResponse(
      data: bytes,
      contentType: 'font/ttf',
      // The data is binary, not text: leave the encoding name empty so the
      // engine does not try to decode the font as a string.
      contentEncoding: '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final html = _preparedHtml;
    if (html == null) {
      return const Center(child: CircularProgressIndicator());
    }
    // Fills the pane handed down by _EmailDetailContent; the web view scrolls
    // its own document, because a platform view swallows the mouse wheel over
    // its whole area — an outer scroll view can never be scrolled there.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_viewportHeight != constraints.maxHeight) {
          // The pane resized around the body — the header collapsed or the
          // footer was revealed. Follow the end of the message if that is where
          // the reader is, instead of letting WebKit clamp the offset and jump
          // the body under them.
          _viewportHeight = constraints.maxHeight;
          if (_atBottom) unawaited(_stickToBottom());
        }
        return _buildWebView(html);
      },
    );
  }

  Widget _buildWebView(String html) {
    return InAppWebView(
      initialData: InAppWebViewInitialData(
        // Render the server's HTML body directly. The .eml endpoint is only
        // for downloading a serialized message, never for the reading view.
        data: html,
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: WebUri(kSolarNetworkApiBase),
      ),
      initialSettings: InAppWebViewSettings(
        // Required: the plugin reports [onScrollChanged] from a script it
        // injects into the document, so the pane needs JavaScript. The
        // sender's scripts are stripped in [sanitizeEmailHtml] — the only
        // script that runs is the plugin's own scroll listener.
        javaScriptEnabled: true,
        transparentBackground: true,
        supportZoom: false,
        mediaPlaybackRequiresUserGesture: true,
        useShouldOverrideUrlLoading: true,
        // The typography stylesheet loads the bundled Nunito faces through
        // this scheme ([_serveAppFont]); platforms without custom-scheme
        // support ignore it and fall back to the system font stack.
        resourceCustomSchemes: const ['appfont'],
      ),
      onWebViewCreated: (controller) => _controller = controller,
      onLoadResourceWithCustomScheme: _serveAppFont,
      onScrollChanged: _onScrollChanged,
      onLoadStop: (controller, url) async {
        _controller = controller;
        await _readScrollMetrics(controller);
        // A message that already fits never scrolls, so it never reports; seed
        // the footer decision from the document as loaded.
        _onScrollChanged(controller, 0, 0);
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        if (!shouldOpenEmailLinkExternally(navigationAction)) {
          return NavigationActionPolicy.ALLOW;
        }
        final url = navigationAction.request.url!;
        await openEmailLink(url);
        return NavigationActionPolicy.CANCEL;
      },
    );
  }
}

/// Strips active content from untrusted message HTML.
///
/// The message pane needs JavaScript because the plugin reports scroll
/// positions from a script it injects into the document; without this the
/// sender's own scripts would run. Styling and links are untouched — `<script>`
/// bodies, embedded objects, inline event handlers and `javascript:` URLs are
/// removed.
String sanitizeEmailHtml(String html) {
  // Paired active elements, contents included.
  var sanitized = html.replaceAll(
    RegExp(
      r'''<\s*(script|iframe|object|embed)\b[^>]*>.*?<\s*/\s*\1\s*>''',
      caseSensitive: false,
      dotAll: true,
    ),
    '',
  );
  // Unpaired or self-closing forms of the same elements.
  sanitized = sanitized.replaceAll(
    RegExp(
      r'''<\s*/?\s*(script|iframe|object|embed)\b[^>]*>''',
      caseSensitive: false,
    ),
    '',
  );
  // Inline handlers: onclick="…", onerror='…', onload=foo().
  sanitized = sanitized.replaceAll(
    RegExp(
      r'''\son[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)''',
      caseSensitive: false,
    ),
    '',
  );
  // javascript: URLs. The attribute value is replaced whole — non-greedily up
  // to its own closing quote — so removing it cannot eat that quote or leave a
  // stray one behind.
  sanitized = sanitized.replaceAllMapped(
    RegExp(
      r'''\b(href|src|xlink:href|action|formaction)\s*=\s*(["'])\s*javascript:[^>]*?\2''',
      caseSensitive: false,
    ),
    (match) => '${match[1]}=${match[2]}about:blank#blocked${match[2]}',
  );
  // Unquoted javascript: URLs and anything the first pass missed. Quotes are
  // excluded so an attribute's delimiter is never swallowed.
  sanitized = sanitized.replaceAll(
    RegExp(r'''javascript\s*:[^\s"'>]*''', caseSensitive: false),
    'about:blank#blocked',
  );
  return sanitized;
}

/// Whether [html] carries styling of its own: an embedded `<style>` element or
/// a linked stylesheet. Inline `style=` attributes do not count — tracking
/// pixels and single-element tweaks are ubiquitous in otherwise-plain email,
/// and the injected defaults are element selectors, so a message's inline
/// styles keep winning by specificity anyway.
bool isUnstyledEmailHtml(String html) {
  final ownStyling = RegExp(
    r'''<\s*style\b|\brel\s*=\s*["']?\s*stylesheet\b''',
    caseSensitive: false,
  );
  return !ownStyling.hasMatch(html);
}

/// Injects [css] as the document's first stylesheet. The style goes into the
/// existing `<head>` when there is one, into a freshly added `<head>` when the
/// document only has `<html>`, and is prepended to bare fragments — browsers
/// apply a `<style>` wherever it appears.
String injectEmailTypography(String html, String css) {
  final style = '<style>$css</style>';
  final headEnd = RegExp(r'</head\s*>', caseSensitive: false).firstMatch(html);
  if (headEnd != null) {
    return html.replaceRange(headEnd.start, headEnd.start, style);
  }
  final htmlTag = RegExp(r'<\s*html\b[^>]*>', caseSensitive: false).firstMatch(
    html,
  );
  if (htmlTag != null) {
    return html.replaceRange(htmlTag.end, htmlTag.end, '<head>$style</head>');
  }
  return '$style$html';
}

/// Returns [html] with [css] injected as its default stylesheet when the
/// message defines no styling of its own; styled messages are returned
/// untouched so their look is preserved.
String withEmailTypography(String html, String css) {
  if (!isUnstyledEmailHtml(html)) return html;
  return injectEmailTypography(html, css);
}

/// The document the reading pane loads: the sender's markup with the app's
/// typography stamped in, and — for a dark pane, which is the one colour
/// assumption a message does not make — the text colours that would not read on
/// it repaired.
///
/// A message that ships a stylesheet is returned with its own palette: its
/// colours come from a cascade [withReadableEmailColors] cannot evaluate.
String readerEmailDocument(String html, ThemeData theme) {
  final body = theme.brightness == Brightness.dark && isUnstyledEmailHtml(html)
      ? withReadableEmailColors(
          html,
          // The pane behind a transparent message body, and so the surface an
          // inline colour has to read against.
          backdrop: theme.colorScheme.surfaceContainerLow,
        )
      : html;
  return withEmailTypography(body, emailTypographyCss(theme));
}

/// Default typography stylesheet for emails that carry no styling of their
/// own, derived from the app theme so the message pane reads like the rest of
/// the app: same font, sizes and colors, dark mode included.
///
/// Nunito is served from the bundled assets through the `appfont://` scheme
/// (see [_HtmlBodyViewerState._serveAppFont]); on platforms without
/// custom-scheme support the stack falls back to the system sans.
String emailTypographyCss(ThemeData theme) {
  final scheme = theme.colorScheme;
  final text = theme.textTheme;
  // The @font-face block below only bundles the Nunito faces, so the family
  // name is pinned to the app's font constant rather than the theme slot —
  // the app theme always applies this family anyway.
  final font = SolWattFonts.sans;
  final onSurface = _cssHex(scheme.onSurface);
  final onSurfaceVariant = _cssHex(scheme.onSurfaceVariant);
  final primary = _cssHex(scheme.primary);
  final outlineVariant = _cssHex(scheme.outlineVariant);
  final codeBackground = _cssHex(scheme.surfaceContainerHighest);
  final selection = _cssHex(scheme.primaryContainer);

  String heading(TextStyle? style, double fallbackSize, int fallbackWeight) =>
      'font-size: ${style?.fontSize ?? fallbackSize}px;'
      'font-weight: ${style?.fontWeight?.value ?? fallbackWeight};';

  return '''
@font-face { font-family: '$font'; src: url('appfont://nunito-regular') format('truetype'); font-weight: 400; font-style: normal; }
@font-face { font-family: '$font'; src: url('appfont://nunito-bold') format('truetype'); font-weight: 700; font-style: normal; }
@font-face { font-family: '$font'; src: url('appfont://nunito-italic') format('truetype'); font-weight: 400; font-style: italic; }
:root { color-scheme: ${theme.brightness == Brightness.dark ? 'dark' : 'light'}; }
html, body { background: transparent; }
body {
  margin: 0;
  padding: 24px;
  font-family: '$font', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
  font-size: ${text.bodyLarge?.fontSize ?? 16}px;
  line-height: 1.6;
  color: $onSurface;
  overflow-wrap: break-word;
  -webkit-text-size-adjust: 100%;
}
h1, h2, h3, h4, h5, h6 { line-height: 1.3; margin: 1.2em 0 0.5em; color: inherit; }
h1 { ${heading(text.headlineMedium, 28, 700)} }
h2 { ${heading(text.headlineSmall, 24, 700)} }
h3 { ${heading(text.titleLarge, 22, 600)} }
h4 { ${heading(text.titleMedium, 16, 600)} }
h5 { ${heading(text.titleSmall, 14, 600)} }
h6 { ${heading(text.labelLarge, 14, 600)} }
p { margin: 0 0 1em; }
a { color: $primary; }
a:visited { color: $primary; }
strong, b { font-weight: 700; }
em, i { font-style: italic; }
img { max-width: 100%; height: auto; }
hr { border: 0; border-top: 1px solid $outlineVariant; margin: 1.5em 0; }
blockquote { margin: 1em 0; padding: 0 0 0 1em; border-left: 3px solid $outlineVariant; color: $onSurfaceVariant; }
code, pre { font-family: ui-monospace, 'SF Mono', 'Cascadia Code', Menlo, Consolas, monospace; font-size: 0.9em; background: $codeBackground; border-radius: 6px; }
code { padding: 0.15em 0.4em; }
pre { padding: 12px; overflow-x: auto; }
pre code { background: none; padding: 0; }
table { border-collapse: collapse; max-width: 100%; }
ul, ol { margin: 0 0 1em; padding-left: 1.5em; }
li { margin: 0.25em 0; }
::selection { background: $selection; }
''';
}

String _cssHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}

String _replaceInlineImageReferences(
  String body,
  List<SnCloudFileReference> attachments,
  Map<String, SnCloudFileReference> inlineAttachments,
  String? workspaceId, {
  Map<String, String> resolvedImageUrls = const {},
}) {
  String imageUrl(SnCloudFileReference attachment) =>
      (resolvedImageUrls[attachment.id] ??
              _cloudFileUri(attachment, workspaceId).toString())
          .replaceAll('&', '&amp;')
          .replaceAll('"', '&quot;');

  final imageMarker = RegExp(
    r'\[image:\s*([^\]\r\n]+)\]',
    caseSensitive: false,
  );
  final withMarkers = body.replaceAllMapped(imageMarker, (match) {
    final filename = match.group(1)!.trim().toLowerCase();
    final attachment = _imageAttachmentForFilename(attachments, filename);
    if (attachment == null) return '';
    return '<img src="${imageUrl(attachment)}" alt="$filename">';
  });
  return withMarkers.replaceAllMapped(
    RegExp(r'''cid:([^"'\s>]+)''', caseSensitive: false),
    (match) {
      final contentId = match.group(1)!.trim().toLowerCase();
      final attachment =
          inlineAttachments[contentId] ??
          inlineAttachments.entries
              .where((entry) => entry.key.toLowerCase() == contentId)
              .firstOrNull
              ?.value;
      return attachment == null ? '' : imageUrl(attachment);
    },
  );
}

SnCloudFileReference? _imageAttachmentForFilename(
  List<SnCloudFileReference> attachments,
  String filename,
) {
  for (final file in attachments) {
    if (isImageFile(file) && file.name.trim().toLowerCase() == filename) {
      return file;
    }
  }
  return null;
}

class _EmailMetadata extends ConsumerWidget {
  const _EmailMetadata({
    required this.email,
    required this.mailHost,
    required this.dateStyle,
  });

  final MailEmail email;
  final String? mailHost;
  final TextStyle? dateStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The message carries no contact data, so the header joins the senders
    // index the same way the list does: that is where an address which is one
    // of the account's own aliases, or a name the message dropped, is known. A
    // missing entry just leaves the chip with the address and its initial.
    final senders =
        ref.watch(mailSenderIndexProvider).value ??
        const <String, MailAddressSuggestion>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EmailRecipientRow(
          label: 'from'.tr(),
          recipients: email.from == null ? const [] : [email.from!],
          mailHost: mailHost,
          senders: senders,
        ),
        EmailRecipientRow(
          label: 'to'.tr(),
          recipients: email.to,
          mailHost: mailHost,
          senders: senders,
        ),
        if (email.cc.isNotEmpty)
          EmailRecipientRow(
            label: 'cc'.tr(),
            recipients: email.cc,
            mailHost: mailHost,
            senders: senders,
          ),
        if (email.bcc.isNotEmpty)
          EmailRecipientRow(
            label: 'bcc'.tr(),
            recipients: email.bcc,
            mailHost: mailHost,
            senders: senders,
          ),
        if (email.createdAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              email.createdAt!.toLocal().toString(),
              style: dateStyle,
            ),
          ),
      ],
    );
  }
}

/// One address row of the message header: its label, then a chip per contact.
class EmailRecipientRow extends StatelessWidget {
  const EmailRecipientRow({
    super.key,
    required this.label,
    required this.recipients,
    this.mailHost,
    this.senders = const {},
  });

  final String label;
  final List<MailRecipient> recipients;
  final String? mailHost;

  /// Senders-index entries, keyed by lowercase address.
  final Map<String, MailAddressSuggestion> senders;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nudged onto the first chip's text line rather than its box.
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final recipient in recipients)
                  EmailRecipientChip(
                    recipient: recipient,
                    mailHost: mailHost,
                    sender: senders[recipient.fullAddress(mailHost)],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One contact as a chip: avatar and name, with the full address behind a tap.
///
/// The reading pane shows names, not addresses — a chip keeps the address one
/// click away (the chip's tooltip already carries it for pointer users who
/// never click) and offers copying it.
///
/// The message payload is the first source of a name and [sender] the second:
/// a message that names nobody (your own alias among the recipients, say) still
/// shows the identity the senders index holds for that address.
class EmailRecipientChip extends StatelessWidget {
  const EmailRecipientChip({
    super.key,
    required this.recipient,
    required this.mailHost,
    this.sender,
    this.onDeleted,
  });

  final MailRecipient recipient;
  final String? mailHost;

  /// The senders-index entry for this address, when the index knows it.
  final MailAddressSuggestion? sender;

  /// Drops the chip when set, for callers that are editing the recipient list
  /// rather than reading it.
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final address = recipient.fullAddress(mailHost);
    final sent = recipient.name?.trim() ?? '';
    final known = sender?.name?.trim() ?? '';
    final name = sent.isNotEmpty ? sent : known;

    return Tooltip(
      message: address,
      child: Material(
        color: scheme.surfaceContainerHighest,
        shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showAddress(context, address: address, name: name),
          child: Padding(
            padding: EdgeInsets.fromLTRB(4, 3, onDeleted == null ? 10 : 2, 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ContactAvatar(
                  url: emailAvatarUrl(sender),
                  label: name.isEmpty ? address : name,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    name.isEmpty ? address : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (onDeleted != null) ...[
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: 'removeRecipient'.tr(),
                    onPressed: onDeleted,
                    icon: const Icon(Symbols.close, size: 14),
                    iconSize: 14,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Drops the chip's menu under the chip: the address, then Copy.
  Future<void> _showAddress(
    BuildContext context, {
    required String address,
    required String name,
  }) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !box.hasSize) return;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    await showMenu<void>(
      context: context,
      position: RelativeRect.fromRect(
        box.localToGlobal(Offset.zero, ancestor: overlay) & box.size,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          height: 0,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (name.isNotEmpty)
                Text(
                  name,
                  style: text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              SelectableText(
                address,
                style: text.bodySmall?.copyWith(color: scheme.onSurface),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<void>(
          onTap: () {
            Clipboard.setData(ClipboardData(text: address));
            showSnackBar('copied'.tr());
          },
          child: Row(
            children: [
              const Icon(Symbols.content_copy, size: 16),
              const SizedBox(width: 10),
              Text('copyAddress'.tr()),
            ],
          ),
        ),
      ],
    );
  }
}

/// The chip's 18px contact picture, falling back to the contact's initial.
class _ContactAvatar extends StatelessWidget {
  const _ContactAvatar({required this.url, required this.label});

  final String? url;

  /// Name — or address, when there is no name — the fallback initial reads
  /// from.
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = CircleAvatar(
      radius: 9,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: Text(
        _senderInitials(label),
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
      ),
    );
    final picture = url;
    if (picture == null || picture.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        picture,
        width: 18,
        height: 18,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class _MailDraft {
  const _MailDraft({
    required this.mailboxId,
    required this.to,
    this.cc = const [],
    this.bcc = const [],
    required this.subject,
    required this.body,
    this.attachmentIds = const [],
    this.replyToId,
    this.isDraft = false,
    this.contentType = 'text/plain',
  });

  final String mailboxId;
  final List<MailRecipient> to;
  final List<MailRecipient> cc;
  final List<MailRecipient> bcc;
  final String subject;
  final String body;
  final List<String> attachmentIds;
  final String? replyToId;
  final bool isDraft;
  final String contentType;
}

class _ComposeSheet extends ConsumerStatefulWidget {
  const _ComposeSheet({
    required this.mailbox,
    required this.mailboxes,
    required this.onSubmitted,
    required this.onClose,
    this.mailHost,
    this.replyingTo,
    this.replyAll = false,
    this.forwarding,
  });

  final MailMailbox mailbox;
  final List<MailMailbox> mailboxes;
  final Future<void> Function(_MailDraft draft) onSubmitted;
  final VoidCallback onClose;
  final String? mailHost;
  final MailEmail? replyingTo;
  final bool replyAll;
  final MailEmail? forwarding;

  @override
  ConsumerState<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends ConsumerState<_ComposeSheet> {
  late String _mailboxId;
  final _toController = TextEditingController();
  final _ccController = TextEditingController();
  final _bccController = TextEditingController();
  final _subjectController = TextEditingController();
  final _quillController = QuillController.basic();
  final List<({String id, String name})> _attachments = [];
  // Committed recipients, shown as chips; the controllers hold whatever is
  // still being typed.
  List<MailRecipient> _to = [];
  List<MailRecipient> _cc = [];
  List<MailRecipient> _bcc = [];
  var _showCcBcc = false;
  var _pickingAttachment = false;
  final _shortcutFocusNode = FocusNode();
  final _bodyFocusNode = FocusNode();
  MailMailbox? get _selectedMailbox =>
      widget.mailboxes.where((m) => m.id == _mailboxId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _mailboxId = widget.mailbox.id;
    final replyingTo = widget.replyingTo;
    final forwarding = widget.forwarding;
    if (replyingTo != null) {
      final from = replyingTo.from;
      if (from != null && from.address.trim().isNotEmpty) {
        _to = [MailRecipient(address: from.address, name: from.name, kind: 'to')];
      }
      if (widget.replyAll) {
        final self = _selectedMailbox?.fullAddress(widget.mailHost);
        final seen = {from?.fullAddress(widget.mailHost), self};
        final others = <MailRecipient>[];
        for (final recipient in [...replyingTo.to, ...replyingTo.cc]) {
          final address = recipient.fullAddress(widget.mailHost);
          if (address.isEmpty || !seen.add(address)) continue;
          others.add(
            MailRecipient(
              address: recipient.address,
              name: recipient.name,
              kind: 'cc',
            ),
          );
        }
        _cc = others;
      }
      _subjectController.text = 'Re: ${replyingTo.displaySubject}';
      _quillController.document = Document.fromDelta(
        HtmlToDelta().convert(_quoteBody(replyingTo, forwarded: false)),
      );
    } else if (forwarding != null) {
      _subjectController.text = 'Fwd: ${forwarding.displaySubject}';
      _quillController.document = Document.fromDelta(
        HtmlToDelta().convert(_quoteBody(forwarding, forwarded: true)),
      );
      _attachments.addAll(
        forwarding.attachments.map((file) => (id: file.id, name: file.name)),
      );
    }
  }

  String _quoteBody(MailEmail email, {required bool forwarded}) {
    final header = forwarded
        ? '<p>---------- ${'forwardedMessage'.tr()} ----------<br>'
              '${email.from?.fullAddress(widget.mailHost) ?? ''}<br>'
              '${email.createdAt?.toLocal() ?? ''}<br>'
              '${'subject'.tr()}: ${email.displaySubject}</p>'
        : '';
    return '\n\n<blockquote>$header${email.body}</blockquote>';
  }

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _bccController.dispose();
    _subjectController.dispose();
    _quillController.dispose();
    _shortcutFocusNode.dispose();
    _bodyFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    if (_pickingAttachment) return;
    setState(() => _pickingAttachment = true);
    try {
      final files = await uploadLocalCloudFiles(
        ref,
        allowMultiple: true,
        workspaceId: widget.mailbox.workspaceId,
      );
      if (files != null && files.isNotEmpty && mounted) {
        setState(
          () => _attachments.addAll(
            files.map((file) => (id: file.id, name: file.name)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingAttachment = false);
    }
  }

  /// The chips committed in [field] plus an address still being typed there,
  /// so a send never silently drops it.
  List<MailRecipient> _recipients(
    List<MailRecipient> committed,
    TextEditingController field,
    String kind,
  ) => _mergeRecipients(committed, _parseRecipients(field.text, kind: kind));

  Future<void> _submit({bool draft = false}) async {
    final to = _recipients(_to, _toController, 'to');
    if (to.isEmpty) {
      showSnackBar('recipientsRequired'.tr());
      return;
    }
    await widget.onSubmitted(
      _MailDraft(
        mailboxId: _mailboxId,
        to: to,
        cc: _recipients(_cc, _ccController, 'cc'),
        bcc: _recipients(_bcc, _bccController, 'bcc'),
        subject: _subjectController.text,
        body: QuillDeltaToHtmlConverter(
          _quillController.document.toDelta().toJson(),
          ConverterOptions.forEmail(),
        ).convert(),
        attachmentIds: _attachments.map((a) => a.id).toList(growable: false),
        replyToId: widget.replyingTo?.id,
        isDraft: draft,
        contentType: 'text/html',
      ),
    );
  }

  Future<void> _insertLink() async {
    final url = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text('insertLink'.tr()),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: 'https://example.com',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('close'.tr()),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: Text('apply'.tr()),
            ),
          ],
        );
      },
    );
    if (url == null || url.isEmpty) return;
    _quillController.formatSelection(LinkAttribute(url));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter, meta: true):
            _SendEmailIntent(),
        SingleActivator(LogicalKeyboardKey.enter, control: true):
            _SendEmailIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter, meta: true):
            _SendEmailIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
            _SendEmailIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            _SaveDraftIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _SaveDraftIntent(),
      },
      child: Actions(
        actions: {
          _SendEmailIntent: CallbackAction<_SendEmailIntent>(
            onInvoke: (_) {
              _submit();
              return null;
            },
          ),
          _SaveDraftIntent: CallbackAction<_SaveDraftIntent>(
            onInvoke: (_) {
              _submit(draft: true);
              return null;
            },
          ),
        },
        child: KeyboardListener(
          focusNode: _shortcutFocusNode,
          onKeyEvent: (event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              widget.onClose();
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: close, title, save draft, send.
              SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'close'.tr(),
                        onPressed: widget.onClose,
                        icon: const Icon(Symbols.close),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'compose'.tr(),
                          style: textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'saveDraft'.tr(),
                        onPressed: () => _submit(draft: true),
                        icon: const Icon(Symbols.bookmark_add),
                      ),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'sendShortcut'.tr(),
                        child: FilledButton.icon(
                          onPressed: () => _submit(),
                          icon: const Icon(Symbols.send, size: 18),
                          label: Text('send'.tr()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              // Compact header fields: from, to, (cc/bcc), subject.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    _CompactLabeledField(
                      label: 'from'.tr(),
                      child: DropdownButtonFormField<String>(
                        initialValue: _mailboxId,
                        isDense: true,
                        isExpanded: true,
                        style: Theme.of(context).textTheme.bodyLarge,
                        decoration: _CompactLabeledField.decoration(),
                        items: [
                          for (final mailbox in widget.mailboxes)
                            DropdownMenuItem(
                              value: mailbox.id,
                              child: Text(mailbox.displayName),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _mailboxId = value);
                          }
                        },
                      ),
                    ),
                    if (_selectedMailbox
                            ?.fullAddress(widget.mailHost)
                            .contains('@') !=
                        true) ...[
                      _MailboxInvalidBanner(
                        message: 'mailboxAddressInvalidSend'.tr(),
                      ),
                    ],
                    const SizedBox(height: 8),
                    _CompactLabeledField(
                      label: 'to'.tr(),
                      child: _ComposeRecipientField(
                        controller: _toController,
                        recipients: _to,
                        kind: 'to',
                        mailHost: widget.mailHost,
                        onChanged: (recipients) =>
                            setState(() => _to = recipients),
                        // Sits inside the field's box, at its trailing edge.
                        suffixIcon: IconButton(
                          tooltip: 'ccBcc'.tr(),
                          onPressed: () =>
                              setState(() => _showCcBcc = !_showCcBcc),
                          icon: Icon(
                            _showCcBcc
                                ? Symbols.expand_less
                                : Symbols.expand_more,
                            size: 18,
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _showCcBcc
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 8),
                                _CompactLabeledField(
                                  label: 'cc'.tr(),
                                  child: _ComposeRecipientField(
                                    controller: _ccController,
                                    recipients: _cc,
                                    kind: 'cc',
                                    mailHost: widget.mailHost,
                                    onChanged: (recipients) =>
                                        setState(() => _cc = recipients),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _CompactLabeledField(
                                  label: 'bcc'.tr(),
                                  child: _ComposeRecipientField(
                                    controller: _bccController,
                                    recipients: _bcc,
                                    kind: 'bcc',
                                    mailHost: widget.mailHost,
                                    onChanged: (recipients) =>
                                        setState(() => _bcc = recipients),
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    const SizedBox(height: 8),
                    _CompactLabeledField(
                      label: 'subject'.tr(),
                      child: TextField(
                        controller: _subjectController,
                        style: textTheme.titleMedium,
                        textInputAction: TextInputAction.next,
                        decoration: _CompactLabeledField.decoration(),
                        onSubmitted: (_) => _bodyFocusNode.requestFocus(),
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Formatting toolbar with inline styles and block presets.
              _ComposeToolbar(
                onBold: () => _quillController.formatSelection(Attribute.bold),
                onItalic: () =>
                    _quillController.formatSelection(Attribute.italic),
                onUnderline: () =>
                    _quillController.formatSelection(Attribute.underline),
                onStrikethrough: () =>
                    _quillController.formatSelection(Attribute.strikeThrough),
                onHeading1: () =>
                    _quillController.formatSelection(Attribute.h1),
                onHeading2: () =>
                    _quillController.formatSelection(Attribute.h2),
                onHeading3: () =>
                    _quillController.formatSelection(Attribute.h3),
                onBulletList: () =>
                    _quillController.formatSelection(Attribute.ul),
                onNumberedList: () =>
                    _quillController.formatSelection(Attribute.ol),
                onQuote: () =>
                    _quillController.formatSelection(Attribute.blockQuote),
                onCode: () =>
                    _quillController.formatSelection(Attribute.codeBlock),
                onLink: _insertLink,
                onAttach: _pickingAttachment ? null : _pickAttachment,
              ),
              // Body fills the remaining height, inside a rounded card that
              // subtly highlights while focused.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: AnimatedBuilder(
                    animation: _bodyFocusNode,
                    builder: (context, child) {
                      final focused = _bodyFocusNode.hasFocus;
                      return AnimatedContainer(
                        key: const ValueKey('compose-body-card'),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: focused
                                ? scheme.primary
                                : scheme.outlineVariant,
                            width: focused ? 1.5 : 1,
                          ),
                        ),
                        child: child,
                      );
                    },
                    child: QuillEditor.basic(
                      key: const ValueKey('compose-body'),
                      controller: _quillController,
                      focusNode: _bodyFocusNode,
                      config: QuillEditorConfig(
                        placeholder: 'body'.tr(),
                        expands: true,
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        // A quoted reply brings its body's images along; render
                        // them rather than failing the line that holds them.
                        unknownEmbedBuilder: const _ComposeUnknownEmbed(),
                        // Esc: quill's internal Shortcuts consumes Esc before
                        // the sheet-level listener, so intercept it here.
                        // ignore: experimental_member_use
                        onKeyPressed: (event, node) {
                          if (event is KeyDownEvent &&
                              event.logicalKey == LogicalKeyboardKey.escape) {
                            widget.onClose();
                            return KeyEventResult.handled;
                          }
                          return null;
                        },
                      ),
                    ),
                  ),
                ),
              ),
              if (_attachments.isNotEmpty) ...[
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final file in _attachments)
                          InputChip(
                            avatar: Icon(
                              Symbols.attach_file,
                              size: 16,
                              color: scheme.onSurfaceVariant,
                            ),
                            label: Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            visualDensity: VisualDensity.compact,
                            onDeleted: () =>
                                setState(() => _attachments.remove(file)),
                            deleteButtonTooltipMessage: 'removeAttachment'.tr(),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact formatting toolbar with inline styles and block presets.
class _ComposeToolbar extends StatelessWidget {
  const _ComposeToolbar({
    required this.onBold,
    required this.onItalic,
    required this.onUnderline,
    required this.onStrikethrough,
    required this.onHeading1,
    required this.onHeading2,
    required this.onHeading3,
    required this.onBulletList,
    required this.onNumberedList,
    required this.onQuote,
    required this.onCode,
    required this.onLink,
    required this.onAttach,
  });

  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onUnderline;
  final VoidCallback onStrikethrough;
  final VoidCallback onHeading1;
  final VoidCallback onHeading2;
  final VoidCallback onHeading3;
  final VoidCallback onBulletList;
  final VoidCallback onNumberedList;
  final VoidCallback onQuote;
  final VoidCallback onCode;
  final VoidCallback onLink;
  final VoidCallback? onAttach;

  @override
  Widget build(BuildContext context) {
    Widget iconButton(IconData icon, String tooltip, VoidCallback? onPressed) =>
        IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        );
    Widget presetButton(String label, String tooltip, VoidCallback onPressed) =>
        Tooltip(
          message: tooltip,
          child: TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              minimumSize: const Size(32, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(label),
          ),
        );
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            iconButton(Symbols.format_bold, 'bold'.tr(), onBold),
            iconButton(Symbols.format_italic, 'italic'.tr(), onItalic),
            iconButton(
              Symbols.format_underlined,
              'underline'.tr(),
              onUnderline,
            ),
            iconButton(
              Symbols.format_strikethrough,
              'strikethrough'.tr(),
              onStrikethrough,
            ),
            const SizedBox(width: 8),
            presetButton('H1', 'heading1'.tr(), onHeading1),
            presetButton('H2', 'heading2'.tr(), onHeading2),
            presetButton('H3', 'heading3'.tr(), onHeading3),
            const SizedBox(width: 8),
            iconButton(
              Symbols.format_list_bulleted,
              'bulletList'.tr(),
              onBulletList,
            ),
            iconButton(
              Symbols.format_list_numbered,
              'numberedList'.tr(),
              onNumberedList,
            ),
            iconButton(Symbols.format_quote, 'quote'.tr(), onQuote),
            iconButton(Symbols.code, 'codeBlock'.tr(), onCode),
            const SizedBox(width: 8),
            iconButton(Symbols.link, 'insertLink'.tr(), onLink),
            iconButton(Symbols.attach_file, 'addAttachment'.tr(), onAttach),
          ],
        ),
      ),
    );
  }
}

/// Label and field box for one compose header row (from, to, cc, bcc,
/// subject).
///
/// The boxes are as tall as the field's own content — one text line plus
/// [decoration]'s padding — so the caret sits centered and a recipient row
/// grows downwards as its chips wrap.
class _CompactLabeledField extends StatelessWidget {
  const _CompactLabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  /// Vertical breathing room inside a header box.
  static const _padding = EdgeInsets.symmetric(horizontal: 12, vertical: 10);

  /// Height of a single-line header box.
  static double heightOf(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final scaled = MediaQuery.textScalerOf(
      context,
    ).scale(style?.fontSize ?? 16).toDouble();
    return _padding.vertical + scaled * (style?.height ?? 1.5);
  }

  /// The box every header field wears: the app's outlined input theme with the
  /// padding these rows need.
  ///
  /// The padding is deliberately below the theme's own so that one line plus
  /// the padding measures exactly [heightOf]: an oversized padding would push
  /// the text out of the box and leave the caret off-center.
  static InputDecoration decoration({Widget? suffixIcon}) => InputDecoration(
    suffixIcon: suffixIcon,
    isDense: true,
    contentPadding: _padding,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = heightOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Kept to the first line's height so a wrapped recipient row leaves the
        // label beside its chips.
        SizedBox(
          width: 64,
          height: height,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
        Expanded(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// Chip input for one compose recipient row.
///
/// Addresses become chips instead of a hand-formatted comma-separated string:
/// Enter, a typed separator, a pasted list and a picked suggestion all commit
/// one, a chip's own button takes one back, and backspace in the empty field
/// drops the last.
class _ComposeRecipientField extends ConsumerStatefulWidget {
  const _ComposeRecipientField({
    required this.controller,
    required this.recipients,
    required this.kind,
    required this.onChanged,
    this.mailHost,
    this.suffixIcon,
  });

  /// The address being typed. The sheet reads it too, so an address left
  /// uncommitted still goes out with the message.
  final TextEditingController controller;
  final List<MailRecipient> recipients;

  /// The role every recipient in this row carries ('to', 'cc', 'bcc').
  final String kind;
  final ValueChanged<List<MailRecipient>> onChanged;
  final String? mailHost;
  final Widget? suffixIcon;

  @override
  ConsumerState<_ComposeRecipientField> createState() =>
      _ComposeRecipientFieldState();
}

class _ComposeRecipientFieldState
    extends ConsumerState<_ComposeRecipientField> {
  final _focusNode = FocusNode();

  /// Suggestions picked in this row, keyed by lowercase address, so a chip can
  /// wear the contact's avatar and name.
  final _picked = <String, MailAddressSuggestion>{};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTyped);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(_ComposeRecipientField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTyped);
      widget.controller.addListener(_handleTyped);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTyped);
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  /// The row's box draws the focus ring itself, so it repaints with the
  /// inline field's focus.
  void _handleFocusChanged() => setState(() {});

  /// A separator ends the address being typed — the same one a pasted list of
  /// addresses arrives with.
  void _handleTyped() {
    final text = widget.controller.text;
    if (!text.contains(',') && !text.contains(';') && !text.contains('\n')) {
      return;
    }
    _commit(text);
  }

  void _commit(String text) => _add(_parseRecipients(text, kind: widget.kind));

  /// Appends [incoming] and clears the field, so the caret is ready for the
  /// next address.
  void _add(Iterable<MailRecipient> incoming) {
    final merged = _mergeRecipients(widget.recipients, incoming);
    if (merged.length != widget.recipients.length) widget.onChanged(merged);
    if (widget.controller.text.isNotEmpty) widget.controller.clear();
  }

  /// Backspace in the empty field takes the last chip back; every other key
  /// belongs to the field.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (widget.controller.text.isNotEmpty || widget.recipients.isEmpty) {
      return KeyEventResult.ignored;
    }
    widget.onChanged([...widget.recipients]..removeLast());
    return KeyEventResult.handled;
  }

  Future<Iterable<MailAddressSuggestion>> _options(TextEditingValue value) async {
    final query = value.text.trim();
    if (query.isEmpty) return const [];
    try {
      final suggestions = <String, MailAddressSuggestion>{};
      for (final senders in [false, true]) {
        final items = await ref.read(
          mailAddressSuggestionsProvider((
            query: query,
            senders: senders,
          )).future,
        );
        for (final item in items) {
          suggestions.putIfAbsent(item.address.toLowerCase(), () => item);
        }
      }
      return suggestions.values;
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Focus sits above the field: key events bubble up from it, so backspace
    // can still take a chip back when the field itself is empty.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _focusNode.requestFocus,
        child: InputDecorator(
          isFocused: _focusNode.hasFocus,
          isEmpty: widget.recipients.isEmpty && widget.controller.text.isEmpty,
          decoration: _CompactLabeledField.decoration(
            suffixIcon: widget.suffixIcon,
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final recipient in widget.recipients)
                EmailRecipientChip(
                  recipient: recipient,
                  mailHost: widget.mailHost,
                  sender: _picked[recipient.address.trim().toLowerCase()],
                  onDeleted: () => widget.onChanged(
                    [...widget.recipients]..remove(recipient),
                  ),
                ),
              // The address field keeps the line's leftover width and grows
              // with what is typed, down to an obvious click target.
              IntrinsicWidth(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 96),
                  child: Autocomplete<MailAddressSuggestion>(
                    textEditingController: widget.controller,
                    focusNode: _focusNode,
                    displayStringForOption: (option) => option.address,
                    optionsBuilder: _options,
                    onSelected: (option) {
                      _picked[option.address.toLowerCase()] = option;
                      _add([
                        MailRecipient(
                          address: option.address,
                          name: option.name,
                          kind: widget.kind,
                        ),
                      ]);
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) =>
                            TextField(
                              controller: controller,
                              focusNode: focusNode,
                              style: text.bodyLarge,
                              // Enter commits and keeps the caret here: a
                              // recipient row usually holds several addresses.
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                isCollapsed: true,
                                contentPadding: EdgeInsets.zero,
                                filled: false,
                                // Every slot: the app's input theme supplies
                                // outlined borders, and one inside the row's
                                // own box would read as a second field.
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                              ),
                              onSubmitted: _commit,
                              onTapOutside: (_) => focusNode.unfocus(),
                            ),
                    optionsViewBuilder: (context, onSelected, options) => Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 6,
                        borderRadius: BorderRadius.circular(8),
                        clipBehavior: Clip.antiAlias,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: 280,
                            maxWidth: 420,
                          ),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (context, index) {
                              final option = options.elementAt(index);
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 17,
                                  child: ClipOval(
                                    child: option.avatarUrl.isEmpty
                                        ? const Icon(
                                            Icons.person_outline,
                                            size: 18,
                                          )
                                        : Image.network(
                                            option.avatarUrl,
                                            width: 34,
                                            height: 34,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) =>
                                                const Icon(
                                                  Icons.person_outline,
                                                  size: 18,
                                                ),
                                          ),
                                  ),
                                ),
                                title: Text(
                                  option.name ?? option.address,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  option.address,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => onSelected(option),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ends one address and starts the next in a typed or pasted recipient list.
final _recipientSeparators = RegExp(r'[,;\n]');

/// Splits a typed or pasted recipient list on the separators mail clients
/// accept, dropping blanks and repeats.
List<MailRecipient> _parseRecipients(String text, {String kind = 'to'}) {
  final seen = <String>{};
  final recipients = <MailRecipient>[];
  for (final part in text.split(_recipientSeparators)) {
    final address = part.trim();
    if (address.isEmpty || !seen.add(address.toLowerCase())) continue;
    recipients.add(MailRecipient(address: address, kind: kind));
  }
  return recipients;
}

/// [recipients] plus [incoming], without blanks or addresses already carried.
List<MailRecipient> _mergeRecipients(
  List<MailRecipient> recipients,
  Iterable<MailRecipient> incoming,
) {
  final seen = {
    for (final recipient in recipients) recipient.address.trim().toLowerCase(),
  };
  return [
    ...recipients,
    for (final recipient in incoming)
      if (recipient.address.trim().isNotEmpty &&
          seen.add(recipient.address.trim().toLowerCase()))
        recipient,
  ];
}

/// Renders the embeds the compose editor has no builder for — a quoted
/// reply's inline `<img src>` — instead of failing the line that holds them.
class _ComposeUnknownEmbed extends EmbedBuilder {
  const _ComposeUnknownEmbed();

  @override
  String get key => 'unknown';

  /// Inline images sit on the text's middle rather than demanding a baseline.
  @override
  WidgetSpan buildWidgetSpan(Widget widget) =>
      WidgetSpan(alignment: PlaceholderAlignment.middle, child: widget);

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final source = embedContext.node.value.data;
    if (source is! String || source.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Image.network(
        source,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.broken_image, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                source,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendEmailIntent extends Intent {
  const _SendEmailIntent();
}

class _SaveDraftIntent extends Intent {
  const _SaveDraftIntent();
}

class _MailboxDraft {
  const _MailboxDraft({
    required this.address,
    this.name,
    this.isDefault = false,
  });

  final String address;
  final String? name;
  final bool isDefault;
}

class _CreateMailboxSheet extends ConsumerStatefulWidget {
  const _CreateMailboxSheet();

  @override
  ConsumerState<_CreateMailboxSheet> createState() =>
      _CreateMailboxSheetState();
}

class _CreateMailboxSheetState extends ConsumerState<_CreateMailboxSheet> {
  final _addressController = TextEditingController();
  final _nameController = TextEditingController();
  var _isDefault = false;

  @override
  void dispose() {
    _addressController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      showSnackBar('addressRequired'.tr());
      return;
    }
    Navigator.pop(
      context,
      _MailboxDraft(
        address: address,
        name: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        isDefault: _isDefault,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mailHost = ref.watch(mailHostProvider).value;
    final fullAddress = MailMailbox(
      id: '',
      accountId: '',
      address: _addressController.text,
    ).fullAddress(mailHost);

    return SheetScaffold(
      titleText: 'newMailbox'.tr(),
      heightFactor: 0.6,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _addressController,
              decoration: InputDecoration(
                labelText: 'mailboxAddress'.tr(),
                hintText: 'alice',
                helperText: mailHost?.isNotEmpty == true
                    ? 'mailboxAddressHelperWithHost'.tr(
                        namedArgs: {'host': mailHost!},
                      )
                    : 'mailboxAddressHelperNoHost'.tr(),
                prefixIcon: const Icon(Symbols.alternate_email),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              keyboardType: TextInputType.text,
              onChanged: (_) => setState(() {}),
            ),
            if (fullAddress.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'mailboxAddressPreview'.tr(
                    namedArgs: {'address': fullAddress},
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'mailboxName'.tr(),
                hintText: 'Alice',
                prefixIcon: const Icon(Symbols.badge),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _isDefault,
              onChanged: (value) => setState(() => _isDefault = value ?? false),
              title: Text('setAsDefaultMailbox'.tr()),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Symbols.add, size: 18),
              label: Text('createMailbox'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
