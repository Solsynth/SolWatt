import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/ui/alert.dart';
import 'package:solwatt/ui/page_scaffold.dart';

@RoutePage()
class MailPage extends ConsumerStatefulWidget {
  const MailPage({super.key});

  @override
  ConsumerState<MailPage> createState() => _MailPageState();
}

class _MailPageState extends ConsumerState<MailPage> {
  String? _selectedMailboxId;
  final _take = 20;
  int _offset = 0;
  final List<MailEmail> _emails = [];
  int _total = 0;
  bool _isLoadingMore = false;

  @override
  Widget build(BuildContext context) {
    final mailboxes = ref.watch(mailboxesProvider);
    final mailHost = ref.watch(mailHostProvider);

    return PageScaffold(
      title: 'mail'.tr(),
      subtitle: 'elecPostalMail'.tr(),
      actions: [
        IconButton.filledTonal(
          tooltip: 'mailCredentials'.tr(),
          onPressed: () => _showCredentials(context),
          icon: const Icon(Symbols.key, size: 20),
        ),
        FilledButton.tonalIcon(
          onPressed: () => _compose(context),
          icon: const Icon(Symbols.edit, size: 18),
          label: Text('compose'.tr()),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: mailboxes.when(
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
                  mailHost: mailHost.value,
                  selectedId: _selectedMailboxId,
                  onSelected: (id) {
                    setState(() {
                      _selectedMailboxId = id;
                      _offset = 0;
                      _emails.clear();
                      _total = 0;
                    });
                    ref.invalidate(emailsProvider);
                  },
                  onCreate: () => _createMailbox(context),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              child: _EmailList(
                mailboxId: _selectedMailboxId,
                mailHost: mailHost.value,
                onOpen: (email) => _openEmail(context, email),
                onRefresh: () => _refreshEmails(ref),
                onLoadMore: () => _loadMoreEmails(ref),
              ),
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
      final page = await ref.read(wattEngineClientProvider).listMailboxEmails(
        _selectedMailboxId ?? '',
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
    if (!email.isRead && email.id.isNotEmpty) {
      _markRead(email.id);
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EmailDetailSheet(
        email: email,
        mailHost: ref.read(mailHostProvider).value,
        onReply: () => _compose(context, replyingTo: email),
        onResend: email.isDraft ? null : () => _resendEmail(email),
        onToggleRead: () => _toggleRead(email),
        onDelete: () => _deleteEmail(email),
      ),
    );
  }

  Future<void> _markRead(String emailId) async {
    try {
      await ref.read(wattEngineClientProvider).markEmailRead(emailId);
      ref.invalidate(emailsProvider);
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  Future<void> _toggleRead(MailEmail email) async {
    try {
      if (email.isRead) {
        await ref.read(wattEngineClientProvider).markEmailUnread(email.id);
      } else {
        await ref.read(wattEngineClientProvider).markEmailRead(email.id);
      }
      ref.invalidate(emailsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  Future<void> _deleteEmail(MailEmail email) async {
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
      if (mounted) Navigator.of(context).pop();
      showSnackBar('emailDeleted'.tr());
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  Future<void> _resendEmail(MailEmail email) async {
    try {
      await ref.read(wattEngineClientProvider).resendEmail(email.id);
      ref.invalidate(emailsProvider);
      if (mounted) Navigator.of(context).pop();
      showSnackBar('emailResent'.tr());
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  Future<void> _compose(BuildContext context, {MailEmail? replyingTo}) async {
    final mailboxes = await ref.read(mailboxesProvider.future);
    if (!mounted) return;
    final mailbox = mailboxes.firstWhere(
      (m) => m.id == _selectedMailboxId,
      orElse: () => mailboxes.firstWhere(
        (m) => m.isDefault,
        orElse: () => mailboxes.first,
      ),
    );
    if (!context.mounted) return;
    if (mailboxes.isEmpty) {
      showSnackBar('createMailboxFirst'.tr());
      return;
    }
    final draft = await showModalBottomSheet<_MailDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ComposeSheet(
        mailbox: mailbox,
        mailboxes: mailboxes,
        mailHost: ref.read(mailHostProvider).value,
        replyingTo: replyingTo,
      ),
    );
    if (draft == null) return;
    try {
      await ref.read(wattEngineClientProvider).sendEmail(
        mailboxId: draft.mailboxId,
        to: draft.to,
        cc: draft.cc,
        bcc: draft.bcc,
        subject: draft.subject,
        body: draft.body,
        isDraft: draft.isDraft,
      );
      ref.invalidate(emailsProvider);
      if (mounted) showSnackBar(draft.isDraft ? 'draftSaved'.tr() : 'emailSent'.tr());
    } catch (error) {
      showSnackBar(error.toString());
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
      await ref.read(wattEngineClientProvider).createMailbox(
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

class _MailboxError extends StatelessWidget {
  const _MailboxError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Symbols.error, color: Theme.of(context).colorScheme.error, size: 20),
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onErrorContainer,
              ),
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

    final selected = mailboxes.where((m) => m.id == selectedId).firstOrNull ??
        mailboxes.firstWhere(
          (m) => m.isDefault,
          orElse: () => mailboxes.first,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final canShowChips = constraints.maxWidth >= 480;
        if (canShowChips) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final mailbox in mailboxes)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(mailbox.fullAddress(mailHost)),
                      selected: mailbox.id == selected.id,
                      onSelected: (_) => onSelected(mailbox.id),
                      avatar: mailbox.isDefault
                          ? const Icon(Symbols.star, size: 16)
                          : null,
                    ),
                  ),
                IconButton.filledTonal(
                  tooltip: 'newMailbox'.tr(),
                  onPressed: onCreate,
                  icon: const Icon(Symbols.add),
                ),
              ],
            ),
          );
        }
        return DropdownButtonFormField<String>(
          initialValue: selected.id,
          decoration: InputDecoration(
            labelText: 'mailbox'.tr(),
            prefixIcon: const Icon(Symbols.mail),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          items: [
              for (final mailbox in mailboxes)
                  DropdownMenuItem(
                    value: mailbox.id,
                    child: Text(mailbox.fullAddress(mailHost)),
                  ),
          ],
          onChanged: (value) => onSelected(value),
        );
      },
    );
  }
}

class _EmailList extends ConsumerWidget {
  const _EmailList({
    required this.mailboxId,
    required this.mailHost,
    required this.onOpen,
    required this.onRefresh,
    required this.onLoadMore,
  });

  final String? mailboxId;
  final String? mailHost;
  final ValueChanged<MailEmail> onOpen;
  final VoidCallback onRefresh;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emails = ref.watch(emailsProvider(mailboxId));

    return emails.when(
      loading: () => const PageLoading(),
      error: (error, _) => PageError(
        message: error.toString(),
        onRetry: onRefresh,
      ),
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
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final email = items[index];
                          return _EmailTile(
                            email: email,
                            mailHost: mailHost,
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
  });

  final MailEmail email;
  final String? mailHost;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fromAddress = email.from?.fullAddress(mailHost) ?? '';
    final fromName = email.from?.displayName ?? '';
    final from = fromName.isNotEmpty ? fromName : fromAddress;
    final date = email.createdAt;

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: email.isRead
            ? scheme.surfaceContainerHighest
            : scheme.primaryContainer,
        foregroundColor: email.isRead
            ? scheme.onSurfaceVariant
            : scheme.onPrimaryContainer,
        child: Icon(
          email.isRead ? Symbols.mail_outline : Symbols.mail,
          size: 18,
          fill: email.isRead ? 0 : 1,
        ),
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
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
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
      'pending' => (StatusChipTone.primary, 'deliveryStatusPending', Symbols.schedule),
      'failed' => (StatusChipTone.error, 'deliveryStatusFailed', Symbols.error),
      'not_configured' => (StatusChipTone.neutral, 'deliveryStatusNotConfigured', Symbols.block),
      _ => (StatusChipTone.neutral, 'deliveryStatusUnknown', Symbols.help),
    };
    return StatusChip(label: labelKey.tr(), icon: icon, tone: tone);
  }
}

class _EmailDetailSheet extends StatelessWidget {
  const _EmailDetailSheet({
    required this.email,
    required this.mailHost,
    required this.onReply,
    required this.onResend,
    required this.onToggleRead,
    required this.onDelete,
  });

  final MailEmail email;
  final String? mailHost;
  final VoidCallback onReply;
  final VoidCallback? onResend;
  final VoidCallback onToggleRead;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SheetScaffold(
      titleText: email.displaySubject,
      heightFactor: 0.85,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _RecipientRow(
                    label: 'from'.tr(),
                    recipient: email.from,
                    mailHost: mailHost,
                  ),
                ),
                IconButton(
                  tooltip: email.isRead ? 'markUnread'.tr() : 'markRead'.tr(),
                  onPressed: onToggleRead,
                  icon: Icon(
                    email.isRead ? Symbols.mail : Symbols.drafts,
                  ),
                ),
                IconButton(
                  tooltip: 'delete'.tr(),
                  onPressed: onDelete,
                  icon: Icon(Symbols.delete, color: scheme.error),
                ),
              ],
            ),
            const Divider(),
            _RecipientRow(label: 'to'.tr(), recipients: email.to, mailHost: mailHost),
            if (email.cc.isNotEmpty)
              _RecipientRow(label: 'cc'.tr(), recipients: email.cc, mailHost: mailHost),
            if (email.bcc.isNotEmpty)
              _RecipientRow(label: 'bcc'.tr(), recipients: email.bcc, mailHost: mailHost),
            const Divider(),
            if (email.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  email.createdAt!.toLocal().toString(),
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            SelectableText(
              email.body.isNotEmpty ? email.body : '(no body)',
              style: text.bodyLarge,
            ),
            if (email.attachments.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'attachments'.tr(),
                style: text.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final attachment in email.attachments)
                    Chip(
                      avatar: const Icon(Symbols.attach_file, size: 18),
                      label: Text(attachment.name),
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
                      'deliveryAttempts'.tr(args: [email.deliveryAttempts.toString()]),
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              if (email.lastDeliveryAttemptAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'lastDeliveryAttempt'.tr(namedArgs: {
                      'date': email.lastDeliveryAttemptAt!.toLocal().toString(),
                    }),
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
              if (email.deliveryStatus?.toLowerCase() == 'failed' && onResend != null) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: onResend,
                  icon: const Icon(Symbols.refresh, size: 18),
                  label: Text('resend'.tr()),
                ),
              ],
            ],
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: onReply,
              icon: const Icon(Symbols.reply, size: 18),
              label: Text('reply'.tr()),
            ),
          ],
        ),
      ),
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
  });

  final String mailboxId;
  final List<MailRecipient> to;
  final List<MailRecipient> cc;
  final List<MailRecipient> bcc;
  final String subject;
  final String body;
  final bool isDraft;
}

