import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solwatt/network.dart';

/// Shared preferences handle. Overridden by the ProviderScope in main() once
/// the singleton is loaded.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in the ProviderScope',
  );
});

/// The API base URL the drive (and other services) render remote assets from.
final serverUrlProvider = Provider<String>((ref) => kSolarNetworkApiBase);

/// App settings read by the drive: data-saver mode, image compression, and
/// the default file pool. Keep the field surface identical to Solian's
/// `AppSettings` so the ported drive code compiles unchanged.
class AppSettings {
  final bool dataSavingMode;
  final bool imageCompressionEnabled;
  final int imageCompressionQuality;
  final String? defaultPoolId;

  const AppSettings({
    this.dataSavingMode = false,
    this.imageCompressionEnabled = true,
    this.imageCompressionQuality = 80,
    this.defaultPoolId,
  });
}

final appSettingsProvider = Provider<AppSettings>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AppSettings(
    dataSavingMode: prefs.getBool('drive_data_saving_mode') ?? false,
    imageCompressionEnabled:
        prefs.getBool('drive_image_compression_enabled') ?? true,
    imageCompressionQuality:
        (prefs.getInt('drive_image_compression_quality') ?? 80).clamp(10, 100),
    defaultPoolId: prefs.getString('drive_default_pool_id'),
  );
});

// --- App appearance: theme mode and accent color ----------------------------

const _kThemeModeKey = 'app_theme_mode';
const _kAccentColorKey = 'app_accent_color';

/// Dark/light/system preference, persisted in SharedPreferences. Defaults to
/// following the system, mirroring `ThemeMode.system`.
final appThemeModeProvider = NotifierProvider<AppThemeModeNotifier, ThemeMode>(
  AppThemeModeNotifier.new,
);

class AppThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final value = ref
        .watch(sharedPreferencesProvider)
        .getString(_kThemeModeKey);
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  void set(ThemeMode mode) {
    ref.read(sharedPreferencesProvider).setString(
      _kThemeModeKey,
      switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
    state = mode;
  }
}

/// Optional seed color override for the Material scheme. Null follows the app
/// default ([kSolWattSeedColor]); persisted as an ARGB int.
final appAccentColorProvider = NotifierProvider<AppAccentColorNotifier, int?>(
  AppAccentColorNotifier.new,
);

class AppAccentColorNotifier extends Notifier<int?> {
  @override
  int? build() => ref.watch(sharedPreferencesProvider).getInt(_kAccentColorKey);

  void set(Color? color) {
    final prefs = ref.read(sharedPreferencesProvider);
    if (color == null) {
      prefs.remove(_kAccentColorKey);
    } else {
      prefs.setInt(_kAccentColorKey, color.toARGB32());
    }
    state = color?.toARGB32();
  }
}

// --- App shell: last visited top-level tab --------------------------------

const _kLastTabIndexKey = 'app_last_tab_index';

/// The top-level tab the user was last on, persisted so a relaunch reopens
/// there. The value is an index into the shell's tab routes, clamped to the
/// route list on restore. Deliberately scoped to the tab alone — the mail
/// folder is *not* remembered, so mail always reopens on the inbox.
final lastTabIndexProvider = NotifierProvider<LastTabIndexNotifier, int>(
  LastTabIndexNotifier.new,
);

class LastTabIndexNotifier extends Notifier<int> {
  @override
  int build() =>
      ref.watch(sharedPreferencesProvider).getInt(_kLastTabIndexKey) ?? 0;

  void set(int index) {
    if (index == state) return;
    ref.read(sharedPreferencesProvider).setInt(_kLastTabIndexKey, index);
    state = index;
  }
}

// --- Update checks (Solsynth Express distribution) --------------------------

const _kUpdateChecksEnabledKey = 'app_update_checks_enabled';
const _kUpdateChannelKey = 'app_update_channel';

/// SolWatt's product on the Solsynth Express distribution service, the same
/// service the release workflow uploads to (see `.github/workflows/build.yml`).
/// CI overrides it with the repository's `DISTRIBUTION_PRODUCT_ID` variable;
/// local builds fall back to the published product.
const kSolWattDistributionProductId = 'cbe8b5c1-5956-4ac3-8a7d-37f4d9a0fdab';
const kDistributionProductId = String.fromEnvironment(
  'DISTRIBUTION_PRODUCT_ID',
  defaultValue: kSolWattDistributionProductId,
);

const kDefaultUpdateChannel = 'stable';

/// Whether the app checks for a newer release on launch. The check hits the
/// network on every start, so the preference can turn it off; manual checks
/// from the settings page still run while it is disabled.
final updateChecksEnabledProvider =
    NotifierProvider<UpdateChecksEnabledNotifier, bool>(
      UpdateChecksEnabledNotifier.new,
    );

class UpdateChecksEnabledNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_kUpdateChecksEnabledKey) ??
      true;

  void setEnabled(bool value) {
    ref.read(sharedPreferencesProvider).setBool(_kUpdateChecksEnabledKey, value);
    state = value;
  }
}

/// Release channel the update checks follow. Only channels the product
/// publishes are offered in settings; `stable` is the default.
final updateChannelProvider = NotifierProvider<UpdateChannelNotifier, String>(
  UpdateChannelNotifier.new,
);

class UpdateChannelNotifier extends Notifier<String> {
  @override
  String build() =>
      ref.watch(sharedPreferencesProvider).getString(_kUpdateChannelKey) ??
      kDefaultUpdateChannel;

  void setChannel(String value) {
    final channel = value.trim();
    if (channel.isEmpty) return;
    ref.read(sharedPreferencesProvider).setString(_kUpdateChannelKey, channel);
    state = channel;
  }
}
