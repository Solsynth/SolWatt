import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/ui/alert.dart';
import 'package:solwatt/ui/page_scaffold.dart';

/// Opens the GitHub App integration sheet for a board.
///
/// Flow (see WattEngine `docs/GITHUB_APP_TASK_SYNC.md`):
/// install app → poll installation → pick repositories → link / manage.
Future<void> showGitHubIntegrationSheet(
  BuildContext context,
  WidgetRef ref, {
  required String broadId,
  required String broadName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _GitHubIntegrationSheet(broadId: broadId, broadName: broadName),
  );
}

enum _GitHubStep { status, install, pickRepo }

class _GitHubIntegrationSheet extends ConsumerStatefulWidget {
  const _GitHubIntegrationSheet({
    required this.broadId,
    required this.broadName,
  });

  final String broadId;
  final String broadName;

  @override
  ConsumerState<_GitHubIntegrationSheet> createState() =>
      _GitHubIntegrationSheetState();
}

class _GitHubIntegrationSheetState
    extends ConsumerState<_GitHubIntegrationSheet> {
  var _step = _GitHubStep.status;
  var _busy = false;
  String? _error;
  int? _installationId;
  List<GitHubRepository> _repos = const [];
  Timer? _pollTimer;
  var _polling = false;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _polling = false;
  }

  Future<void> _startConnect() async {
    setState(() {
      _busy = true;
      _error = null;
      _step = _GitHubStep.install;
      _installationId = null;
      _repos = const [];
    });
    try {
      final existingInstallation = await ref
          .read(wattEngineClientProvider)
          .getGitHubInstallation(widget.broadId);
      if (existingInstallation != null) {
        _installationId = existingInstallation;
        await _loadRepos(existingInstallation);
        return;
      }
      final url = await ref
          .read(wattEngineClientProvider)
          .createGitHubInstallUrl(widget.broadId);
      final uri = Uri.tryParse(url);
      if (uri == null) {
        throw const OAuthException('Invalid GitHub install URL.');
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        throw const OAuthException('Could not open GitHub in the browser.');
      }
      if (!mounted) return;
      setState(() => _busy = false);
      _beginPoll();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = wattApiErrorMessage(error);
        _step = _GitHubStep.status;
      });
    }
  }

  void _beginPoll() {
    _stopPolling();
    _polling = true;
    _pollOnce();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    if (!_polling || !mounted) return;
    try {
      final id = await ref
          .read(wattEngineClientProvider)
          .getGitHubInstallation(widget.broadId);
      if (id == null || !mounted) return;
      _stopPolling();
      setState(() {
        _installationId = id;
        _busy = true;
        _error = null;
      });
      await _loadRepos(id);
    } catch (error) {
      if (!mounted) return;
      // Keep polling on transient errors; surface message without aborting.
      setState(() => _error = wattApiErrorMessage(error));
    }
  }

  Future<void> _loadRepos(int installationId) async {
    try {
      final repos = await ref
          .read(wattEngineClientProvider)
          .listGitHubRepositories(widget.broadId, installationId);
      if (!mounted) return;
      setState(() {
        _repos = repos;
        _step = _GitHubStep.pickRepo;
        _busy = false;
        _error = repos.isEmpty
            ? 'No repositories were granted to the app. '
                  'Install again and select at least one repository.'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = wattApiErrorMessage(error);
        _step = _GitHubStep.install;
      });
    }
  }

  Future<void> _link(GitHubRepository repo) async {
    final installationId = _installationId;
    if (installationId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(wattEngineClientProvider)
          .linkGitHubRepository(
            broadId: widget.broadId,
            installationId: installationId,
            owner: repo.owner,
            repository: repo.name,
          );
      ref.invalidate(gitHubIntegrationProvider(widget.broadId));
      ref.invalidate(tasksProvider(widget.broadId));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _GitHubStep.status;
      });
      showSnackBar('Linked ${repo.fullName}. Issues are importing as tasks.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = wattApiErrorMessage(error);
      });
    }
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(wattEngineClientProvider)
          .syncGitHubIntegration(widget.broadId);
      ref.invalidate(gitHubIntegrationProvider(widget.broadId));
      ref.invalidate(tasksProvider(widget.broadId));
      if (!mounted) return;
      setState(() => _busy = false);
      showSnackBar('GitHub sync queued. It will continue in the background.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = wattApiErrorMessage(error);
      });
    }
  }

  Future<void> _unlink(GitHubIntegration integration) async {
    final confirmed = await showConfirmAlert(
      'Tasks stay on the board. GitHub issues, comments, and the app '
          'installation are not deleted. Sync will stop for '
          '${integration.fullName}.',
      'Unlink GitHub?',
      icon: Symbols.link_off,
      isDanger: true,
      confirmLabel: 'Unlink',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(wattEngineClientProvider)
          .unlinkGitHubIntegration(integration.id);
      ref.invalidate(gitHubIntegrationProvider(widget.broadId));
      if (!mounted) return;
      setState(() => _busy = false);
      showSnackBar('GitHub unlinked.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = wattApiErrorMessage(error);
      });
    }
  }

  Future<void> _openRepo(GitHubIntegration integration) async {
    final uri = Uri.parse(
      'https://github.com/${integration.owner}/${integration.repository}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      showSnackBar('Could not open GitHub.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final integration = ref.watch(gitHubIntegrationProvider(widget.broadId));

    return SheetScaffold(
      titleText: 'GitHub',
      heightFactor: 0.78,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Link repositories to “${widget.broadName}”. Issues become '
              'tasks; title, body, labels, open/closed state, and comments '
              'sync both ways.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Material(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Symbols.error,
                        color: scheme.onErrorContainer,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            Expanded(child: _buildBody(integration, scheme, text)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    AsyncValue<List<GitHubIntegration>> integration,
    ColorScheme scheme,
    TextTheme text,
  ) {
    if (_step == _GitHubStep.install) {
      return _InstallWaiting(
        polling: _polling,
        busy: _busy,
        onCancel: () {
          _stopPolling();
          setState(() {
            _step = _GitHubStep.status;
            _error = null;
          });
        },
        onRetryOpen: _busy ? null : _startConnect,
        onCheckNow: _polling && !_busy ? _pollOnce : null,
      );
    }

    if (_step == _GitHubStep.pickRepo) {
      return _RepoPicker(
        repos: _repos,
        busy: _busy,
        onSelect: _busy ? null : _link,
        onBack: _busy
            ? null
            : () {
                _stopPolling();
                setState(() {
                  _step = _GitHubStep.status;
                  _error = null;
                });
              },
      );
    }

    return integration.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => EmptyState(
        icon: Symbols.error,
        title: 'Could not load GitHub status',
        message: wattApiErrorMessage(error),
        action: FilledButton(
          onPressed: () =>
              ref.invalidate(gitHubIntegrationProvider(widget.broadId)),
          child: const Text('Try again'),
        ),
      ),
      data: (linked) {
        if (linked.isEmpty) {
          return EmptyState(
            icon: Symbols.hub,
            title: 'Not connected',
            message:
                'Install the WattEngine GitHub App, then choose repositories '
                'to sync with this board.',
            action: FilledButton.icon(
              onPressed: _busy ? null : _startConnect,
              icon: const Icon(Symbols.link),
              label: const Text('Connect GitHub'),
            ),
          );
        }
        return _LinkedStatus(
          integrations: linked,
          busy: _busy,
          onOpen: _openRepo,
          onSync: _busy ? null : _sync,
          onUnlink: _busy ? null : _unlink,
          onConnectAnother: _busy ? null : _startConnect,
        );
      },
    );
  }
}

class _InstallWaiting extends StatelessWidget {
  const _InstallWaiting({
    required this.polling,
    required this.busy,
    required this.onCancel,
    required this.onRetryOpen,
    required this.onCheckNow,
  });

  final bool polling;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback? onRetryOpen;
  final VoidCallback? onCheckNow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Symbols.open_in_browser, size: 40, color: scheme.primary),
        const SizedBox(height: 12),
        Text(
          'Complete installation in GitHub',
          textAlign: TextAlign.center,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          polling
              ? 'Waiting for GitHub to finish… return here after you approve '
                    'the app and grant repository access. Organization policy '
                    'may require owner approval.'
              : 'Open the install page, grant repository access, then return '
                    'to SolWatt.',
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const Spacer(),
        if (onCheckNow != null)
          OutlinedButton(onPressed: onCheckNow, child: const Text('Check now')),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: onRetryOpen,
          child: const Text('Open install page again'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: busy ? null : onCancel,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _RepoPicker extends StatelessWidget {
  const _RepoPicker({
    required this.repos,
    required this.busy,
    required this.onSelect,
    required this.onBack,
  });

  final List<GitHubRepository> repos;
  final bool busy;
  final ValueChanged<GitHubRepository>? onSelect;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose a repository to link. You can add more repositories afterward.',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: repos.isEmpty
              ? const EmptyState(
                  icon: Symbols.folder_off,
                  title: 'No repositories',
                  message:
                      'Grant the app access to at least one repository, then try again.',
                )
              : ListView.separated(
                  itemCount: repos.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final repo = repos[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Symbols.book_2, color: scheme.primary),
                      title: Text(repo.fullName),
                      subtitle: repo.htmlUrl == null
                          ? null
                          : Text(
                              repo.htmlUrl!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: const Icon(Symbols.chevron_right),
                      enabled: !busy && onSelect != null,
                      onTap: onSelect == null ? null : () => onSelect!(repo),
                    );
                  },
                ),
        ),
        TextButton(onPressed: onBack, child: const Text('Back')),
      ],
    );
  }
}

