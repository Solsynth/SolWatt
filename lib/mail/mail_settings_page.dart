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

/// Mail settings: app-password credentials for desktop mail clients plus the
/// `.eml`/`.mbox` import. Reachable from the mail list header.
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
          const SizedBox(height: 8),
          const _CredentialsSection(),
          const SizedBox(height: 24),
          const _ImportSection(),
        ],
      ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'mailCredentials'.tr(),
          trailing: IconButton(
            onPressed: _openCreateSheet,
            icon: const Icon(Symbols.add),
            tooltip: 'createCredential'.tr(),
          ),
        ),
        credentials.when(
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
      ],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: 'importEmails'.tr()),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                    _selectedMailboxId ??=
                        items.any((mailbox) => mailbox.id == selectedId)
                        ? selectedId
                        : items
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
        ),
      ],
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
    ref.invalidate(emailsProvider);
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
