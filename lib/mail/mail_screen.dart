import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_saver/file_saver.dart';
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

import 'package:solwatt/mail/mail_address_suggestion.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/ui/alert.dart';
import 'package:solwatt/ui/cloud_files.dart';
import 'package:solwatt/ui/page_scaffold.dart';
import 'package:solwatt/main.dart';
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
    return const SafeArea(
      child: Padding(padding: EdgeInsets.all(8), child: _MailListWidget()),
    );
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
      ref.invalidate(emailsProvider);
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
  MailEmail? _selectedEmail;
  final _take = 20;
  int _offset = 0;
  final List<MailEmail> _emails = [];
  int _total = 0;
  bool _isLoadingMore = false;
  final _searchController = TextEditingController();
  bool _searchOpen = false;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Resets the paged list state when the mailbox, folder, or query changes.
  void _resetList() {
    setState(() {
      _selectedEmail = null;
      _offset = 0;
      _emails.clear();
      _total = 0;
    });
  }

  void _selectMailbox(String id) {
    if (ref.read(selectedMailboxIdProvider) == id) return;
    ref.read(selectedMailboxIdProvider.notifier).select(id);
    _resetList();
    ref.invalidate(emailsProvider);
  }

  void _selectFolder(String folder) {
    if (ref.read(selectedFolderProvider) == folder) return;
    ref.read(selectedFolderProvider.notifier).select(folder);
    _resetList();
    ref.invalidate(emailsProvider);
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _resetList();
      ref.invalidate(emailsProvider);
    });
  }

  Future<void> _toggleStar(MailEmail email) async {
    try {
      await ref
          .read(wattEngineClientProvider)
          .starEmail(email.id, starred: !email.isStarred);
      ref.invalidate(emailsProvider);
    } catch (error) {
      showSnackBar(error.toString());
    }
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
      ref.invalidate(emailsProvider);
    });
    final mailboxes = ref.watch(mailboxesProvider);
    final mailHost = ref.watch(mailHostProvider);
    final workspaceId = ref.watch(selectedWorkspaceProvider).value?.id;
    final selectedMailboxId = ref.watch(selectedMailboxIdProvider);
    final folder = ref.watch(selectedFolderProvider);
    final mailboxId = _effectiveMailboxId(mailboxes.value, selectedMailboxId);
    final unreadCounts =
        ref.watch(mailboxUnreadCountsProvider).value ?? const <String, int>{};
    return _buildEmailList(
      mailHost.value,
      workspaceId: workspaceId,
      mailboxId: mailboxId,
      folder: folder,
      mailboxSelector: _buildMailboxSelector(
        mailboxes,
        mailHost: mailHost.value,
        mailboxId: mailboxId,
      ),
      inboxUnread: mailboxId == null ? 0 : (unreadCounts[mailboxId] ?? 0),
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
        // Narrow screens switch inboxes from the bottom navigation bar, so
        // the header only shows the current inbox title.
        if (items.isNotEmpty && !isWideScreen(context)) {
          final current =
              items.where((m) => m.id == mailboxId).firstOrNull ??
              items.firstWhere((m) => m.isDefault, orElse: () => items.first);
          return Text(
            current.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
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
    String? workspaceId,
    required String folder,
  }) => (
    mailboxId: mailboxId,
    workspaceId: workspaceId,
    folder: folder,
    q: _searchController.text.trim().isEmpty
        ? null
        : _searchController.text.trim(),
    status: _deliveryStatus,
    isFlagged: _isFlagged,
    isRead: null,
    isStarred: null,
    labelId: null,
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
      _selectedEmail = null;
      _offset = 0;
      _emails.clear();
      _total = 0;
    });
    ref.invalidate(emailsProvider);
  }

  Widget _buildEmailList(
    String? mailHost, {
    String? workspaceId,
    String? mailboxId,
    required String folder,
    required Widget mailboxSelector,
    required int inboxUnread,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            children: [
              _MailListHeader(
                mailboxSelector: mailboxSelector,
                searchController: _searchController,
                searchOpen: _searchOpen,
                onToggleSearch: () {
                  setState(() {
                    _searchOpen = !_searchOpen;
                    if (!_searchOpen) _searchController.clear();
                  });
                  if (!_searchOpen) _resetList();
                  ref.invalidate(emailsProvider);
                },
                onSearchChanged: _onSearchChanged,
                folder: folder,
                inboxUnread: inboxUnread,
                onSelectFolder: _selectFolder,
                hasDiscoveryFilters: _hasDiscoveryFilters,
                onOpenSettings: () => _openSettings(context),
                onShowFilters: () => _showEmailFilters(context),
              ),
              const Divider(height: 1),
              Expanded(
                // Crossfade between lists when the rail (or bottom bar/folder
                // chips) switches mailbox or folder, so the reload doesn't
                // blink from a stale list to a spinner.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: _EmailList(
                    key: ValueKey('$mailboxId/$folder'),
                    mailboxId: mailboxId,
                    workspaceId: workspaceId,
                    filter: _emailFilter(
                      mailboxId: mailboxId,
                      workspaceId: workspaceId,
                      folder: folder,
                    ),
                    mailHost: mailHost,
                    selectedEmail: _selectedEmail,
                    onOpen: (email) => _openEmail(context, email),
                    onToggleStar: _toggleStar,
                    onDelete: (context, ref, email) =>
                        _deleteEmail(context, ref, email, closeDetail: false),
                    onMove: (ref, email, folder) =>
                        _moveEmailFromList(ref, email, folder),
                    onRefresh: () => _refreshEmails(ref),
                    onLoadMore: () => _loadMoreEmails(ref),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'mail-compose-fab',
              tooltip: 'compose'.tr(),
              onPressed: () => _compose(context),
              child: const Icon(Symbols.edit),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshEmails(WidgetRef ref) async {
    setState(() {
      _offset = 0;
      _emails.clear();
      _total = 0;
    });
    ref.invalidate(emailsProvider);
  }

  Future<void> _loadMoreEmails(WidgetRef ref) async {
    if (_isLoadingMore || _emails.length >= _total) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = await ref
          .read(wattEngineClientProvider)
          .listEmails(
            mailboxId: _effectiveMailboxId(),
            workspaceId: ref.read(selectedWorkspaceProvider).value?.id,
            folder: ref.read(selectedFolderProvider),
            q: _searchController.text.trim().isEmpty
                ? null
                : _searchController.text.trim(),
            status: _deliveryStatus,
            isFlagged: _isFlagged,
            from: _from,
            to: _to,
            hasAttachments: _hasAttachments,
            offset: _offset + _take,
            take: _take,
          );
      if (!mounted) return;
      setState(() {
        _offset += _take;
        _emails.addAll(page.items);
        _total = page.totalCount;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      showSnackBar(error.toString());
    }
  }

  void _openEmail(BuildContext context, MailEmail email) {
    final wide = isWideScreen(context);
    if (!email.isRead && email.id.isNotEmpty) {
      _markRead(email.id);
    }
    setState(() => _selectedEmail = email);
    final route = MailDetailRoute(emailId: email.id);
    if (wide) {
      context.router.navigate(route);
    } else {
      context.router.push(route);
    }
  }

  Future<void> _markRead(String emailId) async {
    try {
      await ref.read(wattEngineClientProvider).markEmailRead(emailId);
      ref.invalidate(emailsProvider);
    } catch (error) {
      showSnackBar(error.toString());
    }
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
      data: (value) => _EmailDetailPanel(
        key: ValueKey(value.id),
        email: value,
        mailHost: mailHost,
        workspaceId:
            value.mailbox?.workspaceId ??
            ref.watch(selectedWorkspaceProvider).value?.id,
        onReply: () => _composeEmail(context, value),
        onReplyAll: () => _composeEmail(context, value, replyAll: true),
        onForward: () => _forwardEmail(context, value),
        onResend: value.isDraft ? null : () => _resendEmail(ref, value),
        onToggleRead: () => _toggleEmailRead(ref, value),
        onToggleStar: () => _toggleEmailStar(ref, value),
        onMove: (folder) => _moveEmail(context, ref, value, folder),
        onDownloadEml: () => _downloadEmailEml(context, ref, value),
        onDelete: () => _deleteEmail(context, ref, value),
        onClose: () => context.router.pop(),
      ),
    );
  }
}

Future<void> _toggleEmailStar(WidgetRef ref, MailEmail email) async {
  try {
    await ref
        .read(wattEngineClientProvider)
        .starEmail(email.id, starred: !email.isStarred);
    ref.invalidate(emailProvider(email.id));
    ref.invalidate(emailsProvider);
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
    ref.invalidate(emailsProvider);
    if (context.mounted) context.router.pop();
    showSnackBar(
      'movedToFolder'.tr(namedArgs: {'folder': mailFolderLabel(folder)}),
    );
  } catch (error) {
    showSnackBar(error.toString());
  }
}

/// Moves a message from the list context menu, which has no detail route to
/// pop after the move.
Future<void> _moveEmailFromList(
  WidgetRef ref,
  MailEmail email,
  String folder,
) async {
  try {
    await ref.read(wattEngineClientProvider).moveEmail(email.id, folder);
    ref.invalidate(emailsProvider);
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
    ref.invalidate(emailProvider(email.id));
    ref.invalidate(emailsProvider);
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
    ref.invalidate(emailProvider(email.id));
    ref.invalidate(emailsProvider);
  } catch (error) {
    showSnackBar(error.toString());
  }
}

Future<void> _deleteEmail(
  BuildContext context,
  WidgetRef ref,
  MailEmail email, {
  bool closeDetail = true,
}) async {
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
    ref.invalidate(emailsProvider);
    if (closeDetail && context.mounted) context.router.pop();
    showSnackBar('emailDeleted'.tr());
  } catch (error) {
    showSnackBar(error.toString());
  }
}

class _MailListHeader extends StatelessWidget {
  const _MailListHeader({
    required this.mailboxSelector,
    required this.searchController,
    required this.searchOpen,
    required this.onToggleSearch,
    required this.onSearchChanged,
    required this.folder,
    required this.inboxUnread,
    required this.onSelectFolder,
    required this.hasDiscoveryFilters,
    required this.onOpenSettings,
    required this.onShowFilters,
  });

  final Widget mailboxSelector;
  final TextEditingController searchController;
  final bool searchOpen;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onSearchChanged;
  final String folder;
  final int inboxUnread;
  final ValueChanged<String> onSelectFolder;
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
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'searchEmailsHint'.tr(),
                prefixIcon: const Icon(Symbols.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        // On wide screens the desktop rail already lists every folder, so the
        // horizontal switcher would be redundant; keep it only where the rail
        // is absent.
        if (!isWideScreen(context))
          _FolderTabs(
            folder: folder,
            inboxUnread: inboxUnread,
            onSelect: onSelectFolder,
          ),
      ],
    );
  }
}

