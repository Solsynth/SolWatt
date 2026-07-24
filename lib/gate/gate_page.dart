import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../network.dart';
import '../workspaces/workspace_actions.dart';

/// Matches the generated [AppShellRoute] name without importing main.dart.
const _appShellRouteName = 'AppShellRoute';

/// Entry screen: sign in, then select or create a workspace before the shell.
@RoutePage()
class GatePage extends ConsumerStatefulWidget {
  const GatePage({super.key});

  @override
  ConsumerState<GatePage> createState() => _GatePageState();
}

class _GatePageState extends ConsumerState<GatePage> {
  var _signingIn = false;
  var _enteringShell = false;
  String? _signInError;

  void _enterShell() {
    if (!mounted || _enteringShell) return;
    _enteringShell = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.router.replaceAll([const PageRouteInfo(_appShellRouteName)]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(appAccessProvider);

    ref.listen(appAccessProvider, (previous, next) {
      next.whenData((state) {
        if (state == AppAccess.ready) _enterShell();
      });
    });

    return access.when(
      loading: () =>
          const _GateFrame(child: Center(child: CircularProgressIndicator())),
      error: (error, _) => _GateFrame(
        child: _SignInPanel(
          signingIn: _signingIn,
          error: error.toString(),
          onSignIn: _signIn,
        ),
      ),
      data: (state) {
        switch (state) {
          case AppAccess.loading:
            return const _GateFrame(
              child: Center(child: CircularProgressIndicator()),
            );
          case AppAccess.needsSignIn:
            return _GateFrame(
              child: _SignInPanel(
                signingIn: _signingIn,
                error: _signInError,
                onSignIn: _signIn,
              ),
            );
          case AppAccess.needsWorkspace:
            return _GateFrame(child: _WorkspacePanel(onEnter: _enterShell));
          case AppAccess.ready:
            _enterShell();
            return const _GateFrame(
              child: Center(child: CircularProgressIndicator()),
            );
        }
      },
    );
  }

  Future<void> _signIn() async {
    setState(() {
      _signingIn = true;
      _signInError = null;
    });
    try {
      await ref.read(authenticatorProvider).signIn();
      invalidateSessionScope(ref);
    } catch (error) {
      if (!mounted) return;
      setState(() => _signInError = error.toString());
      showSnackBar(error.toString());
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }
}

class _GateFrame extends StatelessWidget {
  const _GateFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _SignInPanel extends StatelessWidget {
  const _SignInPanel({
    required this.signingIn,
    required this.onSignIn,
    this.error,
  });

  final bool signingIn;
  final VoidCallback onSignIn;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Symbols.solar_power, size: 40, color: scheme.primary),
        const SizedBox(height: 20),
        Text(
          'SolWatt',
          textAlign: TextAlign.center,
          style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Sign in with Solar Network to continue.',
          textAlign: TextAlign.center,
          style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: scheme.error),
          ),
        ],
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: signingIn ? null : onSignIn,
          icon: signingIn
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onPrimary,
                  ),
                )
              : const Icon(Symbols.login),
          label: Text(
            signingIn ? 'Signing in…' : 'Continue with Solar Network',
          ),
        ),
      ],
    );
  }
}

class _WorkspacePanel extends ConsumerWidget {
  const _WorkspacePanel({required this.onEnter});

  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userInfoProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose a workspace',
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'An active workspace is required to use SolWatt.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () async {
                await ref.read(authenticatorProvider).clear();
                await clearSelectedWorkspace(ref.read(secureStorageProvider));
                invalidateSessionScope(ref);
              },
              child: const Text('Sign out'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        profile.when(
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (_, _) => const SizedBox.shrink(),
          data: (user) {
            if (user == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    foregroundImage: user.solWattAvatarUrl == null
                        ? null
                        : NetworkImage(user.solWattAvatarUrl!),
                    child: Text(_initials(user.solWattDisplayName)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.solWattDisplayName, style: text.titleSmall),
                        Text(
                          '@${user.name}',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        Row(
          children: [
            Text('Your workspaces', style: text.titleMedium),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: () => createWorkspaceAction(context, ref),
              icon: const Icon(Symbols.add, size: 18),
              label: const Text('New'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: WorkspaceList(
            onActivate: (workspace) async {
              await activateWorkspaceAction(ref, workspace);
              onEnter();
            },
          ),
        ),
      ],
    );
  }
}

String _initials(String name) {
  final parts = name
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0])
      .join()
      .toUpperCase();
  return parts.isEmpty ? '?' : parts;
}
