import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/mail/import/mail_import_models.dart';
import 'package:solwatt/mail/import/mail_import_service.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/tasks/app_task.dart';
import 'package:solwatt/tasks/tasks_notifier.dart';
import 'package:solwatt/ui/alert.dart';
import 'package:solwatt/ui/page_scaffold.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart';

/// Mail settings: notification preferences, app-password credentials for
/// desktop mail clients, per-mailbox settings (storage quota, aliases,
/// forwarding), blocked senders, and the `.eml`/`.mbox` import. Reachable from
/// the mail list header.
@RoutePage()
class MailSettingsPage extends ConsumerWidget {
  const MailSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'mailSettings'.tr(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'close'.tr(),
                onPressed: () => context.router.pop(),
                icon: const Icon(Symbols.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _NotificationSection(),
          const SizedBox(height: 16),
          const _CredentialsSection(),
          const SizedBox(height: 16),
          const _MailboxSection(),
          const SizedBox(height: 16),
          const _BlockedSendersSection(),
          const SizedBox(height: 16),
          const _ImportSection(),
        ],
      ),
    );
  }
}

/// Outlined card chrome shared by every settings section.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: title, trailing: trailing),
            child,
          ],
        ),
      ),
    );
  }
}

/// Reusable mailbox picker for the per-mailbox settings sections.
class _MailboxDropdownField extends StatelessWidget {
  const _MailboxDropdownField({
    required this.mailboxes,
    required this.mailHost,
    required this.value,
    required this.onChanged,
  });

