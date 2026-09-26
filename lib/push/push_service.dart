import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/firebase_options.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/notifications/notifications.dart';

/// Firebase is only available on platforms firebase_core/firebase_messaging
/// support (Android, iOS, macOS). Linux, Windows and the web silently keep
/// the in-app Metoer feed (over the gateway websocket) as their only
/// notification surface.
bool firebaseSupported() {
  if (kIsWeb) return false;
  return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
}

/// System-notification channel used for SolWatt pushes.
const kSolWattNotificationChannelId = 'solarwatt_notifications';
const kSolWattNotificationChannelName = 'SolWatt';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

/// Shows a system notification. Safe to call from any isolate; the plugin is
/// created fresh so the background FCM isolate does not share main-isolate
/// state.
Future<void> showSolWattSystemNotification({
  required String title,
  required String body,
}) async {
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/launcher_icon'),
    iOS: DarwinInitializationSettings(),
    macOS: DarwinInitializationSettings(),
  );
  await _localNotifications.initialize(settings: settings);
  await _localNotifications.show(
    id: 0,
    title: title,
    body: body.isEmpty ? null : body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        kSolWattNotificationChannelId,
        kSolWattNotificationChannelName,
        channelDescription: 'Notifications from the Solar Network',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
  );
}

/// Cold-start and background FCM entry point. The isolate has no access to
/// the widget tree, so it only surfaces the system notification; the in-app
/// feed refreshes on the next page load.
@pragma('vm:entry-point')
Future<void> solWattFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final data = message.data;
  final title = data['title']?.toString() ?? 'SolWatt';
  final body = data['body']?.toString() ?? data['content']?.toString() ?? '';
  if (body.isEmpty && title == 'SolWatt') return;
  await showSolWattSystemNotification(title: title, body: body);
}

enum SolWattPushRegistrationStatus {
  unknown,
  notSignedIn,
  registering,
  registered,
  waitingForToken,
  unavailable,
  unsupported,
  failed,
}

/// Reports the device token to Metoer as a SolWatt push subscription
/// (`PUT /metoer/notifications/subscription` with the SolWatt tenant
/// `app_id`). Top-level so the wire contract is testable without Firebase.
Future<void> registerSolWattPushSubscription(
  SolarNetworkClient client, {
  required String deviceToken,
  required SnNotificationPushSubscriptionProvider provider,
  required String deviceName,
}) {
  return client.notifications.registerPushSubscription(
    deviceToken: deviceToken,
    provider: provider,
    deviceName: deviceName,
    appId: kNotificationTenantAppId,
  );
}

/// Registers this device for FCM/APNs push of Solar Network notifications,
/// mirroring Solian's `subscribePushNotification`
/// (`lib/core/services/notify.universal.dart`) and MaidKit's
/// `MaidCafePushService`. The device token is reported to Metoer as a
/// `dev.solsynth.solarwatt` subscription (`PUT /metoer/notifications/
/// subscription` with `app_id`), so the gateway can route pushes to this
/// device.
class SolWattPushService {
  SolWattPushService({
    required this.clientProvider,
    required this.onNotification,
    this.onStatusChanged,
  });

  /// Fresh authenticated SDK client per registration, so a sign-in or
  /// sign-out that invalidates [solarNetworkClientProvider] is honored.
  final SolarNetworkClient Function() clientProvider;

  /// Invoked when a push arrives while the app is in the foreground, so the
  /// in-app notification feed can refresh (the gateway websocket is the
  /// foreground surface; system banners are reserved for background/cold
  /// start to avoid duplication).
  final void Function() onNotification;

  /// Reports registration state to callers/tests.
  final void Function(SolWattPushRegistrationStatus status)? onStatusChanged;

  Future<void>? _pending;
  bool _subscribed = false;
  bool _listenersAttached = false;

  SolWattPushRegistrationStatus get initialStatus {
    if (!firebaseSupported()) {
      return SolWattPushRegistrationStatus.unsupported;
    }
    return SolWattPushRegistrationStatus.unknown;
  }

  void refreshStatus({required bool signedIn}) {
    final status = !firebaseSupported()
        ? SolWattPushRegistrationStatus.unsupported
        : Firebase.apps.isEmpty
        ? SolWattPushRegistrationStatus.unavailable
        : _subscribed
        ? SolWattPushRegistrationStatus.registered
        : signedIn
        ? SolWattPushRegistrationStatus.unknown
        : SolWattPushRegistrationStatus.notSignedIn;
    onStatusChanged?.call(status);
  }

