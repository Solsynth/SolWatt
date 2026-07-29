import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/ui/alert.dart';
import 'package:solwatt/ui/page_scaffold.dart';

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
            ? 'noRepositoriesGranted'.tr()
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
      ref.invalidate(tasksProvider);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _GitHubStep.status;
      });
      showSnackBar('linkedRepo'.tr(namedArgs: {'name': repo.fullName}));
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
      ref.invalidate(tasksProvider);
      if (!mounted) return;
      setState(() => _busy = false);
      showSnackBar('githubSyncQueued'.tr());
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
      'unlinkGitHubConfirm'.tr(namedArgs: {'name': integration.fullName}),
      'unlinkGitHub'.tr(),
      icon: Symbols.link_off,
      isDanger: true,
      confirmLabel: 'unlinkGitHub'.tr(),
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
      showSnackBar('githubUnlinked'.tr());
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
      showSnackBar('couldNotOpenGitHub'.tr());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final integration = ref.watch(gitHubIntegrationProvider(widget.broadId));

    return SheetScaffold(
      titleText: 'github'.tr(),
      heightFactor: 0.78,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'githubDescription'.tr(namedArgs: {'name': widget.broadName}),
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
        title: 'couldNotLoadGitHubStatus'.tr(),
        message: wattApiErrorMessage(error),
        action: FilledButton(
          onPressed: () =>
              ref.invalidate(gitHubIntegrationProvider(widget.broadId)),
          child: Text('tryAgain'.tr()),
        ),
      ),
      data: (linked) {
        if (linked.isEmpty) {
          return EmptyState(
            icon: Symbols.hub,
            title: 'notConnected'.tr(),
            message: 'notConnectedDescription'.tr(),
            action: FilledButton.icon(
              onPressed: _busy ? null : _startConnect,
              icon: const Icon(Symbols.link),
              label: Text('connectGitHub'.tr()),
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
          'completeInstallationInGitHub'.tr(),
          textAlign: TextAlign.center,
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          polling
              ? 'waitingForGitHub'.tr()
              : 'openInstallPage'.tr(),
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const Spacer(),
        if (onCheckNow != null)
          OutlinedButton(onPressed: onCheckNow, child: Text('checkNow'.tr())),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: onRetryOpen,
          child: Text('openInstallPageAgain'.tr()),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: busy ? null : onCancel,
          child: Text('cancel'.tr()),
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
          'chooseRepositoryToLink'.tr(),
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: repos.isEmpty
              ? EmptyState(
                  icon: Symbols.folder_off,
                  title: 'noRepositories'.tr(),
                  message: 'noRepositoriesDescription'.tr(),
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
        TextButton(onPressed: onBack, child: Text('back'.tr())),
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
                  ? 'linkedImportQueued'.tr()
                  : 'lastSynced'.tr(namedArgs: {
                      'date': integration.lastSyncedAt!.toLocal().toString().split('.').first,
                    }),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'openOnGitHub'.tr(),
                  icon: const Icon(Symbols.open_in_new),
                  onPressed: () => onOpen(integration),
                ),
                IconButton(
                  tooltip: 'unlinkRepository'.tr(),
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
          'supportedFields'.tr(),
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        FilledButton.tonalIcon(
          onPressed: onSync,
          icon: const Icon(Symbols.sync),
          label: Text('syncNow'.tr()),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onConnectAnother,
          icon: const Icon(Symbols.add_link),
          label: Text('addRepository'.tr()),
        ),
        if (busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }
}