/// Horizontal folder switcher (Inbox, Sent, Drafts, Spam, Trash, Archive),
/// mirroring the folders of a desktop mail client.
class _FolderTabs extends StatelessWidget {
  const _FolderTabs({
    required this.folder,
    required this.inboxUnread,
    required this.onSelect,
  });

  static const _folders = [
    'inbox',
    'sent',
    'drafts',
    'spam',
    'trash',
    'archive',
  ];

  final String folder;
  final int inboxUnread;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: _folders.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final id = _folders[index];
          final selected = id == folder;
          final label = mailFolderLabel(id);
          return ChoiceChip(
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => onSelect(id),
            avatar: id == 'inbox' && inboxUnread > 0
                ? Badge(
                    label: Text(inboxUnread > 99 ? '99+' : '$inboxUnread'),
                    child: const Icon(Symbols.mail, size: 16),
                  )
                : null,
            label: Text(label),
          );
        },
      ),
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

class _EmailList extends ConsumerWidget {
  const _EmailList({
    super.key,
    required this.mailboxId,
    required this.workspaceId,
    required this.filter,
    required this.mailHost,
    required this.selectedEmail,
    required this.onOpen,
    required this.onToggleStar,
    required this.onDelete,
    required this.onMove,
    required this.onRefresh,
    required this.onLoadMore,
  });

