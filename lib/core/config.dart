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
