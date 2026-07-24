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
    String? pictureId,
    String? backgroundId,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '/value/workspaces',
      data: {
        'slug': slug,
        'name': name,
        'description': description,
        'type': type,
        'picture_id': ?pictureId,
        'background_id': ?backgroundId,
      },
    );
    return Workspace.fromJson(response.data!);
  }

  Future<Workspace> updateWorkspace({
    required String slug,
    required String name,
    String? description,
    String? pictureId,
    bool updatePicture = false,
    String? backgroundId,
    bool updateBackground = false,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'PATCH',
      '/value/workspaces/$slug',
      data: {
        'name': name,
        'description': description,
        // Null clears the image when the backend treats null as clear.
        if (updatePicture) 'picture_id': pictureId,
        if (updateBackground) 'background_id': backgroundId,
      },
    );
    return Workspace.fromJson(response.data!);
  }

  Future<void> deleteWorkspace(String slug) =>
      _request<void>('DELETE', '/value/workspaces/$slug');

  Future<List<WorkspaceMember>> listWorkspaceMembers(String slug) async {
    final response = await _get<List<dynamic>>(
      '/value/workspaces/$slug/members',
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map(
          (item) => WorkspaceMember.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<WorkspaceMember> inviteWorkspaceMember({
    required String slug,
    required String accountId,
    required int role,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '/value/workspaces/$slug/members/invite',
      data: {'account_id': accountId, 'role': role},
    );
    return WorkspaceMember.fromJson(response.data!);
  }

  Future<WorkspaceMember> updateWorkspaceMemberRole({
    required String slug,
    required String accountId,
    required int role,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'PATCH',
      '/value/workspaces/$slug/members/$accountId',
      data: {'role': role},
    );
    return WorkspaceMember.fromJson(response.data!);
  }

  Future<void> removeWorkspaceMember({
    required String slug,
    required String accountId,
  }) => _request<void>('DELETE', '/value/workspaces/$slug/members/$accountId');

  Future<List<SnAccount>> searchAccounts(String query) async {
    if (query.trim().isEmpty) return const [];
    final response = await _get<List<dynamic>>(
      '/passport/accounts/search',
      queryParameters: {'query': query.trim()},
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => SnAccount.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

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
          : {'workspace_id': workspaceId},
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => Broad.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> createBroad({
    required String name,
    String? description,
    String? content,
    required String workspaceId,
    String? backgroundImageId,
    String? iconImageId,
    int visibility = 0,
  }) => _request<void>(
    'POST',
    '/ideask/broads',
    data: {
      'name': name,
      'description': description,
      'content': content ?? '',
      'visibility': visibility,
      'workspace_id': workspaceId,
      'background_image_id': ?backgroundImageId,
      'icon_image_id': ?iconImageId,
    },
  );

  Future<Broad> updateBroad({
    required String broadId,
    required String name,
    String? description,
    String? content,
    String? workspaceId,
    String? backgroundImageId,
    bool updateBackgroundImage = false,
    String? iconImageId,
    bool updateIconImage = false,
    int? visibility,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'PATCH',
      '/ideask/broads/$broadId',
      data: {
        'name': name,
        'description': description,
        'content': content,
        'workspace_id': ?workspaceId,
        'visibility': ?visibility,
        if (updateBackgroundImage) 'background_image_id': backgroundImageId,
        if (updateIconImage) 'icon_image_id': iconImageId,
      },
    );
    return Broad.fromJson(response.data!);
  }

  Future<List<WorkTask>> listTasks(String broadId) async {
    final response = await _get<List<dynamic>>('/ideask/broads/$broadId/tasks');
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => WorkTask.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<WorkTask> getTask(String taskId) async {
    final response = await _get<Map<String, dynamic>>('/ideask/tasks/$taskId');
    return WorkTask.fromJson(response.data ?? const {});
  }

  Future<WorkTask> createTask(String broadId, WorkTaskDraft task) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '/ideask/broads/$broadId/tasks',
      data: task.toCreateJson(),
    );
    return WorkTask.fromJson(response.data ?? const {});
  }

  Future<WorkTask> updateTask(String taskId, WorkTaskDraft task) async {
    final response = await _request<Map<String, dynamic>>(
      'PATCH',
      '/ideask/tasks/$taskId',
      data: task.toUpdateJson(),
    );
    return WorkTask.fromJson(response.data ?? const {});
  }

  Future<void> deleteTask(String taskId) =>
      _request<void>('DELETE', '/ideask/tasks/$taskId');

  Future<void> setTaskAssignees(
    String taskId,
    List<String> assigneeAccountIds,
  ) => _request<void>(
    'POST',
    '/ideask/tasks/$taskId/assignees',
    data: {'assignee_account_ids': assigneeAccountIds},
  );

  Future<void> unassignTask(String taskId, String assigneeAccountId) =>
      _request<void>(
        'DELETE',
        '/ideask/tasks/$taskId/assignees/$assigneeAccountId',
      );

  Future<List<TaskGroup>> listTaskGroups(String broadId) async {
    final response = await _get<List<dynamic>>(
      '/ideask/broads/$broadId/groups',
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => TaskGroup.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<TaskGroup> createTaskGroup(
    String broadId, {
    required String name,
    int? position,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '/ideask/broads/$broadId/groups',
      data: {'name': name, 'position': ?position},
    );
    return TaskGroup.fromJson(response.data ?? const {});
  }

  Future<TaskGroup> updateTaskGroup(
    String groupId, {
    required String name,
    int? position,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'PATCH',
      '/ideask/task-groups/$groupId',
      data: {'name': name, 'position': ?position},
    );
    return TaskGroup.fromJson(response.data ?? const {});
  }

  Future<void> deleteTaskGroup(String groupId) =>
      _request<void>('DELETE', '/ideask/task-groups/$groupId');

  /// Uploads a file via the Drive direct-upload endpoint (≤ ~20 MB).
  Future<SnCloudFile> uploadCloudFile({
    required List<int> bytes,
    required String fileName,
    String? contentType,
    String? usage,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final client = await _authenticatedSdk();
    try {
      return await client.drive.directUpload(
        fileBytes: bytes,
        fileName: fileName,
        contentType: contentType,
        usage: usage,
        onSendProgress: onSendProgress,
      );
    } finally {
      client.close();
    }
  }

  Future<SolarNetworkClient> _authenticatedSdk() async {
    final session = await _authenticator.validSession();
    if (session == null) {
      throw const OAuthException(
        'Sign in is required to access Solar Network.',
      );
    }
    final dio = _createLoggedDio(
      BaseOptions(
        baseUrl: _issuer,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 2),
        sendTimeout: const Duration(minutes: 5),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
        },
      ),
    );
    return SolarNetworkClient.fromDio(dio);
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
    this.type = 0,
    this.picture,
    this.background,
    this.plan = 0,
  });
  final String id;
  final String slug;
  final String name;
  final String? description;
  final int type;
  final SnCloudFileReference? picture;
  final SnCloudFileReference? background;
  final int plan;
  factory Workspace.fromJson(Map<String, dynamic> json) => Workspace(
    id: json['id']?.toString() ?? '',
    slug: json['slug']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Untitled workspace',
    description: json['description']?.toString(),
    type: (json['type'] as num?)?.toInt() ?? 0,
    picture: parseCloudFileReference(json['picture']),
    background: parseCloudFileReference(json['background']),
    plan: (json['plan'] as num?)?.toInt() ?? 0,
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

class WorkspaceMember {
  const WorkspaceMember({
    required this.id,
    required this.accountId,
    required this.role,
    this.displayName,
    this.username,
  });

  final String id;
  final String accountId;
  final int role;
  final String? displayName;
  final String? username;

  factory WorkspaceMember.fromJson(Map<String, dynamic> json) {
    final account = json['account'] as Map?;
    return WorkspaceMember(
      id: json['id']?.toString() ?? '',
      accountId: json['account_id']?.toString() ?? '',
      role: (json['role'] as num?)?.toInt() ?? 25,
      displayName:
          account?['nick']?.toString() ?? json['account_nick']?.toString(),
      username:
          account?['name']?.toString() ?? json['account_name']?.toString(),
    );
  }

  String get label =>
      displayName ??
      (username != null ? '@$username' : 'Account ${_shortId(accountId)}');
}

String _shortId(String id) => id.length > 8 ? id.substring(0, 8) : id;

class Broad {
  const Broad({
    required this.id,
    required this.name,
    this.description,
    this.content,
    this.workspaceId,
    this.visibility = 0,
    this.backgroundImage,
    this.iconImage,
  });
  final String id;
  final String name;
  final String? description;
  final String? content;
  final String? workspaceId;
  final int visibility;
  final SnCloudFileReference? backgroundImage;
  final SnCloudFileReference? iconImage;
  factory Broad.fromJson(Map<String, dynamic> json) => Broad(
    id: json['id']?.toString() ?? '',
    name: (json['name'] ?? json['title'])?.toString() ?? 'Untitled board',
    description: json['description']?.toString(),
    content: json['content']?.toString(),
    workspaceId: json['workspace_id']?.toString(),
    visibility: (json['visibility'] as num?)?.toInt() ?? 0,
    backgroundImage: parseCloudFileReference(json['background_image']),
    iconImage: parseCloudFileReference(json['icon_image']),
  );
}

class TaskGroup {
  const TaskGroup({
    required this.id,
    required this.name,
    required this.broadId,
    this.position = 0,
  });

  final String id;
  final String name;
  final String broadId;
  final int position;

  factory TaskGroup.fromJson(Map<String, dynamic> json) => TaskGroup(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Untitled group',
    broadId: json['broad_id']?.toString() ?? '',
    position: (json['position'] as num?)?.toInt() ?? 0,
  );
}

class TaskAssignee {
  const TaskAssignee({
    required this.id,
    required this.accountId,
    this.displayName,
    this.username,
  });

  final String id;
  final String accountId;
  final String? displayName;
  final String? username;

  String get label =>
      displayName ??
      (username != null ? '@$username' : 'Account ${_shortId(accountId)}');

  factory TaskAssignee.fromJson(Map<String, dynamic> json) {
    final account = json['account'] as Map?;
    return TaskAssignee(
      id: json['id']?.toString() ?? '',
      accountId: json['account_id']?.toString() ?? '',
      displayName:
          account?['nick']?.toString() ?? json['account_nick']?.toString(),
      username:
          account?['name']?.toString() ?? json['account_name']?.toString(),
    );
  }
}

class WorkTask {
  const WorkTask({
    required this.id,
    required this.name,
    this.description,
    this.content,
    this.attachments = const [],
    this.tags = const [],
    this.priority = 0,
    this.deadlineAt,
    this.completedAt,
    this.completeReason,
    this.broadId,
    this.parentTaskId,
    this.groupId,
    this.assignees = const [],
  });
  final String id;
  final String name;
  final String? description;
  final String? content;
  final List<SnCloudFileReference> attachments;
  final List<String> tags;
  final int priority;
  final DateTime? deadlineAt;
  final DateTime? completedAt;
  final int? completeReason;
  final String? broadId;
  final String? parentTaskId;
  final String? groupId;
  final List<TaskAssignee> assignees;

  bool get isCompleted => completedAt != null || completeReason != null;

  List<String> get assigneeAccountIds =>
      assignees.map((item) => item.accountId).toList(growable: false);

  WorkTask withGroupId(String? groupId) => WorkTask(
    id: id,
    name: name,
    description: description,
    content: content,
    attachments: attachments,
    tags: tags,
    priority: priority,
    deadlineAt: deadlineAt,
    completedAt: completedAt,
    completeReason: completeReason,
    broadId: broadId,
    parentTaskId: parentTaskId,
    groupId: groupId,
    assignees: assignees,
  );

  factory WorkTask.fromJson(Map<String, dynamic> json) => WorkTask(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Untitled task',
    description: json['description']?.toString(),
    content: json['content']?.toString(),
    attachments: parseCloudFileReferenceList(json['attachments']),
    tags: (json['tags'] as List?)
            ?.map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList() ??
        const [],
    priority: (json['priority'] as num?)?.toInt() ?? 0,
    deadlineAt: parseInstant(json['deadline_at']),
    completedAt: parseInstant(json['completed_at']),
    completeReason: (json['complete_reason'] as num?)?.toInt(),
    broadId: json['broad_id']?.toString(),
    parentTaskId: json['parent_task_id']?.toString(),
    groupId: json['group_id']?.toString(),
    assignees: (json['assignees'] as List?)
            ?.whereType<Map>()
            .map(
              (item) => TaskAssignee.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList() ??
        const [],
  );
}

class WorkTaskDraft {
  const WorkTaskDraft({
    required this.name,
    this.description,
    this.content,
    this.priority = 0,
    this.attachmentIds = const [],
    this.tags,
    this.deadlineAt,
    this.completeReason,
    this.groupId,
    this.ungroup,
    this.parentTaskId,
    this.assigneeAccountIds = const [],
  });
  final String name;
  final String? description;
  final String? content;
  final int priority;
  final List<String> attachmentIds;
  final List<String>? tags;
  final DateTime? deadlineAt;
  final int? completeReason;
  final String? groupId;
  final bool? ungroup;
  final String? parentTaskId;
  final List<String> assigneeAccountIds;

  Map<String, dynamic> toCreateJson() => {
    'name': name,
    'description': description,
    'content': content ?? '',
    'attachment_ids': attachmentIds,
    'priority': priority,
    'deadline_at': deadlineAt?.toUtc().toIso8601String(),
    'parent_task_id': parentTaskId,
    'assignee_account_ids': assigneeAccountIds,
    'group_id': ?groupId,
    'tags': ?tags,
  };

  Map<String, dynamic> toUpdateJson() => {
    'name': name,
    'description': description,
    'content': content,
    'attachment_ids': attachmentIds,
    'priority': priority,
    'deadline_at': deadlineAt?.toUtc().toIso8601String(),
    'complete_reason': ?completeReason,
    'group_id': ?groupId,
    if (ungroup == true) 'ungroup': true,
    'tags': ?tags,
  };
}

/// Resolves a display URL for a cloud file reference.
String cloudFileDisplayUrl(IDisplayableCloudFile file) =>
    file.storageUrl ?? '$_issuer/drive/files/${file.id}';

SnCloudFileReference? parseCloudFileReference(dynamic value) {
  if (value is! Map) return null;
  try {
    return SnCloudFileReference.fromJson(Map<String, dynamic>.from(value));
  } catch (_) {
    return null;
  }
}

List<SnCloudFileReference> parseCloudFileReferenceList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map(parseCloudFileReference)
      .whereType<SnCloudFileReference>()
      .toList(growable: false);
}

DateTime? parseInstant(dynamic value) {
  if (value == null) return null;
  if (value is num) {
    final n = value.toInt();
    // Heuristic: values beyond year ~2001 in ms are treated as milliseconds.
    if (n > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true).toLocal();
    }
    return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true).toLocal();
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}

/// Builds a lightweight [SnCloudFileReference] from a full [SnCloudFile]
/// (e.g. after a successful upload) for local UI state.
SnCloudFileReference cloudFileToReference(SnCloudFile file) =>
    SnCloudFileReference(
      id: file.id,
      name: file.name,
      mimeType: file.mimeType,
      storageUrl: file.storageUrl,
      size: file.size,
      hash: file.hash ?? '',
      fileMeta: file.fileMeta,
      userMeta: file.userMeta,
      sensitiveMarks: file.sensitiveMarks,
      width: file.width,
      height: file.height,
      blur: file.blurhash,
      usage: file.usage,
      applicationType: file.applicationType,
    );

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

final taskGroupsProvider = FutureProvider.family<List<TaskGroup>, String>(
  (ref, broadId) async =>
      ref.watch(wattEngineClientProvider).listTaskGroups(broadId),
);

/// Makes the shared Solar Network SDK available for service APIs that it
/// already models; the WattEngine routes above use the same bearer session.
final solarNetworkClientProvider = Provider<SolarNetworkClient>(
  (ref) => SolarNetworkClient(baseUrl: _issuer),
);
