import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/push/push_service.dart';

/// Captures outgoing requests and resolves them with an empty 200 so the
/// request never hits the network.
class _CapturingInterceptor extends Interceptor {
  final requests = <RequestOptions>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(
      Response<dynamic>(requestOptions: options, statusCode: 200),
    );
  }
}

void main() {
  group('registerSolWattPushSubscription', () {
    test('reports an Apple device token as a SolWatt APNs subscription', () async {
      final interceptor = _CapturingInterceptor();
      final client = SolarNetworkClient.fromDio(
        Dio(BaseOptions(baseUrl: 'https://example.com'))
          ..interceptors.add(interceptor),
      );

      await registerSolWattPushSubscription(
        client,
        deviceToken: 'apns-token',
        provider: SnNotificationPushSubscriptionProvider.apple,
        deviceName: 'dev.solsynth.solarwatt host',
      );

      final request = interceptor.requests.single;
      expect(request.method, 'PUT');
      expect(request.path, '/metoer/notifications/subscription');
      expect(request.data['device_token'], 'apns-token');
      expect(request.data['provider'], 0); // apple = APNs
      expect(request.data['device_name'], 'dev.solsynth.solarwatt host');
      expect(request.data['app_id'], kNotificationTenantAppId);
    });

    test('reports an FCM token as a SolWatt FCM subscription', () async {
      final interceptor = _CapturingInterceptor();
      final client = SolarNetworkClient.fromDio(
        Dio(BaseOptions(baseUrl: 'https://example.com'))
          ..interceptors.add(interceptor),
      );

      await registerSolWattPushSubscription(
        client,
        deviceToken: 'fcm-token',
        provider: SnNotificationPushSubscriptionProvider.fcm,
        deviceName: 'Pixel 9',
      );

      final request = interceptor.requests.single;
      expect(request.data['device_token'], 'fcm-token');
      expect(request.data['provider'], 1); // fcm
      expect(request.data['app_id'], kNotificationTenantAppId);
    });
  });

  test(
    'push provider defers status mutation until after initialization',
    () async {
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(solWattPushProvider), isA<SolWattPushService>());
      expect(
        container.read(solWattPushStatusProvider),
        SolWattPushRegistrationStatus.unknown,
      );

      await Future<void>.delayed(Duration.zero);
      // No Firebase app in tests: the deferred refresh reports push as
      // unavailable (or unsupported where firebase_core does not run), but
      // never leaves the status stuck at the pre-init sentinel.
      expect(
        container.read(solWattPushStatusProvider),
        isNot(SolWattPushRegistrationStatus.unknown),
      );
    },
  );
}
