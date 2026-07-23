import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

const _issuer = 'https://api.solian.app';
const _callbackScheme = 'solwatt';
const _redirectUri = '$_callbackScheme://oauth/callback';

/// Public OAuth client for SolWatt. This authorization-code flow uses PKCE and
/// never includes a client secret.
const _clientId = 'solarwatt';

class OAuthSession {
  const OAuthSession({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  bool get needsRefresh =>
      expiresAt != null &&
      DateTime.now().isAfter(expiresAt!.subtract(const Duration(seconds: 30)));

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt?.toUtc().toIso8601String(),
  };

  static OAuthSession? fromJson(Map<String, dynamic> json) {
    final accessToken = json['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) return null;
    return OAuthSession(
      accessToken: accessToken,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: DateTime.tryParse(
        json['expires_at'] as String? ?? '',
      )?.toLocal(),
    );
  }
}

class _OidcConfiguration {
  const _OidcConfiguration({
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
  });

  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;

  factory _OidcConfiguration.fromJson(Map<String, dynamic> json) =>
      _OidcConfiguration(
        authorizationEndpoint: Uri.parse(
          json['authorization_endpoint'] as String,
        ),
        tokenEndpoint: Uri.parse(json['token_endpoint'] as String),
      );
}

class SolarNetworkAuthenticator {
  SolarNetworkAuthenticator(this._storage);

  static const _storageKey = 'solar_network_oauth_session';
  final FlutterSecureStorage _storage;

  Future<OAuthSession?> restore() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null) return null;
    try {
      return OAuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<OAuthSession> signIn() async {
    Logger.root.info('[OAuth] Starting authorization-code flow.');
    final configuration = await _discover();
    final verifier = _randomUrlSafe(64);
    final state = _randomUrlSafe(32);
    final challenge = base64Url
        .encode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');
    final authorizationUrl = configuration.authorizationEndpoint.replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': _clientId,
        'redirect_uri': _redirectUri,
        // Solar Network accepts * as the full-access scope for first-party apps.
        'scope': '*',
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      },
    );

    final callback = Uri.parse(
      await FlutterWebAuth2.authenticate(
        url: authorizationUrl.toString(),
        callbackUrlScheme: _callbackScheme,
      ),
    );
    if (callback.queryParameters['state'] != state) {
      throw const OAuthException(
        'The authorization response could not be verified.',
      );
    }
    final error = callback.queryParameters['error'];
    if (error != null) {
      throw OAuthException(
        callback.queryParameters['error_description'] ?? error,
      );
    }
    final code = callback.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const OAuthException(
        'The authorization server did not return an authorization code.',
      );
    }

    final session = await _exchange(configuration.tokenEndpoint, {
      'grant_type': 'authorization_code',
      'client_id': _clientId,
      'code': code,
      'redirect_uri': _redirectUri,
      'code_verifier': verifier,
    });
    await _save(session);
    Logger.root.info('[OAuth] Authorization completed successfully.');
    return session;
  }

  Future<OAuthSession?> validSession() async {
    final session = await restore();
    if (session == null || !session.needsRefresh) return session;
    if (session.refreshToken == null || session.refreshToken!.isEmpty) {
      await clear();
      return null;
    }
    try {
      final configuration = await _discover();
      final refreshed = await _exchange(configuration.tokenEndpoint, {
        'grant_type': 'refresh_token',
        'client_id': _clientId,
        'refresh_token': session.refreshToken!,
      }, previous: session);
      await _save(refreshed);
      return refreshed;
    } on DioException {
      Logger.root.warning(
        '[OAuth] Refresh token request failed; clearing session.',
      );
      await clear();
      return null;
    }
  }

  Future<void> clear() => _storage.delete(key: _storageKey);

  /// Reads the signed-in Solar Network profile using the current access token.
  Future<OAuthUser?> getUserInfo() async {
    final session = await validSession();
    if (session == null) return null;
    final client = _createLoggedDio();
    final options = Options(
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
    );
    // Island reads this endpoint for the signed-in account. It contains the
    // profile picture reference required by the settings avatar.
    final accountResponse = await client.get<Map<String, dynamic>>(
      '$_issuer/passport/accounts/me',
      options: options,
    );
    final accountData = accountResponse.data;
    return accountData == null ? null : OAuthUser.fromJson(accountData);
  }

  Future<_OidcConfiguration> _discover() async {
    final response = await _createLoggedDio().get<Map<String, dynamic>>(
      '$_issuer/.well-known/openid-configuration',
    );
    final data = response.data;
    if (data == null) {
      throw const OAuthException('Unable to load OAuth configuration.');
    }
    return _OidcConfiguration.fromJson(data);
  }

  Future<OAuthSession> _exchange(
    Uri endpoint,
    Map<String, String> fields, {
    OAuthSession? previous,
  }) async {
    final response = await _createLoggedDio().post<Map<String, dynamic>>(
      endpoint.toString(),
      data: fields,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final data = response.data ?? const <String, dynamic>{};
    final accessToken = (data['access_token'] ?? data['token']) as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const OAuthException(
        'The token response did not include an access token.',
      );
    }
    final expiresIn = data['expires_in'];
    return OAuthSession(
      accessToken: accessToken,
      refreshToken: data['refresh_token'] as String? ?? previous?.refreshToken,
      expiresAt: expiresIn is num
          ? DateTime.now().add(Duration(seconds: expiresIn.toInt()))
          : null,
    );
  }

  Future<void> _save(OAuthSession session) =>
      _storage.write(key: _storageKey, value: jsonEncode(session.toJson()));

  String _randomUrlSafe(int length) {
    final values = List<int>.generate(
      length,
      (_) => Random.secure().nextInt(256),
    );
    return base64Url.encode(values).replaceAll('=', '');
  }
}