class _LinkedStatus extends StatelessWidget {
  const _LinkedStatus({
    required this.integrations,
    required this.busy,
    required this.onOpen,
    required this.onSync,
    required this.onUnlink,
    required this.onConnectAnother,
  });

  final List<GitHubIntegration> integrations;
  final bool busy;
  final ValueChanged<GitHubIntegration> onOpen;
  final VoidCallback? onSync;
  final ValueChanged<GitHubIntegration>? onUnlink;
  final VoidCallback? onConnectAnother;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListView(
      children: [
        for (final integration in integrations) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Symbols.hub, color: scheme.primary),
            title: Text(
              integration.fullName,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              integration.lastSyncedAt == null
                  ? 'Import queued or not synced yet'
                  : 'Last synced ${integration.lastSyncedAt!.toLocal().toString().split('.').first}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Open on GitHub',
                  icon: const Icon(Symbols.open_in_new),
                  onPressed: () => onOpen(integration),
                ),
                IconButton(
                  tooltip: 'Unlink repository',
                  icon: const Icon(Symbols.link_off),
                  onPressed: onUnlink == null
                      ? null
                      : () => onUnlink!(integration),
                ),
              ],
            ),
          ),
          if (integration.lastError != null)
            Text(
              integration.lastError!,
              style: text.bodySmall?.copyWith(color: scheme.error),
            ),
        ],
        const SizedBox(height: 16),
        Text(
          'Supported fields: title ↔ name, body ↔ content, labels ↔ tags, '
          'open/closed ↔ incomplete/completed, issue comments ↔ task comments. '
          'Groups, priority, due dates, assignees, and attachments stay in SolWatt only.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        FilledButton.tonalIcon(
          onPressed: onSync,
          icon: const Icon(Symbols.sync),
          label: const Text('Sync now'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onConnectAnother,
          icon: const Icon(Symbols.add_link),
          label: const Text('Add repository'),
        ),
        if (busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }
}