  final String? mailboxId;
  final String? workspaceId;
  final EmailListFilter filter;
  final String? mailHost;
  final MailEmail? selectedEmail;
  final ValueChanged<MailEmail> onOpen;
  final ValueChanged<MailEmail> onToggleStar;
  final Future<void> Function(BuildContext, WidgetRef, MailEmail) onDelete;
  final Future<void> Function(WidgetRef, MailEmail, String) onMove;
  final VoidCallback onRefresh;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emails = ref.watch(emailsProvider(filter));

    return emails.when(
      loading: () => const PageLoading(),
      error: (error, _) =>
          PageError(message: error.toString(), onRetry: onRefresh),
      data: (page) {
        final items = page.items;
        if (items.isEmpty) {
          return EmptyState(
            icon: Symbols.mail_outline,
            title: 'noEmails'.tr(),
            message: 'noEmailsDescription'.tr(),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => onRefresh(),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length + (items.length < page.totalCount ? 1 : 0),
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == items.length) {
                onLoadMore();
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final email = items[index];
              return _EmailTile(
                email: email,
                mailHost: mailHost,
                selected: email.id == selectedEmail?.id,
                onTap: () => onOpen(email),
                onToggleStar: () => onToggleStar(email),
                onToggleRead: () => _toggleEmailRead(ref, email),
                onDelete: () => onDelete(context, ref, email),
                onMove: (folder) => onMove(ref, email, folder),
              );
            },
          ),
        );
      },
    );
  }
}