  void markNotSignedIn() {
    _subscribed = false;
    refreshStatus(signedIn: false);
  }

  /// Registers this device. A normal call is idempotent for the current
  /// session; concurrent calls share one attempt. [force] repeats the
  /// platform-token registration after a successful attempt so a retry can
  /// repair a stale server-side subscription.
  Future<void> subscribe({bool force = false}) {
    if (!firebaseSupported()) {
      debugPrint(
        '[SolWattPush] Skipping registration: Firebase is unsupported on '
        '${Platform.operatingSystem}.',
      );
      onStatusChanged?.call(SolWattPushRegistrationStatus.unsupported);
      return Future.value();
    }
    if (Firebase.apps.isEmpty) {
      debugPrint(
        '[SolWattPush] Skipping registration: Firebase is not initialized '
        '(platform config missing?).',
      );
      onStatusChanged?.call(SolWattPushRegistrationStatus.unavailable);
      return Future.value();
    }
    if (_subscribed && !force) {
      debugPrint('[SolWattPush] Already registered this session.');
      onStatusChanged?.call(SolWattPushRegistrationStatus.registered);
      return Future.value();
    }
    if (_pending != null) return _pending!;
    debugPrint(
      '[SolWattPush] Starting ${Platform.operatingSystem} registration.',
    );
    onStatusChanged?.call(SolWattPushRegistrationStatus.registering);
    final attempt = _subscribe();
    _pending = attempt;
    return attempt;
  }

  Future<void> _subscribe() async {
    try {
      final registered = await _register();
      _subscribed = registered;
      debugPrint(
        registered
            ? '[SolWattPush] Server accepted the push subscription.'
            : '[SolWattPush] No device token is available yet.',
      );
      onStatusChanged?.call(
        registered
            ? SolWattPushRegistrationStatus.registered
            : SolWattPushRegistrationStatus.waitingForToken,
      );
    } catch (error, stackTrace) {
      debugPrint('[SolWattPush] Registration failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      onStatusChanged?.call(SolWattPushRegistrationStatus.failed);
      rethrow;
    } finally {
      _pending = null;
    }
  }

  Future<bool> _register() async {
    final permission = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint(
      '[SolWattPush] Notification permission: '
      '${permission.authorizationStatus}.',
    );
    // macOS: FCM-managed APNs registration like MaidKit — re-enable
    // auto-init so the plugin's native setter calls
    // registerForRemoteNotifications(). iOS deliberately keeps
    // FirebaseMessagingAutoInitEnabled = NO (Info.plist): APNs is used
    // directly, so the token below comes from the native registration.
    if (Platform.isMacOS) {
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      debugPrint('[SolWattPush] Requested native APNs registration.');
    }
    final deviceName = await _deviceName();

    if (Platform.isAndroid) {
      _attachListeners();
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint(
        token == null || token.isEmpty
            ? '[SolWattPush] FCM token was empty.'
            : '[SolWattPush] FCM token obtained.',
      );
      if (token != null && token.isNotEmpty) {
        await _registerToken(
          token,
          SnNotificationPushSubscriptionProvider.fcm,
          deviceName,
        );
        return true;
      }
      return false;
    }

    // iOS/macOS: obtain APNs before using the token as the Apple push
    // subscription identity. The Firebase guide requires APNs to be ready
    // before making other Apple messaging API calls.
    final apnsToken = await _apnsTokenWithRetry();
    debugPrint(
      apnsToken == null || apnsToken.isEmpty
          ? '[SolWattPush] APNs token was empty.'
          : '[SolWattPush] APNs token obtained.',
    );
    _attachListeners();
    if (apnsToken != null && apnsToken.isNotEmpty) {
      await _registerToken(
        apnsToken,
        SnNotificationPushSubscriptionProvider.apple,
        deviceName,
      );
      return true;
    }
    return false;
  }

  /// Reports the device token to Metoer as a SolWatt push subscription.
  Future<void> _registerToken(
    String token,
    SnNotificationPushSubscriptionProvider provider,
    String deviceName,
  ) {
    return registerSolWattPushSubscription(
      clientProvider(),
      deviceToken: token,
      provider: provider,
      deviceName: deviceName,
    );
  }

  /// Attaches the token-refresh and foreground-message listeners once.
  void _attachListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      debugPrint('[SolWattPush] Token refresh received.');
      onStatusChanged?.call(SolWattPushRegistrationStatus.registering);
      try {
        var registered = false;
        final deviceName = await _deviceName();
        if (Platform.isAndroid) {
          await _registerToken(
            token,
            SnNotificationPushSubscriptionProvider.fcm,
            deviceName,
          );
          registered = token.isNotEmpty;
        } else {
          final apnsToken = await _apnsTokenWithRetry();
          if (apnsToken != null && apnsToken.isNotEmpty) {
            await _registerToken(
              apnsToken,
              SnNotificationPushSubscriptionProvider.apple,
              deviceName,
            );
            registered = true;
          }
        }
        _subscribed = registered;
        debugPrint(
          registered
              ? '[SolWattPush] Refreshed token registered.'
              : '[SolWattPush] Refreshed token was empty.',
        );
        onStatusChanged?.call(
          registered
              ? SolWattPushRegistrationStatus.registered
              : SolWattPushRegistrationStatus.waitingForToken,
        );
      } catch (error, stackTrace) {
        debugPrint('[SolWattPush] Token refresh registration failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        onStatusChanged?.call(SolWattPushRegistrationStatus.failed);
        // Registration is an upsert; the next token refresh or sign-in
        // retries it. Never let push bookkeeping crash the app.
      }
    });

