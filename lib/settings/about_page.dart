import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:solwatt/ui/page_scaffold.dart';

/// About page: app identity, legal links, and developer credits. Mirrors
/// Solian's About screen, trimmed to the app-wide facts SolWatt owns.
@RoutePage()
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PageScaffold(
      title: 'about'.tr(),
      subtitle: 'aboutSubtitle'.tr(),
      child: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Text('aboutLoadFailed'.tr()),
            );
          }
          final info = snapshot.data!;
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              _AboutHeader(info: info),
              const SizedBox(height: 16),
              _AboutSection(
                title: 'aboutAppSection'.tr(),
                children: [
                  _AboutInfoRow(
                    icon: Symbols.info,
                    label: 'aboutAppName'.tr(),
                    value: info.appName,
                  ),
                  const Divider(height: 1),
                  _AboutInfoRow(
                    icon: Symbols.tag,
                    label: 'aboutVersion'.tr(),
                    value: info.version,
                  ),
                  const Divider(height: 1),
                  _AboutInfoRow(
                    icon: Symbols.build,
                    label: 'aboutBuildNumber'.tr(),
                    value: info.buildNumber,
                  ),
                  const Divider(height: 1),
                  _AboutInfoRow(
                    icon: Symbols.inventory_2,
                    label: 'aboutPackageName'.tr(),
                    value: info.packageName,
                    copyable: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _AboutSection(
                title: 'aboutLinksSection'.tr(),
                children: [
                  _AboutLinkTile(
                    icon: Symbols.privacy_tip,
                    title: 'aboutPrivacyPolicy'.tr(),
                    onTap: () => _launch(
                      'https://solsynth.dev/terms/privacy-policy',
                    ),
                  ),
                  const Divider(height: 1),
                  _AboutLinkTile(
                    icon: Symbols.description,
                    title: 'aboutTermsOfService'.tr(),
                    onTap: () => _launch(
                      'https://solsynth.dev/terms/user-agreement',
                    ),
                  ),
                  const Divider(height: 1),
                  _AboutLinkTile(
                    icon: Symbols.code,
                    title: 'aboutLicenses'.tr(),
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: info.appName,
                      applicationVersion: 'Version ${info.version}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _AboutSection(
                title: 'aboutDeveloperSection'.tr(),
                children: [
                  _AboutLinkTile(
                    icon: Symbols.mail,
                    title: 'aboutContact'.tr(),
                    subtitle: 'lily@solsynth.dev',
                    onTap: () => _launch('mailto:lily@solsynth.dev'),
                  ),
                  const Divider(height: 1),
                  _AboutLinkTile(
                    icon: Symbols.copyright,
                    title: 'aboutLicense'.tr(),
                    subtitle: 'aboutLicenseContent'.tr(),
                    onTap: () => _launch(
                      'https://github.com/Solsynth/Solian/blob/v3/LICENSE.txt',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'aboutCopyright'.tr(
                  namedArgs: {'year': '${DateTime.now().year}'},
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// App identity header: icon, name, and version line.
class _AboutHeader extends StatelessWidget {
  const _AboutHeader({required this.info});

  final PackageInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Image.asset('assets/icons/icon.png'),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.appName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'aboutVersionInfo'.tr(
                    namedArgs: {
                      'version': info.version,
                      'build': info.buildNumber,
                    },
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Outlined section card on the about page.
class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          ...children,
        ],
      ),
    );
  }
}

/// Label/value row with an optional copy button.
class _AboutInfoRow extends StatelessWidget {
  const _AboutInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          if (copyable)
            IconButton(
              icon: const Icon(Symbols.content_copy, size: 16),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('copied'.tr())),
                );
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'copyToClipboard'.tr(),
            ),
        ],
      ),
    );
  }
}

/// Tappable link row with a chevron.
class _AboutLinkTile extends StatelessWidget {
  const _AboutLinkTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final multipleLines = subtitle?.contains('\n') ?? false;
    return Column(
      children: [
        ListTile(
          leading: Padding(
            padding: EdgeInsets.only(top: multipleLines ? 8 : 0),
            child: Icon(icon, size: 20),
          ),
          title: Text(title),
          subtitle: subtitle != null ? Text(subtitle!) : null,
          isThreeLine: multipleLines,
          trailing: Padding(
            padding: EdgeInsets.only(top: multipleLines ? 8 : 0),
            child: const Icon(Symbols.chevron_right),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          minLeadingWidth: 24,
          onTap: onTap,
        ),
      ],
    );
  }
}