class _EmailTile extends StatelessWidget {
  const _EmailTile({
    required this.email,
    required this.mailHost,
    required this.onTap,
    required this.onToggleStar,
    required this.onToggleRead,
    required this.onDelete,
    required this.onMove,
    this.selected = false,
  });

  final MailEmail email;
  final String? mailHost;
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
    final fromAddress = email.from?.fullAddress(mailHost) ?? '';
    final fromName = email.from?.displayName ?? '';
    final from = fromName.isNotEmpty ? fromName : fromAddress;
    final date = email.createdAt;

    return ContextMenuWidget(
      menuProvider: (_) => Menu(
        children: emailContextMenuItems(
          email: email,
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
        leading: Icon(
          email.isRead ? Symbols.mail_outline : Symbols.mail,
          size: 20,
          color: email.isRead ? scheme.onSurfaceVariant : scheme.primary,
          fill: email.isRead ? 0 : 1,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                from,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(
                  fontWeight: email.isRead
                      ? FontWeight.normal
                      : FontWeight.w600,
                ),
              ),
            ),
            if (date != null)
              Text(
                _formatDate(date),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              email.displaySubject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(
                fontWeight: email.isRead ? FontWeight.normal : FontWeight.w600,
              ),
            ),
            if (email.previewText.isNotEmpty)
              Text(
                email.previewText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            if (email.hasDeliveryStatus && !email.isDraft) ...[
              const SizedBox(height: 6),
              _DeliveryStatusChip(status: email.deliveryStatus!),
            ],
          ],
        ),
        isThreeLine: false,
        onTap: onTap,
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }
}

/// Menu items shown when a message tile or its detail view is right-clicked.
///
/// Kept as a plain function so the menu contract (destructive delete, star
/// check state, folder moves) is unit-testable without a native menu.
List<MenuElement> emailContextMenuItems({
  required MailEmail email,
  required VoidCallback onToggleRead,
  required VoidCallback onToggleStar,
  required ValueChanged<String> onMove,
  required VoidCallback onDelete,
}) => [
  MenuAction(
    title: (email.isRead ? 'markUnread' : 'markRead').tr(),
    image: MenuImage.icon(
      email.isRead ? Symbols.mark_email_unread : Symbols.mark_email_read,
    ),
    callback: onToggleRead,
  ),
  MenuAction(
    title: (email.isStarred ? 'unstar' : 'star').tr(),
    image: MenuImage.icon(
      email.isStarred ? Symbols.star : Symbols.star_outline,
    ),
    state: email.isStarred ? MenuActionState.checkOn : MenuActionState.none,
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

  final MailEmail email;
  final String? mailHost;
  final String? workspaceId;
  final VoidCallback onReply;
  final VoidCallback onReplyAll;
  final VoidCallback onForward;
  final VoidCallback? onResend;
  final VoidCallback onToggleRead;
  final VoidCallback onToggleStar;
  final ValueChanged<String> onMove;
  final VoidCallback onDelete;
  final VoidCallback onDownloadEml;
  final VoidCallback onClose;

  @override
  State<_EmailDetailPanel> createState() => _EmailDetailPanelState();
}

class _EmailDetailPanelState extends State<_EmailDetailPanel> {
  /// Initial header height before the summary is measured; replaced by the
  /// exact content height after the first layout so the expanded header
  /// hugs the summary with no dead space.
  static const _estimateSummaryHeight = 180.0;

  final _summaryKey = GlobalKey();
  double? _summaryHeight;

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
    final email = widget.email;
    final scheme = Theme.of(context).colorScheme;
    final expandedHeight =
        _EmailHeaderSpace.toolbarHeight +
        (_summaryHeight ?? _estimateSummaryHeight);

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: scheme.surfaceContainerLow,
                  surfaceTintColor: Colors.transparent,
                  scrolledUnderElevation: 1,
                  leading: IconButton(
                    tooltip: 'close'.tr(),
                    onPressed: widget.onClose,
                    icon: const Icon(Symbols.close),
                  ),
                  actions: [
                    IconButton(
                      tooltip: email.isStarred ? 'unstar'.tr() : 'star'.tr(),
                      onPressed: widget.onToggleStar,
                      icon: Icon(
                        email.isStarred ? Symbols.star : Symbols.star_outline,
                        color: email.isStarred
                            ? Colors.amber.shade600
                            : scheme.onSurfaceVariant,
                        fill: email.isStarred ? 1 : 0,
                      ),
                    ),
                    IconButton(
                      tooltip: email.isRead
                          ? 'markUnread'.tr()
                          : 'markRead'.tr(),
                      onPressed: widget.onToggleRead,
                      icon: Icon(email.isRead ? Symbols.mail : Symbols.drafts),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'more'.tr(),
                      icon: const Icon(Symbols.more_vert),
                      onSelected: (value) {
                        if (value == 'archive') widget.onMove('archive');
                        if (value == 'spam') widget.onMove('spam');
                        if (value == 'trash') widget.onMove('trash');
                        if (value == 'download-eml') widget.onDownloadEml();
                      },
                      itemBuilder: (_) => [
                        if (email.folder != 'archive')
                          PopupMenuItem(
                            value: 'archive',
                            child: Text('folderArchive'.tr()),
                          ),
                        if (email.folder != 'spam')
                          PopupMenuItem(
                            value: 'spam',
                            child: Text('folderSpam'.tr()),
                          ),
                        if (email.folder != 'trash')
                          PopupMenuItem(
                            value: 'trash',
                            child: Text('folderTrash'.tr()),
                          ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'download-eml',
                          child: Text('downloadEml'.tr()),
                        ),
                      ],
                    ),
                    IconButton(
                      tooltip: 'delete'.tr(),
                      onPressed: widget.onDelete,
                      icon: Icon(Symbols.delete, color: scheme.error),
                    ),
                  ],
                  expandedHeight: expandedHeight,
                  flexibleSpace: _EmailHeaderSpace(
                    email: email,
                    mailHost: widget.mailHost,
                    summaryKey: _summaryKey,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _EmailDetailContent(
                    email: email,
                    workspaceId: widget.workspaceId,
                  ),
                ),
              ],
            ),
          ),
          _EmailActionBar(
            onReply: widget.onReply,
            onReplyAll: widget.onReplyAll,
            onForward: widget.onForward,
            onResend: email.deliveryStatus?.toLowerCase() == 'failed'
                ? widget.onResend
                : null,
          ),
        ],
      ),
    );
  }
}

