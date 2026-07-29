import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

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
  const MailComposePage({super.key, @QueryParam('replyTo') this.replyToId});

  final String? replyToId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mailboxes = ref.watch(mailboxesProvider);
    final mailHost = ref.watch(mailHostProvider).value;
    final replyEmail = replyToId == null
        ? null
        : ref.watch(emailProvider(replyToId!));

    if (replyEmail != null) {
      return replyEmail.when(
        loading: () => _composeLoading(context),
        error: (error, _) => _composeError(context, error, ref),
        data: (email) => _buildComposer(
          context,
          ref,
          mailboxes,
          mailHost,
          replyingTo: email,
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
    MailEmail? replyingTo,
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
          (item) => item.id == replyingTo?.mailboxId,
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
            replyingTo: replyingTo,
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
            if (replyToId != null) ref.invalidate(emailProvider(replyToId!));
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
            isDraft: draft.isDraft,
            contentType: draft.contentType,
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
  String? _selectedMailboxId;
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

  @override
  Widget build(BuildContext context) {
    final mailboxes = ref.watch(mailboxesProvider);
    final mailHost = ref.watch(mailHostProvider);
    final workspaceId = ref.watch(selectedWorkspaceProvider).value?.id;
    final mailboxId = _effectiveMailboxId(mailboxes.value);
    return _buildEmailList(
      mailHost.value,
      workspaceId: workspaceId,
      mailboxId: mailboxId,
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
      data: (items) => _MailboxSelector(
        mailboxes: items,
        mailHost: mailHost,
        selectedId: mailboxId,
        onSelected: (id) {
          setState(() {
            _selectedMailboxId = id;
            _selectedEmail = null;
            _offset = 0;
            _emails.clear();
            _total = 0;
          });
          ref.invalidate(emailsProvider);
        },
        onCreate: () => _createMailbox(context),
      ),
    );
  }

  String? _effectiveMailboxId([List<MailMailbox>? mailboxes]) {
    final items = mailboxes ?? ref.read(mailboxesProvider).value;
    if (items == null || items.isEmpty) return null;
    if (items.any((mailbox) => mailbox.id == _selectedMailboxId)) {
      return _selectedMailboxId;
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

  EmailListFilter _emailFilter({String? mailboxId, String? workspaceId}) => (
    mailboxId: mailboxId,
    workspaceId: workspaceId,
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
    required Widget mailboxSelector,
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
                hasDiscoveryFilters: _hasDiscoveryFilters,
                onShowCredentials: () => _showCredentials(context),
                onShowFilters: () => _showEmailFilters(context),
              ),
              const Divider(height: 1),
              Expanded(
                child: _EmailList(
                  mailboxId: mailboxId,
                  workspaceId: workspaceId,
                  filter: _emailFilter(
                    mailboxId: mailboxId,
                    workspaceId: workspaceId,
                  ),
                  mailHost: mailHost,
                  selectedEmail: _selectedEmail,
                  onOpen: (email) => _openEmail(context, email),
                  onRefresh: () => _refreshEmails(ref),
                  onLoadMore: () => _loadMoreEmails(ref),
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

  Future<void> _createMailbox(BuildContext context) async {
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
      if (mounted) showSnackBar('mailboxCreated'.tr());
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  Future<void> _showCredentials(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CredentialsSheet(),
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
        onResend: value.isDraft ? null : () => _resendEmail(ref, value),
        onToggleRead: () => _toggleEmailRead(ref, value),
        onDelete: () => _deleteEmail(context, ref, value),
        onClose: () => context.router.pop(),
      ),
    );
  }
}

void _composeEmail(BuildContext context, MailEmail replyingTo) {
  final route = MailComposeRoute(replyToId: replyingTo.id);
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
    ref.invalidate(emailsProvider);
    if (context.mounted) context.router.pop();
    showSnackBar('emailDeleted'.tr());
  } catch (error) {
    showSnackBar(error.toString());
  }
}

class _MailListHeader extends StatelessWidget {
  const _MailListHeader({
    required this.mailboxSelector,
    required this.hasDiscoveryFilters,
    required this.onShowCredentials,
    required this.onShowFilters,
  });

  final Widget mailboxSelector;
  final bool hasDiscoveryFilters;
  final VoidCallback onShowCredentials;
  final VoidCallback onShowFilters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(child: mailboxSelector),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'mailCredentials'.tr(),
            onPressed: onShowCredentials,
            icon: const Icon(Symbols.key, size: 20),
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
    );
  }
}

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
    required this.mailboxId,
    required this.workspaceId,
    required this.filter,
    required this.mailHost,
    required this.selectedEmail,
    required this.onOpen,
    required this.onRefresh,
    required this.onLoadMore,
  });

  final String? mailboxId;
  final String? workspaceId;
  final EmailListFilter filter;
  final String? mailHost;
  final MailEmail? selectedEmail;
  final ValueChanged<MailEmail> onOpen;
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
    this.selected = false,
  });

  final MailEmail email;
  final String? mailHost;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fromAddress = email.from?.fullAddress(mailHost) ?? '';
    final fromName = email.from?.displayName ?? '';
    final from = fromName.isNotEmpty ? fromName : fromAddress;
    final date = email.createdAt;

    return ListTile(
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
                fontWeight: email.isRead ? FontWeight.normal : FontWeight.w600,
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

class _EmailDetailPanel extends StatelessWidget {
  const _EmailDetailPanel({
    super.key,
    required this.email,
    required this.mailHost,
    required this.workspaceId,
    required this.onReply,
    required this.onResend,
    required this.onToggleRead,
    required this.onDelete,
    required this.onClose,
  });

  final MailEmail email;
  final String? mailHost;
  final String? workspaceId;
  final VoidCallback onReply;
  final VoidCallback? onResend;
  final VoidCallback onToggleRead;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'close'.tr(),
                    onPressed: onClose,
                    icon: const Icon(Symbols.close),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: email.isRead ? 'markUnread'.tr() : 'markRead'.tr(),
                    onPressed: onToggleRead,
                    icon: Icon(email.isRead ? Symbols.mail : Symbols.drafts),
                  ),
                  IconButton(
                    tooltip: 'delete'.tr(),
                    onPressed: onDelete,
                    icon: Icon(Symbols.delete, color: scheme.error),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          Expanded(
            child: _EmailDetailContent(
              email: email,
              mailHost: mailHost,
              workspaceId: workspaceId,
              onReply: onReply,
              onResend: onResend,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailDetailContent extends StatelessWidget {
  const _EmailDetailContent({
    required this.email,
    required this.mailHost,
    required this.workspaceId,
    required this.onReply,
    required this.onResend,
  });

  final MailEmail email;
  final String? mailHost;
  final String? workspaceId;
  final VoidCallback onReply;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final attachmentWorkspaceId = email.mailbox?.workspaceId ?? workspaceId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        email.displaySubject,
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 20),
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
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      email.isHtml
                          ? _HtmlBodyViewer(
                              html: email.body,
                              attachments: email.attachments,
                              inlineAttachments: email.inlineAttachments,
                              workspaceId: attachmentWorkspaceId,
                            )
                          : _PlainTextEmailBody(
                              body: email.body,
                              attachments: email.attachments,
                              workspaceId: attachmentWorkspaceId,
                              style: text.bodyLarge,
                            ),
                      if (email.attachments.isNotEmpty) ...[
                        const SizedBox(height: 24),
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
                        const SizedBox(height: 24),
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
                              style: text.bodySmall?.copyWith(
                                color: scheme.error,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        _EmailActionBar(
          onReply: onReply,
          onResend: email.deliveryStatus?.toLowerCase() == 'failed'
              ? onResend
              : null,
        ),
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
  const _EmailActionBar({required this.onReply, this.onResend});

  final VoidCallback onReply;
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
          mainAxisAlignment: MainAxisAlignment.end,
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
              const SizedBox(width: 8),
            ],
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
      children.add(
        attachment == null
            ? SelectableText(match.group(0)!, style: style)
            : _InlineEmailImage(file: attachment, workspaceId: workspaceId),
      );
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

class _HtmlBodyViewer extends StatefulWidget {
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
  State<_HtmlBodyViewer> createState() => _HtmlBodyViewerState();
}

String _colorHex(Color color) {
  final argb = color.toARGB32();
  return argb.toRadixString(16).padLeft(8, '0').substring(2);
}

class _HtmlBodyViewerState extends State<_HtmlBodyViewer> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bgColor = scheme.surface;
    final textColor = scheme.onSurface;

    final styledHtml =
        '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            font-size: 15px;
            line-height: 1.6;
            color: #${_colorHex(textColor)};
            background: #${_colorHex(bgColor)};
            margin: 0;
            padding: 0;
            word-wrap: break-word;
            overflow-wrap: break-word;
          }
          img { max-width: 100%; height: auto; }
          a { color: #${_colorHex(scheme.primary)}; }
          pre, code { white-space: pre-wrap; word-wrap: break-word; }
          table { max-width: 100%; border-collapse: collapse; }
          blockquote { margin: 0; padding-left: 1em; border-left: 3px solid #${_colorHex(scheme.outlineVariant)}; }
        </style>
      </head>
      <body>${_replaceInlineImageReferences(widget.html, widget.attachments, widget.inlineAttachments, widget.workspaceId)}</body>
      </html>
    ''';

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 600,
        child: InAppWebView(
          initialSettings: InAppWebViewSettings(
            transparentBackground: true,
            supportZoom: false,
            useWideViewPort: true,
            javaScriptEnabled: false,
            cacheEnabled: false,
          ),
          initialData: InAppWebViewInitialData(
            data: styledHtml,
            mimeType: 'text/html',
            encoding: 'utf-8',
          ),
        ),
      ),
    );
  }
}

String _replaceInlineImageReferences(
  String body,
  List<SnCloudFileReference> attachments,
  Map<String, SnCloudFileReference> inlineAttachments,
  String? workspaceId,
) {
  final imageMarker = RegExp(
    r'\[image:\s*([^\]\r\n]+)\]',
    caseSensitive: false,
  );
  final withMarkers = body.replaceAllMapped(imageMarker, (match) {
    final filename = match.group(1)!.trim().toLowerCase();
    final attachment = _imageAttachmentForFilename(attachments, filename);
    if (attachment == null) return match.group(0)!;
    final url = _cloudFileUri(
      attachment,
      workspaceId,
    ).toString().replaceAll('&', '&amp;').replaceAll('"', '&quot;');
    return '<img src="$url" alt="$filename">';
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
      return attachment == null
          ? match.group(0)!
          : _cloudFileUri(attachment, workspaceId).toString();
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
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        maxLines: 2,
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
    this.isDraft = false,
    this.contentType = 'text/plain',
  });

  final String mailboxId;
  final List<MailRecipient> to;
  final List<MailRecipient> cc;
  final List<MailRecipient> bcc;
  final String subject;
  final String body;
  final bool isDraft;
  final String contentType;
}

class _ComposeSheet extends StatefulWidget {
  const _ComposeSheet({
    required this.mailbox,
    required this.mailboxes,
    required this.onSubmitted,
    required this.onClose,
    this.mailHost,
    this.replyingTo,
  });

  final MailMailbox mailbox;
  final List<MailMailbox> mailboxes;
  final Future<void> Function(_MailDraft draft) onSubmitted;
  final VoidCallback onClose;
  final String? mailHost;
  final MailEmail? replyingTo;

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  late String _mailboxId;
  final _toController = TextEditingController();
  final _ccController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  var _isHtml = false;

  MailMailbox? get _selectedMailbox =>
      widget.mailboxes.where((m) => m.id == _mailboxId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _mailboxId = widget.mailbox.id;
    final replyingTo = widget.replyingTo;
    if (replyingTo != null) {
      final from = replyingTo.from;
      if (from != null) {
        _toController.text = from.address;
      }
      _subjectController.text = 'Re: ${replyingTo.displaySubject}';
      _bodyController.text = '\n\n---\n${replyingTo.body}';
      _isHtml = replyingTo.isHtml;
    }
  }

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
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
        bcc: const [],
        subject: _subjectController.text,
        body: _bodyController.text,
        isDraft: draft,
        contentType: _isHtml ? 'text/html' : 'text/plain',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                const SizedBox(width: 8),
                Text(
                  'compose'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _mailboxId,
                  decoration: InputDecoration(
                    labelText: 'fromMailbox'.tr(),
                    prefixIcon: const Icon(Symbols.mail),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: [
                    for (final mailbox in widget.mailboxes)
                      DropdownMenuItem(
                        value: mailbox.id,
                        child: Text(mailbox.displayName),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _mailboxId = value);
                  },
                ),
                if (_selectedMailbox
                        ?.fullAddress(widget.mailHost)
                        .contains('@') !=
                    true) ...[
                  const SizedBox(height: 12),
                  _MailboxInvalidBanner(
                    message: 'mailboxAddressInvalidSend'.tr(),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _toController,
                  decoration: InputDecoration(
                    labelText: 'to'.tr(),
                    hintText: 'recipientHint'.tr(),
                    prefixIcon: const Icon(Symbols.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ccController,
                  decoration: InputDecoration(
                    labelText: 'cc'.tr(),
                    hintText: 'recipientHint'.tr(),
                    prefixIcon: const Icon(Symbols.group),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _subjectController,
                  decoration: InputDecoration(
                    labelText: 'subject'.tr(),
                    prefixIcon: const Icon(Symbols.title),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _bodyController,
                        decoration: InputDecoration(
                          labelText: 'body'.tr(),
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        maxLines: 8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _isHtml,
                  onChanged: (v) => setState(() => _isHtml = v),
                  title: Text('htmlContent'.tr()),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _submit(draft: true),
                        child: Text('saveDraft'.tr()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _submit(),
                        icon: const Icon(Symbols.send, size: 18),
                        label: Text('send'.tr()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
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

class _CredentialsSheet extends ConsumerStatefulWidget {
  const _CredentialsSheet();

  @override
  ConsumerState<_CredentialsSheet> createState() => _CredentialsSheetState();
}

class _CredentialsSheetState extends ConsumerState<_CredentialsSheet> {
  Future<void> _openCreateSheet() async {
    final created = await showModalBottomSheet<MailCredentialCreated>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateCredentialSheet(),
    );
    if (created == null || !mounted) return;
    ref.invalidate(mailCredentialsProvider);
    _showSecret(created);
  }

  Future<void> _revoke(MailCredential credential) async {
    final confirmed = await showConfirmAlert(
      'revokeCredentialConfirm'.tr(namedArgs: {'label': credential.label}),
      'revokeCredential'.tr(),
      icon: Symbols.key,
      isDanger: true,
      confirmLabel: 'revoke'.tr(),
    );
    if (!confirmed) return;
    try {
      await ref
          .read(wattEngineClientProvider)
          .revokeMailCredential(credential.id);
      ref.invalidate(mailCredentialsProvider);
      if (mounted) showSnackBar('credentialRevoked'.tr());
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  void _showSecret(MailCredentialCreated created) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Symbols.key),
        title: Text('credentialCreated'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('saveSecretOnce'.tr()),
            const SizedBox(height: 12),
            SelectableText(
              created.secret,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: created.secret));
              Navigator.pop(context);
              showSnackBar('copied'.tr());
            },
            child: Text('copy'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text('done'.tr()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final credentials = ref.watch(mailCredentialsProvider);
    final mailboxesAsync = ref.watch(mailboxesProvider);
    final mailHost = ref.watch(mailHostProvider).value;
    final scheme = Theme.of(context).colorScheme;
    final mailboxList = mailboxesAsync.maybeWhen(
      data: (data) => data,
      orElse: () => const <MailMailbox>[],
    );

    return SheetScaffold(
      titleText: 'mailCredentials'.tr(),
      actions: [
        IconButton(
          onPressed: _openCreateSheet,
          icon: const Icon(Symbols.add),
          tooltip: 'createCredential'.tr(),
        ),
      ],
      heightFactor: 0.75,
      child: CustomScrollView(
        slivers: [
          ...credentials.when(
            loading: () => const [
              SliverFillRemaining(child: Center(child: PageLoading())),
            ],
            error: (error, _) => [
              SliverFillRemaining(
                child: PageError(
                  message: error.toString(),
                  onRetry: () => ref.invalidate(mailCredentialsProvider),
                ),
              ),
            ],
            data: (items) {
              if (items.isEmpty) {
                return [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Symbols.key,
                      title: 'noCredentials'.tr(),
                      message: 'noCredentialsDescription'.tr(),
                    ),
                  ),
                ];
              }
              return [
                SliverList.builder(
                  itemCount: items.length * 2 - 1,
                  itemBuilder: (context, index) {
                    if (index.isOdd) return const Divider(height: 1);
                    final credential = items[index ~/ 2];
                    final mailbox = mailboxList
                        .where((m) => m.id == credential.mailboxId)
                        .firstOrNull;
                    return ListTile(
                      shape: const RoundedRectangleBorder(),
                      leading: const Icon(Symbols.key),
                      title: Text(credential.label),
                      subtitle: Text(
                        '${mailbox?.fullAddress(mailHost) ?? credential.mailboxId} • ${credential.protocols.map((p) => p.toUpperCase()).join(', ')}',
                      ),
                      trailing: IconButton(
                        tooltip: 'revoke'.tr(),
                        onPressed: () => _revoke(credential),
                        icon: Icon(Symbols.delete, color: scheme.error),
                      ),
                    );
                  },
                ),
              ];
            },
          ),
        ],
      ),
    );
  }
}

class _CreateCredentialSheet extends ConsumerStatefulWidget {
  const _CreateCredentialSheet();

  @override
  ConsumerState<_CreateCredentialSheet> createState() =>
      _CreateCredentialSheetState();
}

class _CreateCredentialSheetState
    extends ConsumerState<_CreateCredentialSheet> {
  final _labelController = TextEditingController();
  final Set<String> _protocols = {'smtp', 'imap'};
  String? _selectedMailboxId;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      showSnackBar('labelRequired'.tr());
      return;
    }
    final mailboxId = _selectedMailboxId;
    if (mailboxId == null || mailboxId.isEmpty) {
      showSnackBar('mailboxRequired'.tr());
      return;
    }
    try {
      final created = await ref
          .read(wattEngineClientProvider)
          .createMailCredential(
            mailboxId: mailboxId,
            label: label,
            protocols: _protocols.toList(),
          );
      if (mounted) Navigator.of(context).pop(created);
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final mailboxes = ref.watch(mailboxesProvider);
    final mailHost = ref.watch(mailHostProvider).value;
    final scheme = Theme.of(context).colorScheme;

    return SheetScaffold(
      titleText: 'createCredential'.tr(),
      heightFactor: 0.65,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  mailboxes.when(
                    loading: () => const SizedBox(
                      height: 56,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    error: (error, _) => Text(
                      error.toString(),
                      style: TextStyle(color: scheme.error),
                    ),
                    data: (items) {
                      if (items.isEmpty) {
                        return Text(
                          'createMailboxFirst'.tr(),
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        );
                      }
                      _selectedMailboxId ??= items
                          .firstWhere(
                            (mailbox) => mailbox.isDefault,
                            orElse: () => items.first,
                          )
                          .id;
                      return DropdownButtonFormField<String>(
                        initialValue: _selectedMailboxId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: 'mailbox'.tr(),
                          prefixIcon: const Icon(Symbols.mail),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: [
                          for (final mailbox in items)
                            DropdownMenuItem(
                              value: mailbox.id,
                              child: Text(mailbox.fullAddress(mailHost)),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _selectedMailboxId = value),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _labelController,
                    decoration: InputDecoration(
                      labelText: 'credentialLabel'.tr(),
                      hintText: 'credentialLabelHint'.tr(),
                      prefixIcon: const Icon(Symbols.label),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final protocol in ['smtp', 'imap', 'pop3'])
                        FilterChip(
                          label: Text(protocol.toUpperCase()),
                          selected: _protocols.contains(protocol),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _protocols.add(protocol);
                              } else {
                                _protocols.remove(protocol);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed:
                        _protocols.isNotEmpty && _selectedMailboxId != null
                        ? _create
                        : null,
                    icon: const Icon(Symbols.add, size: 18),
                    label: Text('createCredential'.tr()),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
