// GENERATED FILE — do not edit by hand.
// Regenerate with `dart run tool/generate_firebase_options.dart` after
// updating android/app/google-services.json, ios/Runner/
// GoogleService-Info.plist or macos/Runner/GoogleService-Info.plist.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      // No web Firebase app is registered for SolWatt yet.
      throw UnsupportedError(
        'DefaultFirebaseOptions are not supported on this platform.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        // firebase_core has no Linux/Windows/fuchsia support; the app
        // never initializes Firebase there.
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported on this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBc9DgIaxN4l2F6XbVlM_Ft3j4pwFWdW6A',
    appId: '1:450302957176:android:e70b21a08396054da93f8d',
    messagingSenderId: '450302957176',
    projectId: 'solwatt-0x001',
    storageBucket: 'solwatt-0x001.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCKNRaMOILz8vuejOld1MMeMZih0CknqyU',
    appId: '1:450302957176:ios:b12645c27fde6234a93f8d',
    messagingSenderId: '450302957176',
    projectId: 'solwatt-0x001',
    storageBucket: 'solwatt-0x001.firebasestorage.app',
    iosBundleId: 'dev.solsynth.solarwatt',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCKNRaMOILz8vuejOld1MMeMZih0CknqyU',
    appId: '1:450302957176:ios:b12645c27fde6234a93f8d',
    messagingSenderId: '450302957176',
    projectId: 'solwatt-0x001',
    storageBucket: 'solwatt-0x001.firebasestorage.app',
    iosBundleId: 'dev.solsynth.solarwatt',
  );
}

