// Generates lib/firebase_options.dart from the platform Firebase configs:
//   - android/app/google-services.json
//   - ios/SolWatt/GoogleService-Info.plist
//   - macos/SolWatt/GoogleService-Info.plist (optional; falls back to the
//     iOS/Apple app config, which shares the bundle id)
//
// This replaces the FlutterFire CLI (which requires the ruby `xcodeproj` gem
// this project does not install), mirroring MaidKit's manually generated
// options. Run from the project root:
//
//   dart run tool/generate_firebase_options.dart
//
// The output file is committed alongside the platform configs, mirroring
// MaidKit's `firebase_options.dart`. Firebase API keys are public client
// identifiers, not credentials (see MaidKit's comment).
library;

import 'dart:convert';
import 'dart:io';

const _androidConfig = 'android/app/google-services.json';
const _iosConfig = 'ios/SolWatt/GoogleService-Info.plist';
const _macosConfig = 'macos/SolWatt/GoogleService-Info.plist';
const _output = 'lib/firebase_options.dart';

/// Parses the flat `<key>…</key><string>…</string>` pairs of a
/// GoogleService-Info.plist (which never contains nested containers).
Map<String, String> _parsePlist(String path) {
  final source = File(path).readAsStringSync();
  final keys = RegExp(r'<key>([^<]+)</key>\s*<string>([^<]*)</string>')
      .allMatches(source)
      .map((m) => MapEntry(m.group(1)!, m.group(2)!));
  return Map.fromEntries(keys);
}

String _required(Map<String, String> values, String key, String source) {
  final value = values[key]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('$source is missing "$key"');
  }
  return value;
}
void _writeOptions(List<String> lines) {
  File(_output).writeAsStringSync('${lines.join('\n')}\n');
  stdout.writeln('Wrote $_output');
}

