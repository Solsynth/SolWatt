import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:solwatt/core/services/app_icon_service.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/ui/page_scaffold.dart';
import 'package:solwatt/workspaces/workspace_actions.dart';

const _appShellRouteName = 'AppShellRoute';

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

  /// The code a device sign-in is waiting on, or null when the platform's flow
  /// has nothing for the user to type. Only the web build produces one.
  DeviceAuthorization? _deviceCode;

  /// Artwork for the icon the platform is currently using, so the card matches
  /// what the user sees on their home screen or in the Dock.
  var _iconAsset = AppIconService.defaultIconAsset;

  @override
  void initState() {
    super.initState();
    _resolveIconAsset();
  }

  /// Swaps in the alternate artwork when the user picked one. Platforms without
  /// alternate icons (and any platform that cannot answer) keep the default.
  Future<void> _resolveIconAsset() async {
    final state = await AppIconService.instance.getState();
    if (!mounted || state?.iconName != AppIconService.cuiteIconName) return;
    setState(() => _iconAsset = AppIconService.cuiteIconAsset);
  }

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
          iconAsset: _iconAsset,
          signingIn: _signingIn,
          deviceCode: _deviceCode,
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
                iconAsset: _iconAsset,
                signingIn: _signingIn,
                deviceCode: _deviceCode,
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
      _deviceCode = null;
    });
    try {
      await ref.read(authenticatorProvider).signIn(
        // The web needs a code approved while this waits; publishing it is what
        // puts it on screen. The other platforms never call this.
        onDeviceCode: (authorization) {
          if (!mounted) return;
          setState(() => _deviceCode = authorization);
        },
      );
      invalidateSessionScope(ref);
    } catch (error) {
      if (!mounted) return;
      setState(() => _signInError = error.toString());
      showSnackBar(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _signingIn = false;
          _deviceCode = null;
        });
      }
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
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Material(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 32,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignInPanel extends StatelessWidget {
  const _SignInPanel({
    required this.iconAsset,
    required this.signingIn,
    required this.onSignIn,
    this.deviceCode,
    this.error,
  });

  /// Artwork of the icon the platform is currently using.
  final String iconAsset;
  final bool signingIn;
  final VoidCallback onSignIn;

  /// The code a web sign-in is waiting on, shown in place of the button.
  final DeviceAuthorization? deviceCode;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          child: Image.asset(
            iconAsset,
            width: 96,
            height: 96,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'appName'.tr(),
          textAlign: TextAlign.center,
          style: text.headlineMedium?.copyWith(letterSpacing: -0.5),
        ),
        const SizedBox(height: 8),
        Text(
          'signInSubtitle'.tr(),
          textAlign: TextAlign.center,
          style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (error != null) ...[
          const SizedBox(height: 20),
          Material(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Symbols.error, color: scheme.onErrorContainer, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      error!,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 28),
        if (deviceCode case final authorization?)
          _DeviceCodePanel(authorization: authorization)
        else
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
              signingIn ? 'signingIn'.tr() : 'continueWithSolarNetwork'.tr(),
            ),
          ),
      ],
    );
  }
}

/// The code a device sign-in is waiting on.
///
/// The web build has no callback to bounce through, so the app shows a code and
/// polls until the user has approved it in a browser. It goes away with the
/// attempt — approved, declined or expired — because the panel holding it does.
class _DeviceCodePanel extends StatelessWidget {
  const _DeviceCodePanel({required this.authorization});

  final DeviceAuthorization authorization;

  Future<void> _openVerificationPage() =>
      launchUrl(authorization.verificationUriComplete);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'deviceCodeTitle'.tr(),
            style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          SelectableText(
            authorization.userCode,
            style: text.headlineSmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            authorization.verificationUri.toString(),
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('deviceCodeWaiting'.tr(), style: text.bodySmall),
              ),
              TextButton.icon(
                onPressed: _openVerificationPage,
                icon: const Icon(Symbols.open_in_new, size: 18),
                label: Text('deviceCodeOpenPage'.tr()),
              ),
            ],
          ),
        ],
      ),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'chooseAWorkspace'.tr(),
                    style: text.headlineSmall?.copyWith(letterSpacing: -0.25),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'activeWorkspaceRequired'.tr(),
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
              child: Text('signOut'.tr()),
            ),
          ],
        ),
        const SizedBox(height: 20),
        profile.when(
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (_, _) => const SizedBox.shrink(),
          data: (user) {
            if (user == null) return const SizedBox.shrink();
            return Card(
              margin: const EdgeInsets.only(bottom: 20),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  foregroundImage: user.solWattAvatarUrl == null
                      ? null
                      : NetworkImage(user.solWattAvatarUrl!),
                  child: Text(_initials(user.solWattDisplayName)),
                ),
                title: Text(user.solWattDisplayName, style: text.titleSmall),
                subtitle: Text(
                  '@${user.name}',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          },
        ),
        SectionHeader(
          title: 'yourWorkspaces'.tr(),
          trailing: FilledButton.tonalIcon(
            onPressed: () => createWorkspaceAction(context, ref),
            icon: const Icon(Symbols.add, size: 18),
            label: Text('new'.tr()),
          ),
        ),
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
