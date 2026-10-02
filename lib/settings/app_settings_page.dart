import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/core/services/app_icon_service.dart';
import 'package:solwatt/route.dart';
import 'package:solwatt/shared/widgets/alert.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/page_scaffold.dart';

/// Tile padding for settings rows, matching Solian's settings list so the
/// leading icons sit clear of the card edge.
const _kSettingsTilePadding = EdgeInsets.only(left: 24, right: 16);

/// Settings tab host: the settings list is the tab's root and About pushes on
/// top of it, so opening About keeps the shell and comes back to the list.
@RoutePage()
class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => const AutoRouter();
}

/// App-wide preferences: display language, appearance (theme mode and accent
/// color), and the app icon. Mirrors Solian's Appearance settings category;
/// preferences persist in SharedPreferences and the theme/locale apply
/// app-wide, while the icon choice is stored by the iOS/macOS runner.
@RoutePage()
class AppSettingsHomePage extends ConsumerWidget {
  const AppSettingsHomePage({super.key});

  static String languageDisplayName(BuildContext context, Locale locale) {
    // Show each language in its own name so the choice reads identically in
    // both locales.
    return switch ('${locale.languageCode}-${locale.countryCode}') {
      'en-US' => 'English (US)',
      'zh-CN' => '简体中文',
      _ => locale.toString(),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);
    final accent = ref.watch(appAccentColorProvider);

    return PageScaffold(
      title: 'settings'.tr(),
      subtitle: 'settingsSubtitle'.tr(),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _SettingsSection(
            title: 'settingsLanguageSection'.tr(),
            children: [
              ListTile(
                contentPadding: _kSettingsTilePadding,
                leading: const Icon(Symbols.translate),
                title: Text('settingsDisplayLanguage'.tr()),
                trailing: DropdownButtonHideUnderline(
                  child: DropdownButton<Locale?>(
                    value: context.locale,
                    items: [
                      for (final locale in context.supportedLocales)
                        DropdownMenuItem<Locale?>(
                          value: locale,
                          child: Text(
                            AppSettingsHomePage.languageDisplayName(
                              context,
                              locale,
                            ),
                          ),
                        ),
                      DropdownMenuItem<Locale?>(
                        value: null,
                        child: Text('settingsLanguageSystem'.tr()),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        context.resetLocale();
                      } else {
                        context.setLocale(value);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: 'settingsAppearanceSection'.tr(),
            children: [
              ListTile(
                contentPadding: _kSettingsTilePadding,
                leading: const Icon(Symbols.dark_mode),
                title: Text('settingsThemeMode'.tr()),
                trailing: DropdownButtonHideUnderline(
                  child: DropdownButton<ThemeMode>(
                    value: themeMode,
                    items: [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text('settingsThemeModeSystem'.tr()),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text('settingsThemeModeLight'.tr()),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text('settingsThemeModeDark'.tr()),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(appThemeModeProvider.notifier).set(value);
                      }
                    },
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: _kSettingsTilePadding,
                leading: const Icon(Symbols.palette),
                title: Text('settingsAccentColor'.tr()),
                subtitle: Text('settingsAccentColorDescription'.tr()),
              ),
              Padding(
                // Align the swatches with the title text: tile padding (24) +
                // leading column (40) + title gap (16).
                padding: const EdgeInsets.fromLTRB(80, 0, 16, 16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final color in kAccentColorOptions)
                      _AccentDot(
                        color: color,
                        selected: accent == color.toARGB32(),
                        onTap: () => ref
                            .read(appAccentColorProvider.notifier)
                            .set(accent == color.toARGB32() ? null : color),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (AppIconService.instance.isSupported) ...[
            const SizedBox(height: 16),
            _SettingsSection(
              title: 'settingsAppIconSection'.tr(),
              children: [
                ListTile(
                  contentPadding: _kSettingsTilePadding,
                  leading: const Icon(Symbols.app_shortcut),
                  title: Text('settingsAppIconStyle'.tr()),
                  subtitle: Text('settingsAppIconDescription'.tr()),
                  trailing: const Icon(Symbols.chevron_right),
                  onTap: () => showModalBottomSheet(
                    context: context,
                    useRootNavigator: true,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => const _AppIconSheet(),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _SettingsSection(
            title: 'about'.tr(),
            children: [
              ListTile(
                contentPadding: _kSettingsTilePadding,
                leading: const Icon(Symbols.info),
                title: Text('appName'.tr()),
                subtitle: Text('aboutSubtitle'.tr()),
                trailing: const Icon(Symbols.chevron_right),
                onTap: () => context.router.push(const AboutRoute()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Outlined section card on the settings page.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card.outlined(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// Tappable seed-color swatch; tapping the selected dot restores the default.
class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? Icon(
                Symbols.check,
                size: 20,
                color: color.computeLuminance() > 0.5
                    ? Colors.black87
                    : Colors.white,
              )
            : null,
      ),
    );
  }
}

/// Grid of bundled app icons; picking one asks the platform runner to switch.
/// The default tile passes a `null` name, which restores the primary icon.
class _AppIconSheet extends HookConsumerWidget {
  const _AppIconSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentIcon = useState<String?>(null);
    final busy = useState(false);

    useEffect(() {
      AppIconService.instance.getState().then((state) {
        if (state != null) currentIcon.value = state.iconName;
      });
      return null;
    }, []);

    Future<void> select(String? name) async {
      if (busy.value) return;
      busy.value = true;
      final navigator = Navigator.of(context);
      try {
        await AppIconService.instance.setIcon(name);
        currentIcon.value = name;
        if (context.mounted) {
          navigator.pop();
          showSnackBar('settingsAppIconApplied'.tr());
        }
      } catch (err) {
        if (context.mounted) {
          navigator.pop();
          showErrorAlert('settingsAppIconFailed'.tr());
        }
      } finally {
        busy.value = false;
      }
    }

    Widget iconTile({
      required String? name,
      required String asset,
      required String label,
    }) {
      final selected = name == currentIcon.value;
      return InkWell(
        onTap: () => select(name),
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
              padding: const EdgeInsets.all(2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.asset(asset, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: selected ? theme.colorScheme.primary : null,
                fontWeight: selected ? FontWeight.w600 : null,
              ),
            ),
          ],
        ),
      );
    }

    return SheetScaffold(
      titleText: 'settingsAppIconStyle'.tr(),
      heightFactor: 0.45,
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 1.0,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        children: [
          Center(
            child: iconTile(
              name: null,
              asset: AppIconService.defaultIconAsset,
              label: 'settingsAppIconDefault'.tr(),
            ),
          ),
          Center(
            child: iconTile(
              name: AppIconService.cuiteIconName,
              asset: AppIconService.cuiteIconAsset,
              label: 'settingsAppIconCuite'.tr(),
            ),
          ),
        ],
      ),
    );
  }
}