class OAuthException implements Exception {
  const OAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class OAuthUser {
  const OAuthUser({
    required this.id,
    this.username,
    this.name,
    this.email,
    this.avatarUrl,
  });

  final String id;
  final String? username;
  final String? name;
  final String? email;
  final String? avatarUrl;

  String get displayName => name?.trim().isNotEmpty == true
      ? name!.trim()
      : email?.trim().isNotEmpty == true
      ? email!.trim()
      : id;

  factory OAuthUser.fromJson(Map<String, dynamic> json) {
    String? textValue(String key) {
      final value = json[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    final profile = json['profile'];
    final picture = profile is Map ? profile['picture'] : null;
    final pictureUrl = picture is Map
        ? picture['url']?.toString() ??
              picture['storage_url']?.toString() ??
              (picture['id'] == null
                  ? null
                  : '$_issuer/drive/files/${picture['id']}')
        : picture is String
        ? picture
        : null;

    return OAuthUser(
      id: textValue('id') ?? textValue('sub') ?? '',
      username: textValue('name') ?? textValue('preferred_username'),
      name:
          textValue('nick') ??
          textValue('name') ??
          textValue('preferred_username'),
      email: textValue('email'),
      // OIDC commonly uses `picture`; accept Solar Network-compatible aliases.
      avatarUrl:
          pictureUrl ??
          textValue('picture') ??
          textValue('avatar_url') ??
          textValue('avatar'),
    );
  }
}

/// Authenticated client for WattEngine. Valve paths map to `/value`; Ideask
/// paths map to `/ideask`, as exposed by the Solar Network API gateway.
class WattEngineClient {
  WattEngineClient(this._authenticator)
    : _dio = _createLoggedDio(
        BaseOptions(
          baseUrl: _issuer,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: const {'Accept': 'application/json'},
        ),
      );

  final SolarNetworkAuthenticator _authenticator;
  final Dio _dio;

  Future<List<Workspace>> listWorkspaces() async {
    Logger.root.info('[WattEngine] Loading workspaces.');
    final response = await _get<List<dynamic>>('/value/workspaces');
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => Workspace.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<Workspace> createWorkspace({
    required String slug,
    required String name,
    String? description,
    required int type,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '/value/workspaces',
      data: {
        'slug': slug,
        'name': name,
        'description': description,
        'type': type,
      },
    );
    return Workspace.fromJson(response.data!);
  }

  Future<Workspace> updateWorkspace({
    required String slug,
    required String name,
    String? description,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'PATCH',
      '/value/workspaces/$slug',
      data: {'name': name, 'description': description},
    );
    return Workspace.fromJson(response.data!);
  }

  Future<void> deleteWorkspace(String slug) =>
      _request<void>('DELETE', '/value/workspaces/$slug');

  Future<WorkspaceQuota> getWorkspaceQuota(String slug) async {
    final response = await _get<Map<String, dynamic>>(
      '/value/workspaces/$slug/quota',
    );
    return WorkspaceQuota.fromJson(response.data ?? const {});
  }

  Future<List<Broad>> listBroads({String? workspaceId}) async {
    Logger.root.info('[WattEngine] Loading Ideask boards.');
    final response = await _get<List<dynamic>>(
      '/ideask/broads',
      queryParameters: workspaceId == null
          ? null
          : {'workspaceId': workspaceId},
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => Broad.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<Response<T>> _get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) => _request<T>('GET', path, queryParameters: queryParameters);

  Future<Response<T>> _request<T>(
    String method,
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    final session = await _authenticator.validSession();
    if (session == null) {
      throw const OAuthException(
        'Sign in is required to access Solar Network.',
      );
    }
    return _dio.request<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: Options(
        method: method,
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      ),
    );
  }
}

/// Island-compatible API diagnostics. Credentials, bearer tokens, and request
/// or response bodies are intentionally never written to diagnostic logs.
Dio _createLoggedDio([BaseOptions? options]) {
  final dio = Dio(options);
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (request, handler) {
        Logger.root.fine('[API] ${request.method} ${request.uri}');
        handler.next(request);
      },
      onResponse: (response, handler) {
        Logger.root.fine(
          '[API] OK ${response.statusCode} '
          '${response.requestOptions.method} ${response.requestOptions.uri}',
        );
        handler.next(response);
      },
      onError: (error, handler) {
        Logger.root.warning(
          '[API] FAIL ${error.response?.statusCode ?? 'Network Error'} '
          '${error.requestOptions.method} ${error.requestOptions.uri}',
          error,
          error.stackTrace,
        );
        handler.next(error);
      },
    ),
  );
  return dio;
}

class Workspace {
  const Workspace({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
  });
  final String id;
  final String slug;
  final String name;
  final String? description;
  factory Workspace.fromJson(Map<String, dynamic> json) => Workspace(
    id: json['id']?.toString() ?? '',
    slug: json['slug']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Untitled workspace',
    description: json['description']?.toString(),
  );
}

class WorkspaceQuota {
  const WorkspaceQuota({required this.plan, required this.limits});
  final int plan;
  final Map<String, dynamic> limits;
  factory WorkspaceQuota.fromJson(Map<String, dynamic> json) => WorkspaceQuota(
    plan: (json['plan'] as num?)?.toInt() ?? 0,
    limits: Map<String, dynamic>.from(json['quotas'] as Map? ?? const {}),
  );
}

class Broad {
  const Broad({required this.id, required this.name, this.description});
  final String id;
  final String name;
  final String? description;
  factory Broad.fromJson(Map<String, dynamic> json) => Broad(
    id: json['id']?.toString() ?? '',
    name: (json['name'] ?? json['title'])?.toString() ?? 'Untitled board',
    description: json['description']?.toString(),
  );
}

final secureStorageProvider = Provider((ref) => const FlutterSecureStorage());
final authenticatorProvider = Provider(
  (ref) => SolarNetworkAuthenticator(ref.watch(secureStorageProvider)),
);
final wattEngineClientProvider = Provider(
  (ref) => WattEngineClient(ref.watch(authenticatorProvider)),
);
final authSessionProvider = FutureProvider<OAuthSession?>(
  (ref) => ref.watch(authenticatorProvider).validSession(),
);
final userInfoProvider = FutureProvider<OAuthUser?>((ref) async {
  final session = await ref.watch(authSessionProvider.future);
  if (session == null) return null;
  return ref.watch(authenticatorProvider).getUserInfo();
});
final workspacesProvider = FutureProvider<List<Workspace>>((ref) async {
  await ref.watch(authSessionProvider.future);
  return ref.watch(wattEngineClientProvider).listWorkspaces();
});
final broadsProvider = FutureProvider<List<Broad>>((ref) async {
  await ref.watch(authSessionProvider.future);
  return ref.watch(wattEngineClientProvider).listBroads();
});

/// Makes the shared Solar Network SDK available for service APIs that it
/// already models; the WattEngine routes above use the same bearer session.
final solarNetworkClientProvider = Provider<SolarNetworkClient>(
  (ref) => SolarNetworkClient(baseUrl: _issuer),
);