void main() {
  final androidJson = jsonDecode(File(_androidConfig).readAsStringSync())
      as Map<String, dynamic>;
  final projectInfo = androidJson['project_info'] as Map<String, dynamic>;
  final clients = (androidJson['client'] as List).cast<Map<String, dynamic>>();

  // Match the Android client by package name; app id + api key come from it.
  Map<String, dynamic>? androidClient;
  for (final client in clients) {
    final info = client['client_info'] as Map<String, dynamic>;
    final androidInfo = info['android_client_info'] as Map<String, dynamic>?;
    if (androidInfo?['package_name'] == 'dev.solsynth.solarwatt') {
      androidClient = client;
      break;
    }
  }
  if (androidClient == null) {
    throw StateError(
      'No android client for dev.solsynth.solarwatt in $_androidConfig',
    );
  }
  final androidClientInfo =
      androidClient['client_info'] as Map<String, dynamic>;
  final androidAppId = androidClientInfo['mobilesdk_app_id'] as String;
  final androidApiKeys =
      (androidClient['api_key'] as List).cast<Map<String, dynamic>>();
  final androidApiKey = androidApiKeys.first['current_key'] as String;
  // project_number is the FCM sender id.
  final messagingSenderId = projectInfo['project_number'].toString();
  final projectId = projectInfo['project_id'].toString();
  final storageBucket =
      (projectInfo['storage_bucket']?.toString() ?? '').trim();

  final ios = _parsePlist(_iosConfig);
  // A dedicated macOS config is optional: when absent (no separate macOS app
  // registered in Firebase), reuse the Apple app config. The iOS and macOS
  // apps share the bundle id, so the values are identical — the same
  // arrangement MaidKit ships (its ios/macos options are equal).
  final macosFile = File(_macosConfig);
  if (!macosFile.existsSync()) {
    stdout.writeln(
      'Note: $_macosConfig not found; reusing the iOS/Apple Firebase app '
      'options for macOS (shared bundle id).',
    );
  }
  final macos = macosFile.existsSync() ? _parsePlist(_macosConfig) : ios;

  final iosApiKey = _required(ios, 'API_KEY', _iosConfig);
  final iosAppId = _required(ios, 'GOOGLE_APP_ID', _iosConfig);
  final iosSenderId =
      ios['GCM_SENDER_ID']?.trim() ??
      iosAppId.split(':').elementAtOrNull(1) ??
      '';
  final iosProjectId = _required(ios, 'PROJECT_ID', _iosConfig);
  final iosStorageBucket =
      ios['STORAGE_BUCKET']?.trim() ?? storageBucket;
  final iosBundleId = _required(ios, 'BUNDLE_ID', _iosConfig);

  final macosApiKey = _required(macos, 'API_KEY', _macosConfig);
  final macosAppId = _required(macos, 'GOOGLE_APP_ID', _macosConfig);
  final macosSenderId =
      macos['GCM_SENDER_ID']?.trim() ??
      macosAppId.split(':').elementAtOrNull(1) ??
      '';
  final macosProjectId = _required(macos, 'PROJECT_ID', _macosConfig);
  final macosStorageBucket =
      macos['STORAGE_BUCKET']?.trim() ?? storageBucket;
  final macosBundleId = _required(macos, 'BUNDLE_ID', _macosConfig);

  final lines = <String>[
    '// GENERATED FILE — do not edit by hand.',
    '// Regenerate with `dart run tool/generate_firebase_options.dart` after',
    '// updating android/app/google-services.json, ios/SolWatt/',
    '// GoogleService-Info.plist or macos/SolWatt/GoogleService-Info.plist.',
    "import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;",
    "import 'package:flutter/foundation.dart'",
    "    show defaultTargetPlatform, TargetPlatform, kIsWeb;",
    '',
    '/// Default [FirebaseOptions] for use with your Firebase apps.',
    'class DefaultFirebaseOptions {',
    '  static FirebaseOptions get currentPlatform {',
    '    if (kIsWeb) {',
    "      // No web Firebase app is registered for SolWatt yet.",
    "      throw UnsupportedError(",
    "        'DefaultFirebaseOptions are not supported on this platform.',",
    '      );',
    '    }',
    '    switch (defaultTargetPlatform) {',
    '      case TargetPlatform.android:',
    '        return android;',
    '      case TargetPlatform.iOS:',
    '        return ios;',
    '      case TargetPlatform.macOS:',
    '        return macos;',
    '      case TargetPlatform.fuchsia:',
    '      case TargetPlatform.linux:',
    '      case TargetPlatform.windows:',
    '        // firebase_core has no Linux/Windows/fuchsia support; the app',
    '        // never initializes Firebase there.',
    "        throw UnsupportedError(",
    "          'DefaultFirebaseOptions are not supported on this platform.',",
    '        );',
    '    }',
    '  }',
    '',
    '  static const FirebaseOptions android = FirebaseOptions(',
    "    apiKey: '$androidApiKey',",
    "    appId: '$androidAppId',",
    "    messagingSenderId: '$messagingSenderId',",
    "    projectId: '$projectId',",
    "    storageBucket: '$storageBucket',",
    '  );',
    '',
    '  static const FirebaseOptions ios = FirebaseOptions(',
    "    apiKey: '$iosApiKey',",
    "    appId: '$iosAppId',",
    "    messagingSenderId: '$iosSenderId',",
    "    projectId: '$iosProjectId',",
    "    storageBucket: '$iosStorageBucket',",
    "    iosBundleId: '$iosBundleId',",
    '  );',
    '',
    '  static const FirebaseOptions macos = FirebaseOptions(',
    "    apiKey: '$macosApiKey',",
    "    appId: '$macosAppId',",
    "    messagingSenderId: '$macosSenderId',",
    "    projectId: '$macosProjectId',",
    "    storageBucket: '$macosStorageBucket',",
    "    iosBundleId: '$macosBundleId',",
    '  );',
    '}',
    '',
  ];

  _writeOptions(lines);
}
