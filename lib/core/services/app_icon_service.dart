import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Snapshot of the platform's alternate app icon state.
class AppIconState {
  final bool supported;
  final String? iconName;

  const AppIconState({required this.supported, this.iconName});

  /// `true` when the primary (default) app icon is active.
  bool get isPrimary => iconName == null;
}

/// Bridges alternate app icon switching to the native
/// `dev.solsynth.solarwatt/app_icon` channel (iOS + macOS).
///
/// Preview artwork for the picker is bundled as Flutter assets (see
/// `assets/icons/`); this service only reads and sets the active icon.
/// The iOS side calls `UIApplication.setAlternateIconName`; macOS has no such
/// API, so the runner swaps `NSApp.applicationIconImage` and persists the
/// choice with `NSWorkspace.setIcon`.
class AppIconService {
  AppIconService._();

  static final instance = AppIconService._();
  static const _channel = MethodChannel('dev.solsynth.solarwatt/app_icon');

  /// Alternate icon names bundled with the app. Must match the Icon Composer
  /// `.icon` document name added to the Runner targets.
  static const String cuiteIconName = 'AppIcon-Cuite';

  /// Preview asset for the primary (default) icon.
  static const String defaultIconAsset = 'assets/icons/app-icon-default.png';

  /// Preview asset for the Cuite alternate icon.
  static const String cuiteIconAsset = 'assets/icons/app-icon-cuite.png';

  bool get _isSupported => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  /// Whether the current platform supports alternate app icon switching.
  bool get isSupported => _isSupported;

  Future<AppIconState?> getState() async {
    if (!_isSupported) return null;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getIconState',
      );
      return AppIconState(
        supported: result?['supported'] == true,
        iconName: result?['current'] as String?,
      );
    } on PlatformException {
      // The runner answered with an error, e.g. an unknown method call.
      return null;
    } on MissingPluginException {
      // No runner wired the channel (test host, or a platform whose runner
      // predates it); the primary icon is the only one to show.
      return null;
    }
  }

  Future<void> setIcon(String? name) async {
    if (!_isSupported) return;
    await _channel.invokeMethod<void>('setAlternateIcon', {'name': name});
  }
}
