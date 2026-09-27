import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:solwatt/network.dart';

/// Answers the endpoints the flow walks, in the order it walks them, and
/// records what it was asked for.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this._answers);

  final List<ResponseBody> _answers;
  final List<String> paths = [];
  final List<Map<String, dynamic>> bodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    final data = options.data;
    bodies.add(data is Map ? Map<String, dynamic>.from(data) : const {});
    if (_answers.isEmpty) {
      throw StateError('the stub was asked for more than it was given');
    }
    return _answers.removeAt(0);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

Object _discovery({bool withDeviceEndpoint = true}) => {
  'authorization_endpoint': 'https://id.example/auth/authorize',
  'token_endpoint': 'https://api.example/stargate/auth/open/token',
  if (withDeviceEndpoint)
    'device_authorization_endpoint':
        'https://api.example/stargate/auth/open/device/code',
};

Object _deviceCode({int interval = 0}) => {
  'device_code': 'device-secret',
  'user_code': 'ABCD-EFGH',
  'verification_uri': 'https://id.example/auth/device',
  'verification_uri_complete': 'https://id.example/auth/device?code=ABCD-EFGH',
  'expires_in': 600,
  'interval': interval,
};

SolarNetworkAuthenticator _authenticator(_StubAdapter adapter, {bool isWeb = true}) =>
    SolarNetworkAuthenticator(
      const FlutterSecureStorage(),
      isWeb: isWeb,
      dioFactory: ([options]) {
        final dio = Dio(options);
        dio.httpClientAdapter = adapter;
        return dio;
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The session is written through the secure-storage channel; answer it so a
  // successful sign-in can be stored.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
  });

  test('a device sign-in is shown the code and polls until it is approved', () async {
    final adapter = _StubAdapter([
      _json(_discovery()),
      _json(_deviceCode()),
      // The user has not answered yet, twice, then does.
      _json({'error': 'authorization_pending'}, 400),
      _json({'error': 'authorization_pending'}, 400),
      _json({'access_token': 'access', 'refresh_token': 'refresh'}),
    ]);
    final shown = <DeviceAuthorization>[];

    final session = await _authenticator(adapter).signIn(onDeviceCode: shown.add);

    expect(session.accessToken, 'access');
    expect(session.refreshToken, 'refresh');
    expect(shown, hasLength(1));
    expect(shown.single.userCode, 'ABCD-EFGH');
    expect(
      shown.single.verificationUri.toString(),
      'https://id.example/auth/device',
    );
    expect(
      shown.single.verificationUriComplete.queryParameters['code'],
      'ABCD-EFGH',
    );

    // Discovery, the code, two refusals to answer, the token.
    expect(adapter.paths, [
      '$kSolarNetworkApiBase/.well-known/openid-configuration',
      'https://api.example/stargate/auth/open/device/code',
      'https://api.example/stargate/auth/open/token',
      'https://api.example/stargate/auth/open/token',
      'https://api.example/stargate/auth/open/token',
    ]);
    expect(adapter.bodies[1], {'client_id': 'solarwatt', 'scope': '*'});
    expect(adapter.bodies[4], {
      'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      'device_code': 'device-secret',
      'client_id': 'solarwatt',
    });
  });

  test('a code that is never approved fails rather than polling forever', () async {
    final adapter = _StubAdapter([
      _json(_discovery()),
      _json(_deviceCode()),
      _json({'error': 'expired_token'}, 400),
    ]);

    await expectLater(
      _authenticator(adapter).signIn(),
      throwsA(
        isA<OAuthException>().having(
          (error) => error.message,
          'message',
          contains('expired'),
        ),
      ),
    );
    expect(
      adapter.paths.where((path) => path.endsWith('/token')),
      hasLength(1),
    );
  });

  test('a declined sign-in reports the refusal', () async {
    final adapter = _StubAdapter([
      _json(_discovery()),
      _json(_deviceCode()),
      _json({'error': 'access_denied'}, 400),
    ]);

    await expectLater(
      _authenticator(adapter).signIn(),
      throwsA(
        isA<OAuthException>().having(
          (error) => error.message,
          'message',
          contains('declined'),
        ),
      ),
    );
  });

  test('a deployment without a device endpoint says so', () async {
    final adapter = _StubAdapter([
      _json(_discovery(withDeviceEndpoint: false)),
    ]);

    await expectLater(
      _authenticator(adapter).signIn(),
      throwsA(
        isA<OAuthException>().having(
          (error) => error.message,
          'message',
          contains('does not offer device sign-in'),
        ),
      ),
    );
    expect(adapter.paths, hasLength(1));
  });
}
