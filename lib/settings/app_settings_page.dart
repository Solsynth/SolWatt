import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/theme.dart';
import 'package:solwatt/ui/page_scaffold.dart';

/// Tile padding for settings rows, matching Solian's settings list so the
/// leading icons sit clear of the card edge.
const _kSettingsTilePadding = EdgeInsets.only(left: 24, right: 16);

/// App-wide preferences: display language and appearance (theme mode and
/// accent color). Mirrors Solian's Appearance settings category; preferences
/// persist in SharedPreferences and the theme/locale apply app-wide.
@RoutePage()
class AppSettingsPage extends ConsumerWidget {
  const AppSettingsPage({super.key});

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
                            AppSettingsPage.languageDisplayName(
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