class _ComposeSheet extends StatefulWidget {
  const _ComposeSheet({
    required this.mailbox,
    required this.mailboxes,
    this.mailHost,
    this.replyingTo,
  });

  final MailMailbox mailbox;
  final List<MailMailbox> mailboxes;
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

  void _submit({bool draft = false}) {
    final to = _parseRecipients(_toController.text);
    if (to.isEmpty) {
      showSnackBar('recipientsRequired'.tr());
      return;
    }
    Navigator.pop(
      context,
      _MailDraft(
        mailboxId: _mailboxId,
        to: to,
        cc: _parseRecipients(_ccController.text),
        bcc: const [],
        subject: _subjectController.text,
        body: _bodyController.text,
        isDraft: draft,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      titleText: 'compose'.tr(),
      heightFactor: 0.85,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
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
            if (_selectedMailbox?.fullAddress(widget.mailHost).contains('@') != true) ...[
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
            TextField(
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
  ConsumerState<_CreateMailboxSheet> createState() => _CreateMailboxSheetState();
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
                    ? 'mailboxAddressHelperWithHost'.tr(namedArgs: {'host': mailHost!})
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
                  'mailboxAddressPreview'.tr(namedArgs: {'address': fullAddress}),
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
  final _labelController = TextEditingController();
  final Set<String> _protocols = {'smtp', 'imap'};

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
    try {
      final created = await ref.read(wattEngineClientProvider).createMailCredential(
        label: label,
        protocols: _protocols.toList(),
      );
      ref.invalidate(mailCredentialsProvider);
      if (mounted) {
        setState(() => _labelController.clear());
        _showSecret(created);
      }
    } catch (error) {
      showSnackBar(error.toString());
    }
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
      await ref.read(wattEngineClientProvider).revokeMailCredential(credential.id);
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
    final scheme = Theme.of(context).colorScheme;

    return SheetScaffold(
      titleText: 'mailCredentials'.tr(),
      heightFactor: 0.75,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _labelController,
              decoration: InputDecoration(
                labelText: 'credentialLabel'.tr(),
                hintText: 'credentialLabelHint'.tr(),
                prefixIcon: const Icon(Symbols.label),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _protocols.isNotEmpty ? _create : null,
              icon: const Icon(Symbols.add, size: 18),
              label: Text('createCredential'.tr()),
            ),
            const Divider(height: 32),
            Expanded(
              child: credentials.when(
                loading: () => const PageLoading(),
                error: (error, _) => PageError(
                  message: error.toString(),
                  onRetry: () => ref.invalidate(mailCredentialsProvider),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return EmptyState(
                      icon: Symbols.key,
                      title: 'noCredentials'.tr(),
                      message: 'noCredentialsDescription'.tr(),
                    );
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final credential = items[index];
                      return ListTile(
                        leading: const Icon(Symbols.key),
                        title: Text(credential.label),
                        subtitle: Text(
                          credential.protocols.map((p) => p.toUpperCase()).join(', '),
                        ),
                        trailing: IconButton(
                          tooltip: 'revoke'.tr(),
                          onPressed: () => _revoke(credential),
                          icon: Icon(Symbols.delete, color: scheme.error),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
