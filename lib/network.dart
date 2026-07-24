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
  Future<SnAccount?> getCurrentAccount() async {
    final session = await validSession();
    if (session == null) return null;
    final dio = _createLoggedDio(
      BaseOptions(
        baseUrl: _issuer,
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      ),
    );
    final client = SolarNetworkClient.fromDio(dio);
    try {
      return await client.accounts.getCurrentAccount();
    } finally {
      client.close();
    }
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

extension SnAccountUi on SnAccount {
  String get solWattDisplayName => nick.isNotEmpty ? nick : '@$name';
  String? get solWattAvatarUrl {
    final picture = profilePicture;
    if (picture == null) return null;
    return picture.storageUrl ?? '$_issuer/drive/files/${picture.id}';
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

  Future<void> createBroad(
    String name,
    String? description,
    String workspaceId,
  ) => _request<void>(
    'POST',
    '/ideask/broads',
    data: {
      'name': name,
      'description': description,
      'content': '',
      'visibility': 0,
      'workspaceId': workspaceId,
    },
  );

  Future<List<WorkTask>> listTasks(String broadId) async {
    final response = await _get<List<dynamic>>('/ideask/broads/$broadId/tasks');
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => WorkTask.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> createTask(String broadId, WorkTaskDraft task) => _request<void>(
    'POST',
    '/ideask/broads/$broadId/tasks',
    data: task.toJson(),
  );

  Future<void> updateTask(String taskId, WorkTaskDraft task) =>
      _request<void>('PATCH', '/ideask/tasks/$taskId', data: task.toJson());

  Future<void> deleteTask(String taskId) =>
      _request<void>('DELETE', '/ideask/tasks/$taskId');

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
  const Broad({
    required this.id,
    required this.name,
    this.description,
    this.workspaceId,
  });
  final String id;
  final String name;
  final String? description;
  final String? workspaceId;
  factory Broad.fromJson(Map<String, dynamic> json) => Broad(
    id: json['id']?.toString() ?? '',
    name: (json['name'] ?? json['title'])?.toString() ?? 'Untitled board',
    description: json['description']?.toString(),
    workspaceId:
        json['workspaceId']?.toString() ?? json['workspace_id']?.toString(),
  );
}

class WorkTask {
  const WorkTask({
    required this.id,
    required this.name,
    this.description,
    this.priority = 0,
  });
  final String id;
  final String name;
  final String? description;
  final int priority;
  factory WorkTask.fromJson(Map<String, dynamic> json) => WorkTask(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Untitled task',
    description: json['description']?.toString(),
    priority: (json['priority'] as num?)?.toInt() ?? 0,
  );
}

class WorkTaskDraft {
  const WorkTaskDraft({
    required this.name,
    this.description,
    this.priority = 0,
  });
  final String name;
  final String? description;
  final int priority;
  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'content': '',
    'attachmentIds': const [],
    'priority': priority,
    'deadlineAt': null,
    'parentTaskId': null,
    'assigneeAccountIds': const [],
  };
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
final userInfoProvider = FutureProvider<SnAccount?>((ref) async {
  final session = await ref.watch(authSessionProvider.future);
  if (session == null) return null;
  return ref.watch(authenticatorProvider).getCurrentAccount();
});

const _selectedWorkspaceKey = 'selected_workspace_id';

/// Whether the user may use product features: signed in with an active workspace.
enum AppAccess { loading, needsSignIn, needsWorkspace, ready }

final appAccessProvider = Provider<AsyncValue<AppAccess>>((ref) {
  final session = ref.watch(authSessionProvider);
  return session.when(
    loading: () => const AsyncValue.loading(),
    error: AsyncValue.error,
    data: (value) {
      if (value == null) {
        return const AsyncValue.data(AppAccess.needsSignIn);
      }
      final workspace = ref.watch(selectedWorkspaceProvider);
      return workspace.when(
        loading: () => const AsyncValue.loading(),
        error: AsyncValue.error,
        data: (selected) => AsyncValue.data(
          selected == null ? AppAccess.needsWorkspace : AppAccess.ready,
        ),
      );
    },
  );
});

final selectedWorkspaceProvider = FutureProvider<Workspace?>((ref) async {
  final session = await ref.watch(authSessionProvider.future);
  if (session == null) return null;
  final id = await ref
      .watch(secureStorageProvider)
      .read(key: _selectedWorkspaceKey);
  if (id == null || id.isEmpty) return null;
  final workspaces = await ref.watch(wattEngineClientProvider).listWorkspaces();
  return workspaces.where((workspace) => workspace.id == id).firstOrNull;
});

Future<void> selectWorkspace(
  FlutterSecureStorage storage,
  Workspace workspace,
) => storage.write(key: _selectedWorkspaceKey, value: workspace.id);

Future<void> clearSelectedWorkspace(FlutterSecureStorage storage) =>
    storage.delete(key: _selectedWorkspaceKey);

/// Invalidates session-scoped providers after sign-in, sign-out, or workspace change.
void invalidateSessionScope(WidgetRef ref) {
  ref.invalidate(authSessionProvider);
  ref.invalidate(userInfoProvider);
  ref.invalidate(workspacesProvider);
  ref.invalidate(selectedWorkspaceProvider);
  ref.invalidate(broadsProvider);
}

void invalidateWorkspaceScope(WidgetRef ref) {
  ref.invalidate(selectedWorkspaceProvider);
  ref.invalidate(broadsProvider);
}

final workspacesProvider = FutureProvider<List<Workspace>>((ref) async {
  final session = await ref.watch(authSessionProvider.future);
  if (session == null) return const [];
  return ref.watch(wattEngineClientProvider).listWorkspaces();
});

final broadsProvider = FutureProvider<List<Broad>>((ref) async {
  final workspace = await ref.watch(selectedWorkspaceProvider.future);
  if (workspace == null) return const [];
  final broads = await ref
      .watch(wattEngineClientProvider)
      .listBroads(workspaceId: workspace.id);
  return broads
      .where(
        (broad) =>
            broad.workspaceId == null || broad.workspaceId == workspace.id,
      )
      .toList();
});

final tasksProvider = FutureProvider.family<List<WorkTask>, String>(
  (ref, broadId) async =>
      ref.watch(wattEngineClientProvider).listTasks(broadId),
);

/// Makes the shared Solar Network SDK available for service APIs that it
/// already models; the WattEngine routes above use the same bearer session.
final solarNetworkClientProvider = Provider<SolarNetworkClient>(
  (ref) => SolarNetworkClient(baseUrl: _issuer),
);