/// Collapsible email summary in the detail header: subject and recipient
/// metadata live above the scroll content and fade out as the pinned
/// [SliverAppBar] collapses to just the action toolbar.
class _EmailHeaderSpace extends StatelessWidget {
  const _EmailHeaderSpace({
    required this.email,
    required this.mailHost,
    required this.summaryKey,
  });

  /// Height of the pinned toolbar row (close + actions).
  static const toolbarHeight = 56.0;

  final MailEmail email;
  final String? mailHost;
  final GlobalKey summaryKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final remaining = constraints.maxHeight;
        // Fade out over the first ~80px of collapse so the summary never
        // shows through the transparent toolbar as it slides under it.
        final opacity = ((remaining - toolbarHeight) / 80).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          // Align fills the flexible space and pins the summary to the
          // bottom; the inner UnconstrainedBox keeps the Column at its
          // natural height (no tight max → no RenderFlex overflow) while
          // hardEdge clips the part that rises above the toolbar.
          child: Align(
            alignment: Alignment.bottomLeft,
            child: UnconstrainedBox(
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: constraints.maxWidth,
                child: Padding(
                  key: summaryKey,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        email.displaySubject,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _EmailMetadata(
                        email: email,
                        mailHost: mailHost,
                        dateStyle: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmailDetailContent extends StatelessWidget {
  const _EmailDetailContent({required this.email, required this.workspaceId});

  final MailEmail email;
  final String? workspaceId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final attachmentWorkspaceId = email.mailbox?.workspaceId ?? workspaceId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        // The HTML body spans the full pane width; plain text keeps padding.
        if (email.isHtml)
          _HtmlBodyViewer(
            html: email.body,
            attachments: email.attachments,
            inlineAttachments: email.inlineAttachments,
            workspaceId: attachmentWorkspaceId,
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: _PlainTextEmailBody(
              body: email.body,
              attachments: email.attachments,
              workspaceId: attachmentWorkspaceId,
              style: text.bodyLarge,
            ),
          ),
        if (email.attachments.isNotEmpty ||
            (email.hasDeliveryStatus && !email.isDraft))
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (email.attachments.isNotEmpty) ...[
                  Text('attachments'.tr(), style: text.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final attachment in email.attachments)
                        CloudFileChip(
                          file: attachment,
                          displayUrl: _cloudFileUri(
                            attachment,
                            attachmentWorkspaceId,
                          ).toString(),
                          onPressed: () => _openAttachment(
                            context,
                            attachment,
                            attachmentWorkspaceId,
                          ),
                        ),
                    ],
                  ),
                ],
                if (email.hasDeliveryStatus && !email.isDraft) ...[
                  if (email.attachments.isNotEmpty) const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _DeliveryStatusChip(status: email.deliveryStatus!),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'deliveryAttempts'.tr(
                            namedArgs: {
                              'count': email.deliveryAttempts.toString(),
                            },
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
                            'date': email.lastDeliveryAttemptAt!
                                .toLocal()
                                .toString(),
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
          )
        else
          const SizedBox(height: 32),
      ],
    );
  }

  Future<void> _openAttachment(
    BuildContext context,
    IDisplayableCloudFile attachment,
    String? workspaceId,
  ) async {
    final uri = _cloudFileUri(attachment, workspaceId);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      showSnackBar('Unable to open ${attachment.name}.');
    }
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
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (onResend != null) ...[
              OutlinedButton.icon(
                onPressed: onResend,
                icon: const Icon(Symbols.refresh, size: 18),
                label: Text('resend'.tr()),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const Spacer(),
            ],
            IconButton(
              tooltip: 'replyAll'.tr(),
              onPressed: onReplyAll,
              icon: const Icon(Symbols.reply_all),
            ),
            IconButton(
              tooltip: 'forward'.tr(),
              onPressed: onForward,
              icon: const Icon(Symbols.forward),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onReply,
              icon: const Icon(Symbols.reply, size: 18),
              label: Text('reply'.tr()),
              style: FilledButton.styleFrom(
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

class _PlainTextEmailBody extends StatelessWidget {
  const _PlainTextEmailBody({
    required this.body,
    required this.attachments,
    required this.workspaceId,
    this.style,
  });

  final String body;
  final List<SnCloudFileReference> attachments;
  final String? workspaceId;
  final TextStyle? style;

  static final _imageMarker = RegExp(
    r'\[image:\s*([^\]\r\n]+)\]',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    if (body.isEmpty) return SelectableText('(no body)', style: style);

    final children = <Widget>[];
    var cursor = 0;
    for (final match in _imageMarker.allMatches(body)) {
      if (match.start > cursor) {
        children.add(
          SelectableText(body.substring(cursor, match.start), style: style),
        );
      }
      final filename = match.group(1)!.trim().toLowerCase();
      final attachment = _imageAttachmentForFilename(attachments, filename);
      // Drop markers with no matching attachment instead of showing the raw
      // preview-generation syntax in the message.
      if (attachment != null) {
        children.add(
          _InlineEmailImage(file: attachment, workspaceId: workspaceId),
        );
      }
      cursor = match.end;
    }
    if (cursor < body.length) {
      children.add(SelectableText(body.substring(cursor), style: style));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _InlineEmailImage extends StatelessWidget {
  const _InlineEmailImage({required this.file, required this.workspaceId});

  final SnCloudFileReference file;
  final String? workspaceId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          _cloudFileUri(file, workspaceId).toString(),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => CloudFileChip(
            file: file,
            displayUrl: _cloudFileUri(file, workspaceId).toString(),
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
  });

  final String html;
  final List<SnCloudFileReference> attachments;
  final Map<String, SnCloudFileReference> inlineAttachments;
  final String? workspaceId;

  @override
  ConsumerState<_HtmlBodyViewer> createState() => _HtmlBodyViewerState();
}

class _HtmlBodyViewerState extends ConsumerState<_HtmlBodyViewer> {
  /// Fallback height before the first measurement and for an empty body, so an
  /// empty message does not collapse the pane.
  static const _placeholderHeight = 120.0;

  double? _contentHeight;
  String? _preparedHtml;

  /// macOS never reports content-size changes (the plugin only implements the
  /// JavaScript `document.body.scrollHeight` query), and that query can run
  /// before inline images have decoded, so the height is polled until two
  /// consecutive probes agree.
  Timer? _settleTimer;
  double _lastProbe = -1;
  int _stableProbes = 0;

  @override
  void initState() {
    super.initState();
    _prepareHtml();
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(_HtmlBodyViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html ||
        oldWidget.inlineAttachments != widget.inlineAttachments ||
        oldWidget.workspaceId != widget.workspaceId) {
      _settleTimer?.cancel();
      _contentHeight = null;
      _preparedHtml = null;
      _lastProbe = -1;
      _stableProbes = 0;
      _prepareHtml();
    }
  }

  Future<void> _prepareHtml() async {
    final imageFiles = <String, SnCloudFileReference>{
      for (final attachment in widget.attachments)
        if (attachment.mimeType.startsWith('image/')) attachment.id: attachment,
      for (final attachment in widget.inlineAttachments.values)
        if (attachment.mimeType.startsWith('image/')) attachment.id: attachment,
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
      _preparedHtml = sanitizeEmailHtml(
        _replaceInlineImageReferences(
          widget.html,
          widget.attachments,
          widget.inlineAttachments,
          widget.workspaceId,
          resolvedImageUrls: urls,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final html = _preparedHtml;
    if (html == null) {
      return const SizedBox(
        height: _HtmlBodyViewerState._placeholderHeight,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: _contentHeight ?? _HtmlBodyViewerState._placeholderHeight,
      child: InAppWebView(
        initialData: InAppWebViewInitialData(
          // Render the server's HTML body directly. The .eml endpoint is only
          // for downloading a serialized message, never for the reading view.
          data: html,
          mimeType: 'text/html',
          encoding: 'utf-8',
          baseUrl: WebUri(kSolarNetworkApiBase),
        ),
        initialSettings: InAppWebViewSettings(
          // Required: on macOS the platform's only way to measure the document
          // is `document.body.scrollHeight` through JavaScript. Message
          // scripts are stripped in [_sanitizeEmailHtml] so nothing of the
          // sender's executes.
          javaScriptEnabled: true,
          transparentBackground: true,
          verticalScrollBarEnabled: false,
          horizontalScrollBarEnabled: false,
          disableVerticalScroll: true,
          disableHorizontalScroll: true,
          supportZoom: false,
          mediaPlaybackRequiresUserGesture: true,
          useShouldOverrideUrlLoading: true,
        ),
        onLoadStop: (controller, url) => _settleContentHeight(controller),
        onProgressChanged: (controller, progress) {
          if (progress == 100) _settleContentHeight(controller);
        },
        onContentSizeChanged: (controller, oldSize, newSize) {
          _applyContentHeight(newSize.height);
        },
        shouldOverrideUrlLoading: (controller, navigationAction) async {
          if (!shouldOpenEmailLinkExternally(navigationAction)) {
            return NavigationActionPolicy.ALLOW;
          }
          final url = navigationAction.request.url!;
          try {
            await launchUrl(url, mode: LaunchMode.externalApplication);
          } catch (_) {}
          return NavigationActionPolicy.CANCEL;
        },
      ),
    );
  }

  /// Full document height, including the body's own margins and anything
  /// overflowing `<html>` — the platform helper only reads
  /// `document.body.scrollHeight`, which clips both.
  static const _contentHeightScript =
      'Math.max(document.body.scrollHeight, '
      'document.documentElement.scrollHeight)';

  Future<double?> _probeContentHeight(InAppWebViewController controller) async {
    try {
      final raw = await controller.evaluateJavascript(
        source: _contentHeightScript,
      );
      final height = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (height != null && height > 0) return height;
    } catch (_) {
      // Fall through to the platform helper.
    }
    return (await controller.getContentHeight())?.toDouble();
  }

  /// Polls the document height until two consecutive probes agree, which
  /// covers images that decode after `onLoadStop`.
  void _settleContentHeight(InAppWebViewController controller) {
    _settleTimer?.cancel();
    _lastProbe = -1;
    _stableProbes = 0;
    var ticks = 0;
    _settleTimer = Timer.periodic(const Duration(milliseconds: 150), (
      timer,
    ) async {
      if (!mounted || ++ticks > 20) {
        timer.cancel();
        return;
      }
      final height = await _probeContentHeight(controller);
      if (height == null || height <= 0) return;
      if ((height - _lastProbe).abs() < 1) {
        if (++_stableProbes >= 2) timer.cancel();
      } else {
        _lastProbe = height;
        _stableProbes = 0;
      }
      _applyContentHeight(height);
    });
  }

  void _applyContentHeight(double? height) {
    if (!mounted || height == null || height <= 0) return;
    if ((height - (_contentHeight ?? 0)).abs() < 1) return;
    setState(() => _contentHeight = height);
  }
}

/// Strips active content from untrusted message HTML.
///
/// The message pane runs with JavaScript enabled because the macOS webview
/// measures the document through `document.body.scrollHeight`; without this the
/// sender's scripts would run. Links and styling are untouched — inline event
/// handlers, `<script>` bodies and `javascript:` URLs are removed.
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
    if (file.mimeType.startsWith('image/') &&
        file.name.trim().toLowerCase() == filename) {
      return file;
    }
  }
  return null;
}

class _EmailMetadata extends StatelessWidget {
  const _EmailMetadata({
    required this.email,
    required this.mailHost,
    required this.dateStyle,
  });

  final MailEmail email;
  final String? mailHost;
  final TextStyle? dateStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RecipientRow(
          label: 'from'.tr(),
          recipient: email.from,
          mailHost: mailHost,
        ),
        _RecipientRow(
          label: 'to'.tr(),
          recipients: email.to,
          mailHost: mailHost,
        ),
        if (email.cc.isNotEmpty)
          _RecipientRow(
            label: 'cc'.tr(),
            recipients: email.cc,
            mailHost: mailHost,
          ),
        if (email.bcc.isNotEmpty)
          _RecipientRow(
            label: 'bcc'.tr(),
            recipients: email.bcc,
            mailHost: mailHost,
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

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({
    required this.label,
    this.recipient,
    this.recipients,
    this.mailHost,
  });

  final String label;
  final MailRecipient? recipient;
  final List<MailRecipient>? recipients;
  final String? mailHost;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final list = recipients ?? (recipient == null ? const [] : [recipient!]);
    final value = list
        .map((r) {
          final address = r.fullAddress(mailHost);
          return r.name?.isNotEmpty == true ? '${r.name} <$address>' : address;
        })
        .join(', ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: text.bodyMedium,
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
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
  var _showCcBcc = false;
  var _pickingAttachment = false;
  final _shortcutFocusNode = FocusNode();
  final _bodyFocusNode = FocusNode();
  final Map<TextEditingController, FocusNode> _addressFocusNodes = {};
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
      if (from != null) _toController.text = from.address;
      if (widget.replyAll) {
        final self = _selectedMailbox
            ?.fullAddress(widget.mailHost)
            .toLowerCase();
        final others = [...replyingTo.to, ...replyingTo.cc]
            .where(
              (r) =>
                  r.address.toLowerCase() != self &&
                  r.address.toLowerCase() != from?.address.toLowerCase(),
            )
            .map((r) => r.address)
            .where((a) => a.isNotEmpty)
            .toSet();
        if (others.isNotEmpty) {
          _ccController.text = others.join(', ');
        }
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
    for (final focusNode in _addressFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  List<MailRecipient> _parseRecipients(String text) {
    return text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((address) => MailRecipient(address: address, kind: 'to'))
        .toList();
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

  Widget _addressField(TextEditingController controller) =>
      Autocomplete<MailAddressSuggestion>(
        textEditingController: controller,
        focusNode: _addressFocusNodes.putIfAbsent(controller, FocusNode.new),
        optionsBuilder: (value) async {
          final query = value.text.split(',').last.trim();
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
            return suggestions.values.toList(growable: false);
          } catch (_) {
            return const [];
          }
        },
        onSelected: (option) {
          final text = controller.text;
          final comma = text.lastIndexOf(',');
          final prefix = comma < 0 ? '' : text.substring(0, comma + 1);
          final replacement = '$prefix${option.address}, ';
          controller.value = TextEditingValue(
            text: replacement,
            selection: TextSelection.collapsed(offset: replacement.length),
          );
        },
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 420),
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
                            ? const Icon(Icons.person_outline, size: 18)
                            : Image.network(
                                option.avatarUrl,
                                width: 34,
                                height: 34,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.person_outline, size: 18),
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
      );

  Future<void> _submit({bool draft = false}) async {
    final to = _parseRecipients(_toController.text);
    if (to.isEmpty) {
      showSnackBar('recipientsRequired'.tr());
      return;
    }
    await widget.onSubmitted(
      _MailDraft(
        mailboxId: _mailboxId,
        to: to,
        cc: _parseRecipients(_ccController.text),
        bcc: _parseRecipients(_bccController.text),
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
                      field: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _mailboxId,
                          isDense: true,
                          isExpanded: true,
                          style: Theme.of(context).textTheme.bodyLarge,
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
                      field: _addressField(_toController),
                      suffix: IconButton(
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
                                  field: _addressField(_ccController),
                                  onSubmitted: (_) =>
                                      FocusScope.of(context).nextFocus(),
                                ),
                                const SizedBox(height: 8),
                                _CompactLabeledField(
                                  label: 'bcc'.tr(),
                                  field: _addressField(_bccController),
                                  onSubmitted: (_) =>
                                      FocusScope.of(context).nextFocus(),
                                ),
                              ],
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    const SizedBox(height: 8),
                    _CompactLabeledField(
                      label: 'subject'.tr(),
                      controller: _subjectController,
                      style: textTheme.titleMedium,
                      onSubmitted: (_) => _bodyFocusNode.requestFocus(),
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

/// Compact borderless labeled field used for recipients and subject.
class _CompactLabeledField extends StatelessWidget {
  const _CompactLabeledField({
    required this.label,
    this.controller,
    this.field,
    this.style,
    this.onSubmitted,
    this.suffix,
  }) : assert(field != null || controller != null);

  final String label;
  final TextEditingController? controller;
  final Widget? field;
  final TextStyle? style;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child:
                field ??
                TextField(
                  controller: controller,
                  style: style,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                  textInputAction: TextInputAction.next,
                  onSubmitted: onSubmitted,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                ),
          ),
          ?suffix,
        ],
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