    FirebaseMessaging.onMessage.listen((message) {
      // Foreground pushes surface through the gateway websocket in-app feed
      // (realtime.dart -> notifications.new); showing a system banner too
      // would duplicate every notification while the app is focused. When
      // the app is backgrounded or terminated the system banner is shown by
      // the OS payload or the background handler instead.
      final data = message.data;
      final title = data['title']?.toString() ?? 'SolWatt';
      final body = data['body']?.toString() ?? data['content']?.toString() ?? '';
      if (title == 'SolWatt' && body.isEmpty) return;
      onNotification();
    });
  }

  Future<String?> _apnsTokenWithRetry() async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final token = await FirebaseMessaging.instance.getAPNSToken();
      if (token != null && token.isNotEmpty) return token;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return null;
  }

  Future<String> _deviceName() async {
    if (Platform.isAndroid) {
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        final model = info.model;
        if (model.trim().isNotEmpty) return model.trim();
      } catch (_) {
        // Fall through to the hostname default.
      }
    }
    try {
      final hostname = Platform.localHostname.trim();
      if (hostname.isNotEmpty) return hostname;
    } catch (_) {
      // Fall through.
    }
    return 'SolWatt device';
  }
}

class SolWattPushStatusNotifier
    extends Notifier<SolWattPushRegistrationStatus> {
  @override
  SolWattPushRegistrationStatus build() =>
      SolWattPushRegistrationStatus.unknown;

  void set(SolWattPushRegistrationStatus status) => state = status;
}

final solWattPushStatusProvider =
    NotifierProvider<SolWattPushStatusNotifier, SolWattPushRegistrationStatus>(
      SolWattPushStatusNotifier.new,
    );

/// FCM/APNs push for Solar Network notifications. Kept alive by the app
/// shell; subscribes once a Solar account is signed in (either at startup or
/// on a later sign-in) and refreshes the in-app notification feed when a push
/// arrives while the app is running.
final solWattPushProvider = Provider<SolWattPushService>((ref) {
  final status = ref.read(solWattPushStatusProvider.notifier);
  final service = SolWattPushService(
    clientProvider: () => ref.read(solarNetworkClientProvider),
    onNotification: () {
      ref.invalidate(notificationUnreadCountProvider);
      ref.invalidate(notificationListProvider);
    },
    onStatusChanged: status.set,
  );
  ref.listen(authSessionProvider, (previous, next) {
    final session = next.asData?.value;
    if (session != null) {
      unawaited(service.subscribe());
    } else if (next.hasValue) {
      service.markNotSignedIn();
    }
  });
  // The provider may be first built after the user already resolved (e.g. a
  // session restored at startup); ref.listen does not deliver the current
  // value, so check it explicitly. Defer the initial status update until this
  // provider has finished building; the callback updates a separate provider.
  Future<void>.microtask(() {
    if (!ref.mounted) return;
    final session = ref.read(authSessionProvider).asData?.value;
    service.refreshStatus(signedIn: session != null);
    if (session != null) unawaited(service.subscribe());
  });
  return service;
});