  final List<MailMailbox> mailboxes;
  final String? mailHost;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: 'mailbox'.tr(),
        prefixIcon: const Icon(Symbols.mail),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: [
        for (final mailbox in mailboxes)
          DropdownMenuItem(
            value: mailbox.id,
            child: Text(mailbox.fullAddress(mailHost)),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _CredentialsSection extends ConsumerStatefulWidget {
  const _CredentialsSection();

  @override
  ConsumerState<_CredentialsSection> createState() =>
      _CredentialsSectionState();
}

class _CredentialsSectionState extends ConsumerState<_CredentialsSection> {
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

    return _SettingsCard(
      title: 'mailCredentials'.tr(),
      trailing: IconButton(
        onPressed: _openCreateSheet,
        icon: const Icon(Symbols.add),
        tooltip: 'createCredential'.tr(),
      ),
      child: credentials.when(
        loading: () => const SizedBox(
          height: 64,
          child: Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (error, _) => PageError(
          message: error.toString(),
          onRetry: () => ref.invalidate(mailCredentialsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ListTile(
                leading: const Icon(Symbols.key),
                title: Text('noCredentials'.tr()),
                subtitle: Text('noCredentialsDescription'.tr()),
              ),
            );
          }
          return Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  leading: const Icon(Symbols.key),
                  title: Text(items[i].label),
                  subtitle: Text(
                    '${mailboxList.where((m) => m.id == items[i].mailboxId).firstOrNull?.fullAddress(mailHost) ?? items[i].mailboxId} • ${items[i].protocols.map((p) => p.toUpperCase()).join(', ')}',
                  ),
                  trailing: IconButton(
                    tooltip: 'revoke'.tr(),
                    onPressed: () => _revoke(items[i]),
                    icon: Icon(Symbols.delete, color: scheme.error),
                  ),
                ),
              ],
            ],
          );
        },
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

/// Account-level incoming-mail notification preferences: highlight extraction
/// and AI summaries.
class _NotificationSection extends ConsumerWidget {
  const _NotificationSection();

  Future<void> _set(WidgetRef ref, Map<String, dynamic> patch) async {
    try {
      await ref
          .read(wattEngineClientProvider)
          .updateNotificationSettings(
            highlight: patch['highlight'] as bool?,
            summarize: patch['summarize'] as bool?,
          );
      ref.invalidate(mailNotificationSettingsProvider);
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(mailNotificationSettingsProvider);

    return _SettingsCard(
      title: 'notificationPreferences'.tr(),
      child: settings.when(
        loading: () => const SizedBox(
          height: 64,
          child: Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (error, _) => PageError(
          message: error.toString(),
          onRetry: () => ref.invalidate(mailNotificationSettingsProvider),
        ),
        data: (value) => Column(
          children: [
            SwitchListTile(
              secondary: const Icon(Symbols.enhanced_encryption),
              title: Text('highlightNotifications'.tr()),
              subtitle: Text('highlightNotificationsDescription'.tr()),
              value: value.highlight,
              onChanged: (enabled) => _set(ref, {'highlight': enabled}),
            ),
            SwitchListTile(
              secondary: const Icon(Symbols.auto_awesome),
              title: Text('summarizeMessages'.tr()),
              subtitle: Text('summarizeMessagesDescription'.tr()),
              value: value.summarize,
              onChanged: (enabled) => _set(ref, {'summarize': enabled}),
            ),
          ],
        ),
      ),
    );
  }
}

/// Per-mailbox settings: storage quota, alias addresses, and alias forwarding.
class _MailboxSection extends ConsumerStatefulWidget {
  const _MailboxSection();

  @override
  ConsumerState<_MailboxSection> createState() => _MailboxSectionState();
}

class _MailboxSectionState extends ConsumerState<_MailboxSection> {
  String? _selectedMailboxId;

  String? _resolvedMailboxId(List<MailMailbox> mailboxes, String? selectedId) {
    if (mailboxes.isEmpty) return null;
    _selectedMailboxId ??= mailboxes.any((m) => m.id == selectedId)
        ? selectedId
        : mailboxes
              .firstWhere(
                (mailbox) => mailbox.isDefault,
                orElse: () => mailboxes.first,
              )
              .id;
    return _selectedMailboxId;
  }

  Future<void> _createAlias(String mailboxId) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreateAliasSheet(mailboxId: mailboxId),
    );
    if (created == true && mounted) {
      ref.invalidate(mailboxAliasesProvider(mailboxId));
      showSnackBar('aliasCreated'.tr());
    }
  }

  Future<void> _removeAlias(MailAlias alias, String mailboxId) async {
    final confirmed = await showConfirmAlert(
      'removeAliasConfirm'.tr(namedArgs: {'address': alias.address}),
      'removeAlias'.tr(),
      icon: Symbols.alternate_email,
      isDanger: true,
      confirmLabel: 'remove'.tr(),
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(wattEngineClientProvider)
          .deleteMailboxAlias(mailboxId, alias.id);
      ref.invalidate(mailboxAliasesProvider(mailboxId));
      ref.invalidate(mailboxForwardingsProvider(mailboxId));
      if (mounted) showSnackBar('aliasRemoved'.tr());
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  Future<void> _createForwarding(String mailboxId) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreateForwardingSheet(mailboxId: mailboxId),
    );
    if (created == true && mounted) {
      ref.invalidate(mailboxForwardingsProvider(mailboxId));
      showSnackBar('forwardingCreated'.tr());
    }
  }

  Future<void> _removeForwarding(
    MailForwarding forwarding,
    String mailboxId,
  ) async {
    final confirmed = await showConfirmAlert(
      'removeForwardingConfirm'.tr(
        namedArgs: {'destination': forwarding.destination},
      ),
      'removeForwarding'.tr(),
      icon: Symbols.forward_to_inbox,
      isDanger: true,
      confirmLabel: 'remove'.tr(),
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(wattEngineClientProvider)
          .deleteMailForwarding(mailboxId, forwarding.id);
      ref.invalidate(mailboxForwardingsProvider(mailboxId));
      if (mounted) showSnackBar('forwardingRemoved'.tr());
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mailboxesAsync = ref.watch(mailboxesProvider);
    final mailHost = ref.watch(mailHostProvider).value;
    final selectedId = ref.read(selectedMailboxIdProvider);

    return _SettingsCard(
      title: 'mailboxSettings'.tr(),
      child: mailboxesAsync.when(
        loading: () => const SizedBox(
          height: 56,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (error, _) => PageError(
          message: error.toString(),
          onRetry: () => ref.invalidate(mailboxesProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'createMailboxFirst'.tr(),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            );
          }
          final mailboxId = _resolvedMailboxId(items, selectedId);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: .symmetric(horizontal: 16),
                child: _MailboxDropdownField(
                  mailboxes: items,
                  mailHost: mailHost,
                  value: _selectedMailboxId,
                  onChanged: (value) =>
                      setState(() => _selectedMailboxId = value),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: .symmetric(horizontal: 16),

                child: _QuotaTile(mailboxId: mailboxId!),
              ),
              const Divider(height: 24),
              _AliasesBlock(
                mailboxId: mailboxId,
                mailHost: mailHost,
                onCreate: () => _createAlias(mailboxId),
                onRemove: (alias) => _removeAlias(alias, mailboxId),
              ),
              const Divider(height: 24),
              _ForwardingBlock(
                mailboxId: mailboxId,
                onCreate: () => _createForwarding(mailboxId),
                onRemove: (forwarding) =>
                    _removeForwarding(forwarding, mailboxId),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Storage usage of the mailbox's workspace, from `GET /postal/mailboxes/{id}/quota`.
class _QuotaTile extends ConsumerWidget {
  const _QuotaTile({required this.mailboxId});

  final String mailboxId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final quota = ref.watch(mailboxQuotaProvider(mailboxId));

    return quota.when(
      loading: () => const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (error, _) => Text(
        error.toString(),
        style: TextStyle(color: scheme.error, fontSize: 13),
      ),
      data: (value) {
        if (value.limitBytes <= 0) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Symbols.storage),
            title: Text('mailStorageQuota'.tr()),
            subtitle: Text('mailStorageQuotaUnlimited'.tr()),
          );
        }
        final ratio = value.limitBytes <= 0
            ? 0.0
            : (value.usedBytes / value.limitBytes).clamp(0.0, 1.0).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Symbols.storage, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'mailStorageQuota'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Text(
                  '${formatFileSize(value.usedBytes)} / ${formatFileSize(value.limitBytes)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Alias addresses of one mailbox.
class _AliasesBlock extends ConsumerWidget {
  const _AliasesBlock({
    required this.mailboxId,
    required this.mailHost,
    required this.onCreate,
    required this.onRemove,
  });

  final String mailboxId;
  final String? mailHost;
  final VoidCallback onCreate;
  final ValueChanged<MailAlias> onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final aliases = ref.watch(mailboxAliasesProvider(mailboxId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'aliases'.tr(),
          trailing: IconButton(
            onPressed: onCreate,
            icon: const Icon(Symbols.add),
            tooltip: 'addAlias'.tr(),
          ),
        ),
              Padding(
                padding: .symmetric(horizontal: 16),
        child: aliases.when(
          loading: () => const SizedBox(
            height: 40,
            child: Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (error, _) => Text(
            error.toString(),
            style: TextStyle(color: scheme.error, fontSize: 13),
          ),
          data: (items) {
            if (items.isEmpty) {
              return Text(
                'noAliases'.tr(),
                style: TextStyle(color: scheme.onSurfaceVariant),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Symbols.alternate_email, size: 20),
                    title: Text(items[i].address),
                    subtitle: items[i].name?.isNotEmpty == true
                        ? Text(items[i].name!)
                        : null,
                    trailing: IconButton(
                      tooltip: 'remove'.tr(),
                      onPressed: () => onRemove(items[i]),
                      icon: Icon(Symbols.delete, color: scheme.error, size: 20),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
              ), 
      ],
    );
  }
}

/// Alias forwarding rules of one mailbox.
class _ForwardingBlock extends ConsumerWidget {
  const _ForwardingBlock({
    required this.mailboxId,
    required this.onCreate,
    required this.onRemove,
  });

  final String mailboxId;
  final VoidCallback onCreate;
  final ValueChanged<MailForwarding> onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final forwardings = ref.watch(mailboxForwardingsProvider(mailboxId));
    final aliases = ref
        .watch(mailboxAliasesProvider(mailboxId))
        .maybeWhen(data: (data) => data, orElse: () => const <MailAlias>[]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'forwarding'.tr(),
          trailing: IconButton(
            onPressed: onCreate,
            icon: const Icon(Symbols.add),
            tooltip: 'addForwarding'.tr(),
          ),
        ),
              Padding(
                padding: .symmetric(horizontal: 16),
        child: forwardings.when(
          loading: () => const SizedBox(
            height: 40,
            child: Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (error, _) => Text(
            error.toString(),
            style: TextStyle(color: scheme.error, fontSize: 13),
          ),
          data: (items) {
            if (items.isEmpty) {
              return Text(
                'noForwarding'.tr(),
                style: TextStyle(color: scheme.onSurfaceVariant),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Symbols.forward_to_inbox, size: 20),
                    title: Text(items[i].destination),
                    subtitle: Text(
                      aliases
                              .where((a) => a.id == items[i].aliasId)
                              .firstOrNull
                              ?.address ??
                          'alias'.tr(),
                    ),
                    trailing: IconButton(
                      tooltip: 'remove'.tr(),
                      onPressed: () => onRemove(items[i]),
                      icon: Icon(Symbols.delete, color: scheme.error, size: 20),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
              ),
      ],
    );
  }
}

/// Sheet creating an alias on a verified workspace custom domain.
class _CreateAliasSheet extends ConsumerStatefulWidget {
  const _CreateAliasSheet({required this.mailboxId});

  final String mailboxId;

  @override
  ConsumerState<_CreateAliasSheet> createState() => _CreateAliasSheetState();
}

class _CreateAliasSheetState extends ConsumerState<_CreateAliasSheet> {
  final _localPartController = TextEditingController();
  final _nameController = TextEditingController();
  String? _customDomainId;

  @override
  void dispose() {
    _localPartController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final localPart = _localPartController.text.trim().toLowerCase();
    if (localPart.isEmpty) {
      showSnackBar('localPartRequired'.tr());
      return;
    }
    final customDomainId = _customDomainId;
    if (customDomainId == null || customDomainId.isEmpty) {
      showSnackBar('customDomainRequired'.tr());
      return;
    }
    try {
      await ref
          .read(wattEngineClientProvider)
          .createMailboxAlias(
            mailboxId: widget.mailboxId,
            customDomainId: customDomainId,
            localPart: localPart,
            name: _nameController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final workspaceId = ref.read(selectedWorkspaceProvider).value?.id;
    final customDomains = workspaceId == null || workspaceId.isEmpty
        ? const AsyncValue<List<MailCustomDomain>>.data([])
        : ref.watch(customDomainsProvider(workspaceId));
    final verifiedDomains = customDomains.maybeWhen(
      data: (data) => data.where((d) => d.verifiedForSending).toList(),
      orElse: () => const <MailCustomDomain>[],
    );

    return SheetScaffold(
      titleText: 'addAlias'.tr(),
      heightFactor: 0.6,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  customDomains.when(
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
                      if (verifiedDomains.isEmpty) {
                        return Text(
                          'noVerifiedDomains'.tr(),
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        );
                      }
                      _customDomainId ??= verifiedDomains.first.id;
                      return DropdownButtonFormField<String>(
                        initialValue: _customDomainId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: 'customDomain'.tr(),
                          prefixIcon: const Icon(Symbols.language),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: [
                          for (final domain in verifiedDomains)
                            DropdownMenuItem(
                              value: domain.id,
                              child: Text(domain.domain),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _customDomainId = value),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _localPartController,
                    decoration: InputDecoration(
                      labelText: 'aliasLocalPart'.tr(),
                      hintText: 'aliasLocalPartHint'.tr(),
                      prefixIcon: const Icon(Symbols.alternate_email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'name'.tr(),
                      prefixIcon: const Icon(Symbols.label),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: verifiedDomains.isEmpty ? null : _create,
                    icon: const Icon(Symbols.add, size: 18),
                    label: Text('addAlias'.tr()),
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

/// Sheet creating an alias forwarding rule to an external address.
class _CreateForwardingSheet extends ConsumerStatefulWidget {
  const _CreateForwardingSheet({required this.mailboxId});

  final String mailboxId;

  @override
  ConsumerState<_CreateForwardingSheet> createState() =>
      _CreateForwardingSheetState();
}

class _CreateForwardingSheetState
    extends ConsumerState<_CreateForwardingSheet> {
  final _destinationController = TextEditingController();
  String? _aliasId;

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final destination = _destinationController.text.trim().toLowerCase();
    if (destination.isEmpty) {
      showSnackBar('destinationRequired'.tr());
      return;
    }
    final aliasId = _aliasId;
    if (aliasId == null || aliasId.isEmpty) {
      showSnackBar('aliasRequired'.tr());
      return;
    }
    try {
      await ref
          .read(wattEngineClientProvider)
          .createMailForwarding(
            mailboxId: widget.mailboxId,
            aliasId: aliasId,
            destination: destination,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final aliases = ref.watch(mailboxAliasesProvider(widget.mailboxId));

    return SheetScaffold(
      titleText: 'addForwarding'.tr(),
      heightFactor: 0.55,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  aliases.when(
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
                          'noAliases'.tr(),
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        );
                      }
                      _aliasId ??= items.first.id;
                      return DropdownButtonFormField<String>(
                        initialValue: _aliasId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: 'alias'.tr(),
                          prefixIcon: const Icon(Symbols.alternate_email),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: [
                          for (final alias in items)
                            DropdownMenuItem(
                              value: alias.id,
                              child: Text(alias.address),
                            ),
                        ],
                        onChanged: (value) => setState(() => _aliasId = value),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _destinationController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'forwardTo'.tr(),
                      hintText: 'forwardToHint'.tr(),
                      prefixIcon: const Icon(Symbols.forward_to_inbox),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Symbols.add, size: 18),
                    label: Text('addForwarding'.tr()),
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

/// Sender/domain block rules for the account, scoped to a mailbox or workspace.
class _BlockedSendersSection extends ConsumerStatefulWidget {
  const _BlockedSendersSection();

  @override
  ConsumerState<_BlockedSendersSection> createState() =>
      _BlockedSendersSectionState();
}

class _BlockedSendersSectionState
    extends ConsumerState<_BlockedSendersSection> {
  Future<void> _add() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateBlockRuleSheet(),
    );
    if (created == true && mounted) {
      ref.invalidate(mailBlockRulesProvider);
      showSnackBar('blockRuleCreated'.tr());
    }
  }

  Future<void> _remove(MailBlockRule rule) async {
    final confirmed = await showConfirmAlert(
      'removeBlockRuleConfirm'.tr(namedArgs: {'pattern': rule.pattern}),
      'removeBlockRule'.tr(),
      icon: Symbols.block,
      isDanger: true,
      confirmLabel: 'remove'.tr(),
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(wattEngineClientProvider).deleteBlockRule(rule.id);
      ref.invalidate(mailBlockRulesProvider);
      if (mounted) showSnackBar('blockRuleRemoved'.tr());
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rules = ref.watch(mailBlockRulesProvider);
    final mailboxes = ref
        .watch(mailboxesProvider)
        .maybeWhen(data: (data) => data, orElse: () => const <MailMailbox>[]);
    final mailHost = ref.watch(mailHostProvider).value;
    final workspace = ref.watch(selectedWorkspaceProvider).value;

    return _SettingsCard(
      title: 'blockedSenders'.tr(),
      trailing: IconButton(
        onPressed: _add,
        icon: const Icon(Symbols.add),
        tooltip: 'addBlockRule'.tr(),
      ),
      child: rules.when(
        loading: () => const SizedBox(
          height: 64,
          child: Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (error, _) => PageError(
          message: error.toString(),
          onRetry: () => ref.invalidate(mailBlockRulesProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Text(
                'noBlockRules'.tr(),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            );
          }
          return Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    items[i].matchType == 'domain'
                        ? Symbols.domain
                        : Symbols.block,
                    size: 20,
                  ),
                  title: Text(items[i].pattern),
                  subtitle: Text(
                    items[i].mailboxId != null
                        ? '${'blockScopeMailbox'.tr()}: ${mailboxes.where((m) => m.id == items[i].mailboxId).firstOrNull?.fullAddress(mailHost) ?? items[i].mailboxId}'
                        : items[i].workspaceId != null
                        ? '${'blockScopeWorkspace'.tr()}: ${workspace?.name ?? items[i].workspaceId}'
                        : items[i].matchType,
                  ),
                  trailing: IconButton(
                    tooltip: 'remove'.tr(),
                    onPressed: () => _remove(items[i]),
                    icon: Icon(Symbols.delete, color: scheme.error, size: 20),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Sheet adding a block rule for a sender/domain, scoped to a mailbox or the
/// whole workspace.
class _CreateBlockRuleSheet extends ConsumerStatefulWidget {
  const _CreateBlockRuleSheet();

  @override
  ConsumerState<_CreateBlockRuleSheet> createState() =>
      _CreateBlockRuleSheetState();
}

class _CreateBlockRuleSheetState extends ConsumerState<_CreateBlockRuleSheet> {
  final _patternController = TextEditingController();
  String _scope = 'mailbox';
  String? _mailboxId;

  @override
  void dispose() {
    _patternController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final pattern = _patternController.text.trim().toLowerCase();
    if (pattern.isEmpty) {
      showSnackBar('patternRequired'.tr());
      return;
    }
    final workspaceId = ref.read(selectedWorkspaceProvider).value?.id;
    try {
      await ref
          .read(wattEngineClientProvider)
          .createBlockRule(
            scope: _scope,
            workspaceId: _scope == 'workspace' ? workspaceId : null,
            mailboxId: _scope == 'mailbox' ? _mailboxId : null,
            pattern: pattern,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      showSnackBar(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mailboxes = ref.watch(mailboxesProvider);
    final mailHost = ref.watch(mailHostProvider).value;

    return SheetScaffold(
      titleText: 'addBlockRule'.tr(),
      heightFactor: 0.6,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'mailbox',
                        label: Text('blockScopeMailbox'.tr()),
                        icon: const Icon(Symbols.mail),
                      ),
                      ButtonSegment(
                        value: 'workspace',
                        label: Text('blockScopeWorkspace'.tr()),
                        icon: const Icon(Symbols.apartment),
                      ),
                    ],
                    selected: {_scope},
                    onSelectionChanged: (selection) =>
                        setState(() => _scope = selection.first),
                  ),
                  const SizedBox(height: 16),
                  if (_scope == 'mailbox') ...[
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
                        _mailboxId ??= items
                            .firstWhere(
                              (mailbox) => mailbox.isDefault,
                              orElse: () => items.first,
                            )
                            .id;
                        return _MailboxDropdownField(
                          mailboxes: items,
                          mailHost: mailHost,
                          value: _mailboxId,
                          onChanged: (value) =>
                              setState(() => _mailboxId = value),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _patternController,
                    decoration: InputDecoration(
                      labelText: 'blockPattern'.tr(),
                      hintText: 'blockPatternHint'.tr(),
                      prefixIcon: const Icon(Symbols.block),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Symbols.add, size: 18),
                    label: Text('addBlockRule'.tr()),
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

class _ImportSection extends ConsumerStatefulWidget {
  const _ImportSection();

  @override
  ConsumerState<_ImportSection> createState() => _ImportSectionState();
}

class _ImportSectionState extends ConsumerState<_ImportSection> {
  String? _selectedMailboxId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mailboxes = ref.watch(mailboxesProvider);
    final mailHost = ref.watch(mailHostProvider).value;
    final selectedId = ref.read(selectedMailboxIdProvider);

    return _SettingsCard(
      title: 'importEmails'.tr(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4, left: 16, right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Symbols.upload_file, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'importEmailsDescription'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            mailboxes.when(
              loading: () => const SizedBox(
                height: 56,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (error, _) =>
                  Text(error.toString(), style: TextStyle(color: scheme.error)),
              data: (items) {
                if (items.isEmpty) {
                  return Text(
                    'createMailboxFirst'.tr(),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  );
                }
                _selectedMailboxId ??=
                    items.any((mailbox) => mailbox.id == selectedId)
                    ? selectedId
                    : items
                          .firstWhere(
                            (mailbox) => mailbox.isDefault,
                            orElse: () => items.first,
                          )
                          .id;
                return _MailboxDropdownField(
                  mailboxes: items,
                  mailHost: mailHost,
                  value: _selectedMailboxId,
                  onChanged: (value) =>
                      setState(() => _selectedMailboxId = value),
                );
              },
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _selectedMailboxId == null
                  ? null
                  : () => importEmailsAction(
                      context,
                      ref,
                      mailboxId: _selectedMailboxId!,
                    ),
              icon: const Icon(Symbols.upload_file, size: 18),
              label: Text('importEmails'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Imports `.eml`/`.mbox` files into the given mailbox's INBOX.
///
/// Picks files with the OS dialog, parses them via [MailImportService], then
/// shows a preview of how many emails were found before posting the messages
/// in ≤500-item chunks. Runs as a background [AppTask] so large archives keep
/// the UI responsive; attachments upload to workspace Drive. The folder is not
/// switched — the snackbar confirms the result.
Future<void> importEmailsAction(
  BuildContext context,
  WidgetRef ref, {
  required String mailboxId,
}) async {
  final workspaceId = ref.read(selectedWorkspaceProvider).value?.id;
  if (workspaceId == null || workspaceId.isEmpty) {
    showSnackBar('selectAWorkspaceFirst'.tr());
    return;
  }

  final List<PlatformFile> selected;
  try {
    selected = await FilePicker.pickFiles(
      dialogTitle: 'importEmails'.tr(),
      type: FileType.custom,
      allowedExtensions: const ['eml', 'mbox'],
    );
  } catch (error) {
    showSnackBar('Could not open the file picker: $error');
    return;
  }
  if (selected.isEmpty || !context.mounted) return;

  final tasks = ref.read(appTasksProvider.notifier);
  final taskId = tasks.addTask(
    title: 'importEmails'.tr(),
    type: AppTaskType.mailImport,
    status: AppTaskStatus.inProgress,
    metadata: {'mailboxId': mailboxId, 'workspaceId': workspaceId},
  );

  try {
    final service = ref.read(mailImportServiceProvider);
    // Parse off the main isolate: huge .mbox archives would otherwise freeze
    // the UI while decoding. Desktop files are read inside the isolate (by
    // path) so their raw bytes never land on the main isolate; web picks
    // arrive as bytes and `compute` runs the parse inline there.
    final inputs = <ImportParseInput>[];
    for (final file in selected) {
      final bytes = file.path == null ? await file.readAsBytes() : null;
      inputs.add(
        ImportParseInput(path: file.path, bytes: bytes, name: file.name),
      );
    }
    final outputs = await compute(parseImportFiles, inputs);
    final messages = <ParsedMailMessage>[];
    final perFileCounts = <String, int>{};
    String? firstError;
    for (final output in outputs) {
      perFileCounts[output.name] = output.messages.length;
      messages.addAll(output.messages);
      firstError ??= output.error;
    }
    if (firstError != null) {
      throw MailImportException(firstError);
    }

    // Preview before making any requests; cancelling drops the task.
    if (messages.isEmpty) {
      tasks.removeTask(taskId);
      if (!context.mounted) return;
      showSnackBar('importPreviewEmpty'.tr());
      return;
    }
    final mailboxName =
        ref
            .read(mailboxesProvider)
            .value
            ?.where((mailbox) => mailbox.id == mailboxId)
            .firstOrNull
            ?.displayName ??
        mailboxId;
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ImportPreviewDialog(
        total: messages.length,
        perFileCounts: perFileCounts,
        mailboxName: mailboxName,
      ),
    );
    if (confirmed != true) {
      tasks.removeTask(taskId);
      return;
    }
    if (!context.mounted) return;

    final result = await service.import(
      messages: messages,
      mailboxId: mailboxId,
      workspaceId: workspaceId,
      onProgress: (progress) {
        tasks.updateTask(
          taskId,
          progress: progress.total == 0
              ? 1
              : progress.processed / progress.total,
          statusMessage: 'importEmailsProgress'.tr(
            namedArgs: {
              'processed': '${progress.processed}',
              'total': '${progress.total}',
            },
          ),
          metadata: {
            'mailboxId': mailboxId,
            'workspaceId': workspaceId,
            'processed': progress.processed,
            'total': progress.total,
            'imported': progress.imported,
            'duplicates': progress.duplicates,
            'failed': progress.failed,
          },
        );
      },
    );

    tasks.updateTask(
      taskId,
      status: AppTaskStatus.completed,
      progress: 1,
      statusMessage: 'importEmailsDone'.tr(),
      result: {
        'imported': result.imported,
        'duplicates': result.duplicates,
        'failed': result.failed,
      },
    );
    invalidateMailSurfaces(ref);
    if (!context.mounted) return;
    showSnackBar(
      'importEmailsResult'.tr(
        namedArgs: {
          'imported': '${result.imported}',
          'duplicates': '${result.duplicates}',
          'failed': '${result.failed}',
        },
      ),
    );
  } on MailImportException catch (error) {
    tasks.updateTask(
      taskId,
      status: AppTaskStatus.failed,
      statusMessage: 'Failed',
      errorMessage: error.message,
    );
    if (!context.mounted) return;
    showSnackBar(error.message);
  } catch (error) {
    tasks.updateTask(
      taskId,
      status: AppTaskStatus.failed,
      statusMessage: 'Failed',
      errorMessage: error.toString(),
    );
    if (!context.mounted) return;
    showSnackBar(error.toString());
  }
}

/// Confirmation dialog shown before any import request is made: how many
/// emails were parsed, broken down per selected file.
class _ImportPreviewDialog extends StatelessWidget {
  const _ImportPreviewDialog({
    required this.total,
    required this.perFileCounts,
    required this.mailboxName,
  });

  final int total;
  final Map<String, int> perFileCounts;
  final String mailboxName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = perFileCounts.entries.toList();

    return AlertDialog(
      scrollable: true,
      title: Text('importPreviewTitle'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'importPreviewSummary'.plural(
              total,
              namedArgs: {'mailbox': mailboxName},
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          for (final entry in entries)
            Padding(
              padding: EdgeInsets.only(bottom: entry != entries.last ? 6 : 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'importPreviewFileCount'.plural(entry.value),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('importConfirm'.tr()),
        ),
      ],
    );
  }
}
