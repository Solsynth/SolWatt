import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http_parser/http_parser.dart';
import 'package:logging/logging.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/mail/import/mail_import_service.dart';
import 'package:solwatt/mail/mail_address_suggestion.dart';

const _issuer = 'https://api.solian.app';
const _callbackScheme = 'solwatt';
const _redirectUri = '$_callbackScheme://oauth/callback';

/// The grant the web build signs in with: RFC 8628's device flow, which needs
/// no callback at all. A browser cannot hand the `solwatt` scheme back to a
/// page, and `flutter_web_auth_2` has nothing to listen for there, so the web
/// takes a code the user approves in a browser instead.
const _deviceCodeGrant = 'urn:ietf:params:oauth:grant-type:device_code';

/// Public OAuth client for SolWatt. This authorization-code flow uses PKCE and
/// never includes a client secret.
const _clientId = 'solarwatt';

/// Solar Network API base URL (gateway). Ring is exposed at `/ring/*`.
const kSolarNetworkApiBase = _issuer;

/// Product multi-tenant id for SolWatt.
///
/// Used for both:
/// - **Ring** notification `app` / `app_id` filtering
/// - **Blade wsgateway** connection `namespace` query param
///
/// Matches the native bundle / application id. Island uses
/// `dev.solsynth.solian` for the same pair of concerns. See
/// Blade `docs/WEBSOCKET_GATEWAY.md` and Island `kNotificationTenantAppId`.
const kProductTenantId = 'dev.solsynth.solarwatt';

/// Ring multi-tenant app id (alias of [kProductTenantId]).
const kNotificationTenantAppId = kProductTenantId;

/// Websocket gateway namespace (alias of [kProductTenantId]).
///
/// Connect with `GET /ws?namespace=…` so presence and pushes are isolated
/// from Solian and other clients on the shared gateway.
const kWebsocketNamespace = kProductTenantId;

/// ElecPostal API base path on the Solar Network gateway.
///
/// Local ElecPostal docs use `/api`, but production exposes the service at
/// `/postal` through the gateway.
const kElecPostalBase = '/postal';

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

/// What the user has to approve before a device sign-in can finish: the code,
/// and the page that takes it. [verificationUriComplete] carries the code in
/// the URL, so opening it saves typing it.
class DeviceAuthorization {
  const DeviceAuthorization({
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.expiresAt,
  });

  final String userCode;
  final Uri verificationUri;
  final Uri verificationUriComplete;
  final DateTime expiresAt;
}

class _OidcConfiguration {
  const _OidcConfiguration({
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.deviceAuthorizationEndpoint,
  });

  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;

  /// Where a device-flow sign-in asks for its code. Empty when the deployment
  /// does not offer one.
  final Uri deviceAuthorizationEndpoint;

  factory _OidcConfiguration.fromJson(Map<String, dynamic> json) =>
      _OidcConfiguration(
        authorizationEndpoint: Uri.parse(
          json['authorization_endpoint'] as String,
        ),
        tokenEndpoint: Uri.parse(json['token_endpoint'] as String),
        deviceAuthorizationEndpoint: Uri.parse(
          json['device_authorization_endpoint'] as String? ?? '',
        ),
      );
}

class SolarNetworkAuthenticator {
  SolarNetworkAuthenticator(
    this._storage, {
    bool? isWeb,
    Dio Function([BaseOptions?])? dioFactory,
  }) : _isWeb = isWeb ?? kIsWeb,
       _dioFactory = dioFactory ?? _createLoggedDio;

  static const _storageKey = 'solar_network_oauth_session';
  final FlutterSecureStorage _storage;

  /// Whether this build signs in with the device flow, which the web has to:
  /// nothing in a browser can hand the `solwatt` scheme back to the page.
  /// Injected rather than read from [kIsWeb] so a test can run either flow.
  final bool _isWeb;

  /// How the flow builds its clients. Injected so a test can answer the
  /// provider's endpoints without a network; the app uses the logging factory.
  final Dio Function([BaseOptions?]) _dioFactory;

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

  /// Signs in, returning the session.
  ///
  /// [onDeviceCode] is how the web build tells the user what to approve: the
  /// device flow has no callback to bounce through, so the provider hands out a
  /// code and this polls until the user has entered it in a browser. The other
  /// platforms open a browser window and never call it.
  Future<OAuthSession> signIn({
    void Function(DeviceAuthorization authorization)? onDeviceCode,
  }) => _isWeb ? _authorizeDevice(onDeviceCode) : _authorizeBrowser();

  /// The authorization-code flow: a browser window, a callback on the
  /// `solwatt` scheme, a PKCE verifier to prove the code is ours.
  Future<OAuthSession> _authorizeBrowser() async {
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
    final profile = await getCurrentProfile();
    return profile?.account;
  }

  /// Profile plus `perk_level` from the accounts/me payload.
  Future<SolWattProfile?> getCurrentProfile() async {
    final session = await validSession();
    if (session == null) return null;
    final dio = _dioFactory(
      BaseOptions(
        baseUrl: _issuer,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
        },
      ),
    );
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/stargate/accounts/me',
      );
      final data = response.data;
      if (data == null) return null;
      final account = SnAccount.fromJson(data);
      final perkLevel = parsePerkLevelFromAccountJson(data);
      return SolWattProfile(
        account: account,
        perkLevel: perkLevel > 0
            ? perkLevel
            : account.solWattPerkLevelFromSubscription,
      );
    } finally {
      dio.close();
    }
  }

  Future<_OidcConfiguration> _discover() async {
    final response = await _dioFactory().get<Map<String, dynamic>>(
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
    final response = await _dioFactory().post<Map<String, dynamic>>(
      endpoint.toString(),
      data: fields,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    return _sessionFrom(response.data ?? const <String, dynamic>{},
        previous: previous);
  }

  /// Signs in with RFC 8628's device flow: take a code, hand it to the user,
  /// poll the token endpoint until they have approved it in a browser.
  ///
  /// This is the web's flow, and the reason is the callback: nothing in a
  /// browser can hand the `solwatt` scheme back to the page, so there is no
  /// callback to wait for. A code the user types on their own screen needs
  /// none.
  Future<OAuthSession> _authorizeDevice(
    void Function(DeviceAuthorization authorization)? onDeviceCode,
  ) async {
    Logger.root.info('[OAuth] Starting device-code flow.');
    final configuration = await _discover();
    final endpoint = configuration.deviceAuthorizationEndpoint;
    if (!endpoint.hasScheme) {
      throw const OAuthException(
        'This Solar Network deployment does not offer device sign-in.',
      );
    }
    final response = await _dioFactory().post<Map<String, dynamic>>(
      endpoint.toString(),
      data: {'client_id': _clientId, 'scope': '*'},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final data = response.data ?? const <String, dynamic>{};
    final deviceCode = data['device_code'] as String? ?? '';
    final userCode = data['user_code'] as String? ?? '';
    final verificationUri = Uri.tryParse(
      data['verification_uri'] as String? ?? '',
    );
    if (deviceCode.isEmpty ||
        userCode.isEmpty ||
        verificationUri == null ||
        !verificationUri.hasScheme) {
      throw const OAuthException('Invalid device authorization response.');
    }
    // The provider may send a URI that carries the code, which saves the user
    // typing it. Where it does not, the code itself is the whole instruction.
    final completeUri = Uri.tryParse(
      data['verification_uri_complete'] as String? ?? '',
    );
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 600;
    final authorization = DeviceAuthorization(
      userCode: userCode,
      verificationUri: verificationUri,
      verificationUriComplete: completeUri != null && completeUri.hasScheme
          ? completeUri
          : verificationUri,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
    onDeviceCode?.call(authorization);
    final session = await _awaitDeviceApproval(
      configuration.tokenEndpoint,
      deviceCode,
      interval: (data['interval'] as num?)?.toInt() ?? 5,
      deadline: authorization.expiresAt,
    );
    await _save(session);
    Logger.root.info('[OAuth] Device authorization completed successfully.');
    return session;
  }

  /// Polls [tokenEndpoint] until the user has approved [deviceCode].
  ///
  /// RFC 8628's two "not yet" answers are not failures: `authorization_pending`
  /// means the user has not got there yet, `slow_down` means the provider wants
  /// the next poll further out. Anything else — approval, refusal, an expired
  /// code — is the answer, and the loop ends either way.
  Future<OAuthSession> _awaitDeviceApproval(
    Uri tokenEndpoint,
    String deviceCode, {
    required int interval,
    required DateTime deadline,
  }) async {
    var wait = interval;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(Duration(seconds: wait));
      Map<String, dynamic>? failure;
      try {
        final response = await _dioFactory().post<Map<String, dynamic>>(
          tokenEndpoint.toString(),
          data: {
            'grant_type': _deviceCodeGrant,
            'device_code': deviceCode,
            'client_id': _clientId,
          },
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
        return _sessionFrom(response.data ?? const <String, dynamic>{});
      } on DioException catch (error) {
        // A pending code is a 400 with a JSON body, which dio reports as a
        // failure; the body is what says whether to keep waiting.
        final body = error.response?.data;
        if (body is! Map) rethrow;
        failure = Map<String, dynamic>.from(body);
      }
      final error = failure['error']?.toString();
      if (error == 'authorization_pending') continue;
      if (error == 'slow_down') {
        wait += 5;
        continue;
      }
      if (error == 'expired_token') {
        throw const OAuthException(
          'The sign-in code expired before it was approved. Try again.',
        );
      }
      if (error == 'access_denied') {
        throw const OAuthException('The sign-in was declined.');
      }
      throw OAuthException(
        failure['error_description']?.toString() ??
            'Solar Network sign-in failed.',
      );
    }
    throw const OAuthException(
      'The sign-in code expired before it was approved. Try again.',
    );
  }

  /// The session a token response describes.
  OAuthSession _sessionFrom(
    Map<String, dynamic> data, {
    OAuthSession? previous,
  }) {
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

class FlywheelOwnerApp {
  const FlywheelOwnerApp({
    required this.appId,
    required this.retainedRevisionCount,
    required this.blobCount,
    required this.retainedRevisionCountTotal,
    required this.retainedBytes,
    required this.lastUpdatedAt,
  });

  final String appId;
  final int retainedRevisionCount;
  final int blobCount;
  final int retainedRevisionCountTotal;
  final int retainedBytes;
  final DateTime lastUpdatedAt;

  factory FlywheelOwnerApp.fromJson(Map<String, dynamic> json) =>
      FlywheelOwnerApp(
        appId: json['app_id'] as String? ?? '',
        retainedRevisionCount:
            (json['retained_revision_count'] as num?)?.toInt() ?? 0,
        blobCount: (json['blob_count'] as num?)?.toInt() ?? 0,
        retainedRevisionCountTotal:
            (json['retained_revision_count_total'] as num?)?.toInt() ?? 0,
        retainedBytes: (json['retained_bytes'] as num?)?.toInt() ?? 0,
        lastUpdatedAt:
            DateTime.tryParse(json['last_updated_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class FlywheelOwnerBlob {
  const FlywheelOwnerBlob({
    required this.blobId,
    required this.currentRevision,
    required this.retainedRevisionCount,
    required this.retainedBytes,
    required this.updatedAt,
  });

  final String blobId;
  final int currentRevision;
  final int retainedRevisionCount;
  final int retainedBytes;
  final DateTime updatedAt;

  factory FlywheelOwnerBlob.fromJson(Map<String, dynamic> json) =>
      FlywheelOwnerBlob(
        blobId: json['blob_id'] as String? ?? '',
        currentRevision: (json['current_revision'] as num?)?.toInt() ?? 0,
        retainedRevisionCount:
            (json['retained_revision_count'] as num?)?.toInt() ?? 0,
        retainedBytes: (json['retained_bytes'] as num?)?.toInt() ?? 0,
        updatedAt:
            DateTime.tryParse(json['updated_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class FlywheelAuditEntry {
  const FlywheelAuditEntry({
    required this.appId,
    required this.blobId,
    required this.revision,
    required this.action,
    required this.actorAccountId,
    required this.createdAt,
  });

  final String appId;
  final String? blobId;
  final int? revision;
  final String action;
  final String actorAccountId;
  final DateTime createdAt;

  factory FlywheelAuditEntry.fromJson(Map<String, dynamic> json) =>
      FlywheelAuditEntry(
        appId: json['app_id'] as String? ?? '',
        blobId: json['blob_id'] as String?,
        revision: (json['revision'] as num?)?.toInt(),
        action: json['action'] as String? ?? '',
        actorAccountId: json['actor_account_id'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

extension SnAccountUi on SnAccount {
  String get solWattDisplayName => nick.isNotEmpty ? nick : '@$name';
  String? get solWattAvatarUrl {
    final picture = profilePicture;
    if (picture == null) return null;
    return picture.storageUrl ?? '$_issuer/drive/files/${picture.id}';
  }

  /// Fallback perk level from stellar subscription identifier when the API
  /// field is missing from the SDK model.
  int get solWattPerkLevelFromSubscription =>
      perkLevelFromStellarIdentifier(perkSubscription?.identifier);
}

/// WattEngine requires perk level 3+ (Stellar Supernova) for bundled Pro on
/// the account's automatically provisioned individual workspace.
const bundledProRequiredPerkLevel = 3;

/// Signed-in account plus [perkLevel] from `/stargate/accounts/me`.
///
/// The SDK [SnAccount] model does not yet surface `perk_level`, so SolWatt
/// reads it from the raw profile payload (with identifier fallback).
class SolWattProfile {
  const SolWattProfile({required this.account, required this.perkLevel});

  final SnAccount account;
  final int perkLevel;

  bool get canAssignBundledPro => perkLevel >= bundledProRequiredPerkLevel;

  String get id => account.id;
  String get name => account.name;
  String get solWattDisplayName => account.solWattDisplayName;
  String? get solWattAvatarUrl => account.solWattAvatarUrl;
}

int perkLevelFromStellarIdentifier(String? identifier) => switch (identifier) {
  'solian.stellar.supernova' => 3,
  'solian.stellar.nova' => 2,
  'solian.stellar.primary' => 1,
  _ => 0,
};

int parsePerkLevelFromAccountJson(Map<String, dynamic> json) {
  final topLevel = (json['perk_level'] as num?)?.toInt();
  if (topLevel != null) return topLevel;
  final sub = json['perk_subscription'];
  if (sub is Map) {
    final subLevel = (sub['perk_level'] as num?)?.toInt();
    if (subLevel != null) return subLevel;
    return perkLevelFromStellarIdentifier(sub['identifier']?.toString());
  }
  return 0;
}

/// Account-level overview of the bundled Pro perk assignment.
class BundledProOverview {
  const BundledProOverview({
    required this.eligible,
    required this.perkLevel,
    this.bundled,
    this.assignedWorkspace,
  });

  final bool eligible;
  final int perkLevel;
  final BundledPlanInfo? bundled;
  final Workspace? assignedWorkspace;

  bool get isAssigned => bundled?.hasAssignment == true;

  /// Seats granted by the perk. Defaults to 1 until the API exposes a count.
  int get totalSeats {
    if (!eligible) return 0;
    final fromApi = bundled?.totalSeats;
    if (fromApi != null && fromApi > 0) return fromApi;
    return 1;
  }

  /// Seats currently in use. Falls back to a single assignment flag.
  int get usedSeats {
    if (!eligible) return 0;
    final fromApi = bundled?.usedSeats;
    if (fromApi != null) return fromApi.clamp(0, totalSeats);
    return isAssigned ? 1 : 0;
  }

  double get seatUsageRatio =>
      totalSeats > 0 ? (usedSeats / totalSeats).clamp(0.0, 1.0) : 0.0;
}

/// Authenticated client for WattEngine. Valve paths map to `/valve`; Ideask
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
    final response = await _get<List<dynamic>>('/valve/workspaces');
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
      '/valve/workspaces',
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
      '/valve/workspaces/$slug',
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
      _request<void>('DELETE', '/valve/workspaces/$slug');

  Future<List<WorkspaceMember>> listWorkspaceMembers(String slug) async {
    final response = await _get<List<dynamic>>(
      '/valve/workspaces/$slug/members',
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
      '/valve/workspaces/$slug/members/invite',
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
      '/valve/workspaces/$slug/members/$accountId',
      data: {'role': role},
    );
    return WorkspaceMember.fromJson(response.data!);
  }

  Future<void> removeWorkspaceMember({
    required String slug,
    required String accountId,
  }) => _request<void>('DELETE', '/valve/workspaces/$slug/members/$accountId');

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
      '/valve/workspaces/$slug/quota',
    );
    return WorkspaceQuota.fromJson(response.data ?? const {});
  }

  Future<WorkspacePlanStatus> getWorkspacePlanStatus(String slug) async {
    final response = await _get<Map<String, dynamic>>(
      '/valve/workspaces/$slug/plan/status',
    );
    return WorkspacePlanStatus.fromJson(response.data ?? const {});
  }

  Future<List<FlywheelOwnerApp>> listFlywheelApps(String workspaceId) async {
    final response = await _get<List<dynamic>>(
      '/flywheel/workspaces/$workspaceId/apps',
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map(
          (item) => FlywheelOwnerApp.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<List<FlywheelOwnerBlob>> listFlywheelBlobs(
    String workspaceId,
    String appId,
  ) async {
    final response = await _get<List<dynamic>>(
      '/flywheel/workspaces/$workspaceId/apps/$appId/management/blobs',
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map(
          (item) => FlywheelOwnerBlob.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<List<FlywheelAuditEntry>> listFlywheelAudit(
    String workspaceId,
    String appId,
  ) async {
    final response = await _get<List<dynamic>>(
      '/flywheel/workspaces/$workspaceId/apps/$appId/management/audit',
      queryParameters: const {'take': 100},
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              FlywheelAuditEntry.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<void> deleteFlywheelBlob(
    String workspaceId,
    String appId,
    String blobId,
  ) => _request<void>(
    'DELETE',
    '/flywheel/workspaces/$workspaceId/apps/$appId/management/blobs/$blobId',
  );

  /// Assigns (or reassigns) the caller's perk-bundled Pro plan to this workspace.
  /// Requires Owner and perk level 3+. Subject to a 7-day reassign cooldown.
  Future<void> assignBundledPlan(String slug) =>
      _request<void>('POST', '/valve/workspaces/$slug/plan/assign-bundled');

  Future<void> unassignBundledPlan(String slug) =>
      _request<void>('POST', '/valve/workspaces/$slug/plan/unassign-bundled');

  /// Creates a paid plan subscription order. Complete payment at
  /// [WorkspacePlanOrder.paymentUrl] (`https://solian.app/orders/{orderId}`).
  Future<WorkspacePlanOrder> subscribeWorkspacePlan({
    required String slug,
    required int plan,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '/valve/workspaces/$slug/plan/subscribe',
      data: {'plan': plan},
    );
    return WorkspacePlanOrder.fromJson(response.data ?? const {});
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

  Future<Broad> createBroad({
    required String name,
    String? description,
    String? content,
    required String workspaceId,
    String? backgroundImageId,
    String? iconImageId,
    int visibility = 0,
    String? taskPrefix,
  }) async {
    try {
      final response = await _request<Map<String, dynamic>>(
        'POST',
        '/ideask/broads',
        data: {
          'name': name,
          'content': content ?? '',
          'visibility': visibility,
          'workspace_id': workspaceId,
          'description': ?nonEmptyString(description),
          'background_image_id': ?backgroundImageId,
          'icon_image_id': ?iconImageId,
          'task_prefix': ?nonEmptyString(taskPrefix),
        },
      );
      final data = response.data;
      if (data == null) {
        // 201 with empty body — board still created; list will refresh.
        return Broad(
          id: '',
          name: name,
          description: description,
          content: content,
          workspaceId: workspaceId,
          visibility: visibility,
          taskPrefix: taskPrefix,
        );
      }
      return Broad.fromJson(data);
    } on DioException catch (error) {
      throw OAuthException(wattApiErrorMessage(error));
    }
  }

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
    String? taskPrefix,
    bool clearTaskPrefix = false,
  }) async {
    try {
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
          'task_prefix': ?taskPrefix,
          if (clearTaskPrefix) 'clear_task_prefix': true,
        },
      );
      return Broad.fromJson(response.data!);
    } on DioException catch (error) {
      throw OAuthException(wattApiErrorMessage(error));
    }
  }

  Future<void> deleteBroad(String broadId) =>
      _request<void>('DELETE', '/ideask/broads/$broadId');

  /// Deletes several boards in one request. Returns how many were removed.
  ///
  /// Server: `POST /ideask/broads/delete/batch` with `{ "broad_ids": [...] }`.
  /// All-or-nothing: a stale id fails the whole batch.
  Future<int> deleteBroads(List<String> broadIds) async {
    if (broadIds.isEmpty) return 0;
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '/ideask/broads/delete/batch',
      data: {'broad_ids': broadIds},
    );
    return (response.data?['count'] as num?)?.toInt() ?? broadIds.length;
  }

  /// Reassigns several boards to another workspace in one request. Returns how
  /// many were moved.
  ///
  /// Server: `POST /ideask/broads/move/batch` with
  /// `{ "broad_ids": [...], "workspace_id": "..." }`.
  Future<int> moveBroads(List<String> broadIds, String workspaceId) async {
    if (broadIds.isEmpty) return 0;
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '/ideask/broads/move/batch',
      data: {'broad_ids': broadIds, 'workspace_id': workspaceId},
    );
    return (response.data?['count'] as num?)?.toInt() ?? broadIds.length;
  }

  Future<List<WorkTask>> listTasks(
    String broadId, {
    TaskListFilters filters = const TaskListFilters(),
  }) async {
    final response = await _get<List<dynamic>>(
      '/ideask/broads/$broadId/tasks',
      queryParameters: filters.toQueryParameters(),
    );
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

  // --- Task comments -----------------------------------------------------------

  Future<List<TaskComment>> listTaskComments(String taskId) async {
    final response = await _get<List<dynamic>>(
      '/ideask/tasks/$taskId/comments',
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => TaskComment.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<TaskComment> createTaskComment(String taskId, String content) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '/ideask/tasks/$taskId/comments',
      data: {'content': content},
    );
    return TaskComment.fromJson(response.data ?? const {});
  }

  Future<TaskComment> updateTaskComment(
    String commentId,
    String content,
  ) async {
    final response = await _request<Map<String, dynamic>>(
      'PATCH',
      '/ideask/task-comments/$commentId',
      data: {'content': content},
    );
    return TaskComment.fromJson(response.data ?? const {});
  }

  Future<void> deleteTaskComment(String commentId) =>
      _request<void>('DELETE', '/ideask/task-comments/$commentId');

  // --- GitHub App integration --------------------------------------------------

  /// Returns a GitHub App installation URL for this board.
  Future<String> createGitHubInstallUrl(String broadId) async {
    final response = await _get<Map<String, dynamic>>(
      '/ideask/github/broads/$broadId/install-url',
    );
    final url = response.data?['url']?.toString();
    if (url == null || url.isEmpty) {
      throw const OAuthException('GitHub install URL was empty.');
    }
    return url;
  }

  /// Completed installation id after the user finishes GitHub setup.
  ///
  /// Returns null while installation is still incomplete (HTTP 404).
  Future<int?> getGitHubInstallation(String broadId) async {
    try {
      final response = await _get<Map<String, dynamic>>(
        '/ideask/github/broads/$broadId/installation',
      );
      final raw =
          response.data?['installation_id'] ?? response.data?['installationId'];
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '');
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<GitHubRepository>> listGitHubRepositories(
    String broadId,
    int installationId,
  ) async {
    final response = await _get<List<dynamic>>(
      '/ideask/github/broads/$broadId/installations/$installationId/repositories',
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map(
          (item) => GitHubRepository.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  /// Linked repository statuses for this board.
  Future<List<GitHubIntegration>> getGitHubIntegrations(String broadId) async {
    final response = await _get<List<dynamic>>(
      '/ideask/github/broads/$broadId',
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map(
          (item) => GitHubIntegration.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<GitHubIntegration> linkGitHubRepository({
    required String broadId,
    required int installationId,
    required String owner,
    required String repository,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '/ideask/github/broads/$broadId',
      data: {
        'installation_id': installationId,
        'owner': owner,
        'repository': repository,
      },
    );
    return GitHubIntegration.fromJson(response.data ?? const {});
  }

  Future<void> syncGitHubIntegration(String broadId) =>
      _request<void>('POST', '/ideask/github/broads/$broadId/sync');

  Future<void> unlinkGitHubIntegration(String integrationId) =>
      _request<void>('DELETE', '/ideask/github/integrations/$integrationId');

  // --- ElecPostal (Mail) -------------------------------------------------------

  Future<List<MailMailbox>> listMailboxes({String? workspaceId}) async {
    final response = await _get<List<dynamic>>(
      '$kElecPostalBase/mailboxes',
      queryParameters: workspaceId == null
          ? null
          : {'workspace_id': workspaceId},
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => MailMailbox.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<MailMailbox> createMailbox({
    required String address,
    String? workspaceId,
    String? name,
    bool isDefault = false,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '$kElecPostalBase/mailboxes',
      data: {
        'address': address,
        'is_default': isDefault,
        if (workspaceId != null && workspaceId.isNotEmpty)
          'workspace_id': workspaceId,
        'name': nonEmptyString(name),
      },
    );
    return MailMailbox.fromJson(response.data!);
  }

  Future<MailEmail> getEmail(String emailId) async {
    final response = await _get<Map<String, dynamic>>(
      '$kElecPostalBase/emails/$emailId',
    );
    return MailEmail.fromJson(response.data ?? const {});
  }

  /// Conversation summaries, newest activity first.
  ///
  /// A mailbox scopes the query to that address
  /// (`GET /postal/mailboxes/{id}/threads`); an empty [mailboxId] asks the
  /// account-wide route (`GET /postal/threads`), which is how a search covers
  /// every mailbox. Counts cover every message of a conversation, not just the
  /// ones on the fetched page.
  Future<PaginatedResult<MailThread>> listThreads(
    String? mailboxId, {
    String? folder,
    String? q,
    String? status,
    bool? isFlagged,
    String? from,
    String? to,
    bool? hasAttachments,
    int offset = 0,
    int take = 20,
  }) async {
    final path = mailboxId == null || mailboxId.isEmpty
        ? '$kElecPostalBase/threads'
        : '$kElecPostalBase/mailboxes/${Uri.encodeComponent(mailboxId)}/threads';
    return _parseThreadPage(
      await _get<List<dynamic>>(
        path,
        queryParameters: {
          'offset': offset,
          'take': take,
          if (folder != null && folder.isNotEmpty) 'folder': folder,
          if (q != null && q.isNotEmpty) 'q': q,
          if (status != null && status.isNotEmpty) 'status': status,
          'is_flagged': ?isFlagged,
          if (from != null && from.isNotEmpty) 'from': from,
          if (to != null && to.isNotEmpty) 'to': to,
          'has_attachments': ?hasAttachments,
        },
      ),
    );
  }

  /// Every message of one conversation, oldest first, with full bodies.
  Future<List<MailEmail>> getThread(String threadId) async {
    final response = await _get<List<dynamic>>(
      '$kElecPostalBase/threads/${Uri.encodeComponent(threadId)}',
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => MailEmail.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  /// Downloads a freshly serialized `.eml` (message/rfc822) for an email.
  /// The endpoint streams it from stored metadata and DysonFS attachment
  /// bytes rather than relying on saved original message bytes.
  Future<Uint8List> downloadEmailEml(String emailId) async {
    final session = await _authenticator.validSession();
    if (session == null) {
      throw const OAuthException(
        'Sign in is required to access Solar Network.',
      );
    }
    final response = await _dio.request<List<int>>(
      '$kElecPostalBase/emails/$emailId/eml',
      options: Options(
        method: 'GET',
        responseType: ResponseType.bytes,
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Accept': 'message/rfc822',
        },
      ),
    );
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw StateError('Empty EML response for email $emailId.');
    }
    return Uint8List.fromList(data);
  }

  /// Resolves the authenticated Drive URL to its storage redirect. HTML
  /// webviews cannot attach the app's bearer token to image subrequests, so
  /// inline email images use the returned signed URL instead.
  Future<String> resolveCloudFileUrl(
    String fileId, {
    String? workspaceId,
  }) async {
    final session = await _authenticator.validSession();
    if (session == null) {
      throw const OAuthException(
        'Sign in is required to access Solar Network.',
      );
    }
    final response = await _dio.get<String>(
      '/drive/files/${Uri.encodeComponent(fileId)}',
      queryParameters: {
        if (workspaceId != null && workspaceId.trim().isNotEmpty)
          'workspace_id': workspaceId.trim(),
      },
      options: Options(
        followRedirects: false,
        responseType: ResponseType.plain,
        validateStatus: (status) => status != null && status < 400,
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Accept': '*/*',
        },
      ),
    );
    final location = response.headers.value('location');
    if (location == null || location.isEmpty) {
      throw StateError('Drive did not return a storage redirect for $fileId.');
    }
    return response.requestOptions.uri.resolve(location).toString();
  }

  Future<List<MailAddressSuggestion>> listSenders({
    String query = '',
    int take = 20,
  }) => _listAddressSuggestions('senders', query: query, take: take);

  Future<List<MailAddressSuggestion>> listContacts({
    String query = '',
    int take = 20,
  }) => _listAddressSuggestions('contacts', query: query, take: take);

  Future<List<MailAddressSuggestion>> _listAddressSuggestions(
    String kind, {
    required String query,
    required int take,
  }) async {
    final response = await _get<List<dynamic>>(
      '$kElecPostalBase/addresses/$kind',
      queryParameters: {'q': query, 'take': take},
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              MailAddressSuggestion.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  Future<MailEmail> sendEmail({
    required String mailboxId,
    required List<MailRecipient> to,
    List<MailRecipient> cc = const [],
    List<MailRecipient> bcc = const [],
    required String subject,
    required String body,
    List<String> attachmentIds = const [],
    bool isDraft = false,
    String contentType = 'text/plain',
    String? replyToId,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '$kElecPostalBase/emails',
      data: {
        'mailbox_id': mailboxId,
        'to': to.map((r) => r.toJson()).toList(),
        'cc': cc.map((r) => r.toJson()).toList(),
        'bcc': bcc.map((r) => r.toJson()).toList(),
        'subject': subject,
        'body': body,
        'attachment_ids': attachmentIds,
        'is_draft': isDraft,
        'content_type': contentType,
        if (replyToId != null && replyToId.isNotEmpty) 'reply_to_id': replyToId,
      },
    );
    return MailEmail.fromJson(response.data!);
  }

  /// Imports one batch (≤500 items) of parsed mail into the per-item
  /// mailboxes' INBOXes. Items mirror the ElecPostal import contract; see
  /// `MailImportService` for parsing and chunking. With [dedupe] (default),
  /// repeated `message_id` values within a mailbox are skipped by the server.
  Future<MailImportResult> importEmails({
    required List<Map<String, dynamic>> items,
    bool dedupe = true,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '$kElecPostalBase/import',
      data: {'emails': items, 'dedupe': dedupe ? 'message_id' : 'off'},
    );
    return MailImportResult.fromJson(response.data ?? const {});
  }

  Future<void> deleteEmail(String emailId) =>
      _request<void>('DELETE', '$kElecPostalBase/emails/$emailId');

  /// Removes a message and its stored attachment bytes for good. This is the
  /// only way out of Trash; it cannot be undone.
  Future<void> deleteEmailPermanently(String emailId) => _request<void>(
    'DELETE',
    '$kElecPostalBase/emails/${Uri.encodeComponent(emailId)}/permanent',
  );

  /// Permanently deletes every message the mailbox keeps in Trash and returns
  /// how many went away.
  Future<int> emptyTrash(String mailboxId) async {
    final response = await _request<Map<String, dynamic>>(
      'DELETE',
      '$kElecPostalBase/mailboxes/${Uri.encodeComponent(mailboxId)}/trash',
    );
    return (response.data?['deleted'] as num?)?.toInt() ?? 0;
  }

  /// Moves a message to another folder
  /// (`inbox`, `sent`, `drafts`, `spam`, `trash`, `archive`).
  Future<void> moveEmail(String emailId, String folder) => _request<void>(
    'POST',
    '$kElecPostalBase/emails/$emailId/move',
    data: {'folder': folder},
  );

  Future<void> starEmail(String emailId, {required bool starred}) =>
      _request<void>(
        'POST',
        '$kElecPostalBase/emails/$emailId/${starred ? 'star' : 'unstar'}',
      );

  /// Unread count of a mailbox's Inbox, read from the `X-Total` header of a
  /// single-item filtered query (the stats endpoint is not folder-filtered).
  Future<int> listUnreadInboxCount(String mailboxId) async {
    final response = await _get<List<dynamic>>(
      '$kElecPostalBase/emails',
      queryParameters: {
        'mailbox_id': mailboxId,
        'folder': 'inbox',
        'is_read': 'false',
        'take': '1',
      },
    );
    return int.tryParse(
          response.headers.value('x-total') ??
              response.headers.value('X-Total') ??
              '',
        ) ??
        0;
  }

  Future<MailEmail> resendEmail(String emailId) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '$kElecPostalBase/emails/$emailId/resend',
    );
    return MailEmail.fromJson(response.data ?? const {});
  }

  Future<void> markEmailRead(String emailId) =>
      _request<void>('POST', '$kElecPostalBase/emails/$emailId/read');

  Future<void> markEmailUnread(String emailId) =>
      _request<void>('POST', '$kElecPostalBase/emails/$emailId/unread');

  Future<List<MailCredential>> listMailCredentials() async {
    final response = await _get<List<dynamic>>('$kElecPostalBase/credentials');
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => MailCredential.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<MailCredentialCreated> createMailCredential({
    required String mailboxId,
    required String label,
    List<String> protocols = const ['smtp', 'imap'],
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '$kElecPostalBase/credentials',
      data: {'mailbox_id': mailboxId, 'label': label, 'protocols': protocols},
    );
    return MailCredentialCreated.fromJson(response.data!);
  }

  Future<void> revokeMailCredential(String credentialId) =>
      _request<void>('DELETE', '$kElecPostalBase/credentials/$credentialId');

  Future<String> getMailHost() async {
    final response = await _get<Map<String, dynamic>>(
      '$kElecPostalBase/mail/host',
    );
    return (response.data?['host'] as String?)?.trim() ?? '';
  }

  // --- Mailbox settings: aliases, forwarding, quota -------------------------

  Future<List<MailAlias>> listMailboxAliases(String mailboxId) async {
    final response = await _get<List<dynamic>>(
      '$kElecPostalBase/mailboxes/$mailboxId/aliases',
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => MailAlias.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<MailAlias> createMailboxAlias({
    required String mailboxId,
    required String customDomainId,
    required String localPart,
    String? name,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '$kElecPostalBase/mailboxes/$mailboxId/aliases',
      data: {
        'custom_domain_id': customDomainId,
        'local_part': localPart,
        if (name != null && name.trim().isNotEmpty) 'name': name,
      },
    );
    return MailAlias.fromJson(response.data!);
  }

  Future<void> deleteMailboxAlias(String mailboxId, String aliasId) =>
      _request<void>(
        'DELETE',
        '$kElecPostalBase/mailboxes/$mailboxId/aliases/$aliasId',
      );

  Future<List<MailForwarding>> listMailForwardings(String mailboxId) async {
    final response = await _get<List<dynamic>>(
      '$kElecPostalBase/mailboxes/$mailboxId/forwarding',
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map(
          (item) => MailForwarding.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<MailForwarding> createMailForwarding({
    required String mailboxId,
    required String aliasId,
    required String destination,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '$kElecPostalBase/mailboxes/$mailboxId/forwarding',
      data: {'alias_id': aliasId, 'destination': destination},
    );
    return MailForwarding.fromJson(response.data!);
  }

  Future<void> deleteMailForwarding(String mailboxId, String forwardingId) =>
      _request<void>(
        'DELETE',
        '$kElecPostalBase/mailboxes/$mailboxId/forwarding/$forwardingId',
      );

  Future<MailboxQuota> getMailboxQuota(String mailboxId) async {
    final response = await _get<Map<String, dynamic>>(
      '$kElecPostalBase/mailboxes/$mailboxId/quota',
    );
    return MailboxQuota.fromJson(response.data ?? const {});
  }

  // --- Blocklist and notification preferences -------------------------------

  Future<List<MailBlockRule>> listBlockRules() async {
    final response = await _get<List<dynamic>>('$kElecPostalBase/blocklist');
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => MailBlockRule.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<MailBlockRule> createBlockRule({
    required String scope,
    String? workspaceId,
    String? mailboxId,
    required String pattern,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '$kElecPostalBase/blocklist',
      data: {
        'scope': scope,
        if (workspaceId != null && workspaceId.isNotEmpty)
          'workspace_id': workspaceId,
        if (mailboxId != null && mailboxId.isNotEmpty)
          'mailbox_id': mailboxId,
        'pattern': pattern,
      },
    );
    return MailBlockRule.fromJson(response.data!);
  }

  Future<void> deleteBlockRule(String ruleId) =>
      _request<void>('DELETE', '$kElecPostalBase/blocklist/$ruleId');

  Future<MailNotificationSettings> getNotificationSettings() async {
    final response = await _get<Map<String, dynamic>>(
      '$kElecPostalBase/settings/notifications',
    );
    return MailNotificationSettings.fromJson(response.data ?? const {});
  }

  Future<MailNotificationSettings> updateNotificationSettings({
    bool? highlight,
    bool? summarize,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'PATCH',
      '$kElecPostalBase/settings/notifications',
      data: {
        'highlight': ?highlight,
        'summarize': ?summarize,
      },
    );
    return MailNotificationSettings.fromJson(response.data ?? const {});
  }

  Future<List<MailCustomDomain>> listCustomDomains({
    required String workspaceId,
  }) async {
    final response = await _get<List<dynamic>>(
      '$kElecPostalBase/custom-domains',
      queryParameters: {'workspace_id': workspaceId},
    );
    return (response.data ?? const [])
        .whereType<Map>()
        .map(
          (item) => MailCustomDomain.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<MailCustomDomain> createCustomDomain({
    required String workspaceId,
    required String domain,
  }) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '$kElecPostalBase/custom-domains',
      data: {'workspace_id': workspaceId, 'domain': domain},
    );
    return MailCustomDomain.fromJson(response.data ?? const {});
  }

  /// Re-runs DNS verification for one custom domain and returns its state.
  Future<MailCustomDomain> refreshCustomDomain(String domainId) async {
    final response = await _request<Map<String, dynamic>>(
      'POST',
      '$kElecPostalBase/custom-domains/$domainId/refresh',
    );
    return MailCustomDomain.fromJson(response.data ?? const {});
  }

  /// Storage pooled across the workspace's mailboxes.
  Future<MailUsageSummary> getWorkspaceMailboxUsage(String workspaceId) async {
    final response = await _get<Map<String, dynamic>>(
      '$kElecPostalBase/workspaces/$workspaceId/mailbox-usage',
    );
    return MailUsageSummary.fromJson(response.data ?? const {});
  }

  /// Messages the workspace has sent today and this month.
  Future<MailSendUsage> getWorkspaceSendUsage(String workspaceId) async {
    final response = await _get<Map<String, dynamic>>(
      '$kElecPostalBase/workspaces/$workspaceId/send-usage',
    );
    return MailSendUsage.fromJson(response.data ?? const {});
  }

  PaginatedResult<MailThread> _parseThreadPage(
    Response<List<dynamic>> response,
  ) {
    final totalHeader =
        response.headers.value('x-total') ??
        response.headers.value('X-Total') ??
        '0';
    final totalCount = int.tryParse(totalHeader) ?? 0;
    final items = (response.data ?? const [])
        .whereType<Map>()
        .map((item) => MailThread.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    return PaginatedResult(items: items, totalCount: totalCount);
  }

  /// Uploads a file to **workspace** Drive (≤ ~20 MB).
  ///
  /// SolWatt only manages workspace files — [workspaceId] is required. DysonFS
  /// must have `[workspace] target` configured (see WORKSPACE_FILES.md).
  Future<SnCloudFile> uploadCloudFile({
    required List<int> bytes,
    required String fileName,
    required String workspaceId,
    String? contentType,
    String? usage,
    String? parentId,
    bool indexed = true,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final ws = workspaceId.trim();
    if (ws.isEmpty) {
      throw const OAuthException(
        'A workspace is required. SolWatt only stores files on workspace Drive.',
      );
    }
    final client = await _authenticatedSdk();
    try {
      try {
        return await _postDirectUpload(
          client,
          bytes: bytes,
          fileName: fileName,
          contentType: contentType,
          usage: usage,
          workspaceId: ws,
          parentId: parentId,
          indexed: indexed,
          onSendProgress: onSendProgress,
        );
      } on DioException catch (error) {
        throw OAuthException(driveApiErrorMessage(error));
      }
    } finally {
      client.close();
    }
  }

  Future<SnCloudFile> _postDirectUpload(
    SolarNetworkClient client, {
    required List<int> bytes,
    required String fileName,
    String? contentType,
    String? usage,
    String? workspaceId,
    String? parentId,
    bool indexed = false,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final resolvedName = fileName.trim().isEmpty
        ? 'upload.bin'
        : fileName.trim();
    final resolvedType = (contentType != null && contentType.trim().isNotEmpty)
        ? contentType.trim()
        : _guessContentType(resolvedName);

    MediaType? multipartContentType;
    try {
      multipartContentType = MediaType.parse(resolvedType);
    } catch (_) {
      multipartContentType = MediaType('application', 'octet-stream');
    }

    // Mirror Island's drive_service.uploadFileDirect payload shape.
    // DysonFS reads: FormFile("file"), PostForm parent_id / workspace_id /
    // usage / index (bool string via optionalBool).
    final payload = <String, dynamic>{
      'file': MultipartFile.fromBytes(
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        filename: resolvedName,
        contentType: multipartContentType,
      ),
      if (usage != null && usage.isNotEmpty) 'usage': usage,
      if (workspaceId != null && workspaceId.isNotEmpty)
        'workspace_id': workspaceId,
      if (parentId != null && parentId.isNotEmpty) 'parent_id': parentId,
      // Only send when true — default on the server is false.
      if (indexed) 'index': 'true',
    };

    final response = await client.dio.post<dynamic>(
      '/drive/files/upload/direct',
      data: FormData.fromMap(payload),
      onSendProgress: onSendProgress,
      options: Options(
        sendTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 5),
      ),
    );

    return _parseUploadedCloudFile(response.data);
  }

  SnCloudFile _parseUploadedCloudFile(dynamic raw) {
    if (raw is! Map) {
      throw const OAuthException('Unexpected upload response payload.');
    }
    final payload = Map<String, dynamic>.from(raw);

    final directFile = payload['file'];
    if (directFile is Map) {
      return SnCloudFile.fromJson(Map<String, dynamic>.from(directFile));
    }
    final fileInfo = payload['file_info'];
    if (fileInfo is Map) {
      return SnCloudFile.fromJson(Map<String, dynamic>.from(fileInfo));
    }
    final nested = payload['data'];
    if (nested is Map) {
      final nestedFile = nested['file'];
      if (nestedFile is Map) {
        return SnCloudFile.fromJson(Map<String, dynamic>.from(nestedFile));
      }
      if (nested['id'] != null) {
        return SnCloudFile.fromJson(Map<String, dynamic>.from(nested));
      }
    }
    if (payload['id'] != null) {
      return SnCloudFile.fromJson(payload);
    }
    throw const OAuthException('Unable to parse uploaded file response.');
  }

  /// Creates a **workspace** folder. [workspaceId] is required — SolWatt does
  /// not manage personal Drive folders.
  ///
  /// FileSystem returns **403** when `CheckWorkspaceUploadQuota` fails
  /// (workspace gRPC not configured, not a member, quota, etc.).
  Future<SnCloudFile> createCloudFolder({
    required String name,
    required String workspaceId,
    String? parentId,
  }) async {
    final ws = workspaceId.trim();
    if (ws.isEmpty) {
      throw const OAuthException(
        'A workspace is required. SolWatt only stores folders on workspace Drive.',
      );
    }
    final client = await _authenticatedSdk();
    try {
      try {
        final response = await client.dio.post<dynamic>(
          '/drive/files/folders',
          data: {'name': name, 'workspace_id': ws, 'parent_id': ?parentId},
        );
        final raw = response.data;
        if (raw is! Map) {
          throw const OAuthException('Unexpected create-folder response.');
        }
        return SnCloudFile.fromJson(Map<String, dynamic>.from(raw));
      } on DioException catch (error) {
        throw OAuthException(driveApiErrorMessage(error));
      }
    } finally {
      client.close();
    }
  }

  /// Lists files owned by the signed-in user (Drive `/files/me`).
  ///
  /// When [workspaceId] is set, DysonFS returns that workspace's owned files
  /// (membership-checked) instead of personal files.
  Future<PaginatedResult<DriveFileEntry>> listMyCloudFiles({
    int offset = 0,
    int take = 40,
    String? query,
    bool recycled = false,
    String? workspaceId,
  }) async {
    final client = await _authenticatedSdk();
    try {
      final response = await client.dio.get<List<dynamic>>(
        '/drive/files/me',
        queryParameters: {
          'offset': offset,
          'take': take,
          'recycled': recycled,
          if (query != null && query.isNotEmpty) 'query': query,
          if (workspaceId != null && workspaceId.isNotEmpty)
            'workspace_id': workspaceId,
        },
      );
      return _parseDrivePage(response);
    } finally {
      client.close();
    }
  }

  /// Lists **indexed** children at Drive root or under [parentId].
  ///
  /// Passes [workspaceId] so DysonFS returns the workspace hierarchy rather
  /// than personal Drive. For unindexed workspace files (logos, backgrounds),
  /// use [listUnindexedCloudFiles].
  Future<PaginatedResult<DriveFileEntry>> listCloudFolderChildren({
    String? parentId,
    required String workspaceId,
    int offset = 0,
    int take = 50,
    String? query,
    String? order,
    bool orderDesc = false,
    bool? isFolder,
    String? contentType,
  }) async {
    final ws = workspaceId.trim();
    if (ws.isEmpty) {
      throw const OAuthException(
        'A workspace is required. SolWatt only browses workspace Drive.',
      );
    }
    final client = await _authenticatedSdk();
    try {
      final path = parentId == null || parentId.isEmpty
          ? '/drive/files/root/children'
          : '/drive/files/$parentId/children';
      final response = await client.dio.get<List<dynamic>>(
        path,
        queryParameters: {
          'offset': offset,
          'take': take,
          'workspace_id': ws,
          'orderDesc': orderDesc,
          if (query != null && query.isNotEmpty) 'query': query,
          if (order != null && order.isNotEmpty) 'order': order,
          'is_folder': ?isFolder,
          if (contentType != null && contentType.isNotEmpty)
            'content_type': contentType,
        },
      );
      return _parseDrivePage(response);
    } finally {
      client.close();
    }
  }

  /// Lists **unindexed** workspace files (flat list — no folder hierarchy).
  ///
  /// Used for assets such as board icons/backgrounds that should not appear
  /// in the folder tree. Server: `GET /drive/files/unindexed?workspace_id=…`.
  Future<PaginatedResult<DriveFileEntry>> listUnindexedCloudFiles({
    required String workspaceId,
    int offset = 0,
    int take = 50,
    String? query,
    bool recycled = false,
    String? order,
    bool orderDesc = true,
    String? contentType,
  }) async {
    final ws = workspaceId.trim();
    if (ws.isEmpty) {
      throw const OAuthException(
        'A workspace is required. SolWatt only browses workspace Drive.',
      );
    }
    final client = await _authenticatedSdk();
    try {
      final response = await client.dio.get<List<dynamic>>(
        '/drive/files/unindexed',
        queryParameters: {
          'offset': offset,
          'take': take,
          'workspace_id': ws,
          'recycled': recycled,
          'orderDesc': orderDesc,
          if (query != null && query.isNotEmpty) 'query': query,
          if (order != null && order.isNotEmpty) 'order': order,
          if (contentType != null && contentType.isNotEmpty)
            'content_type': contentType,
        },
      );
      return _parseDrivePage(response);
    } finally {
      client.close();
    }
  }

  /// Live workspace storage usage from DysonFS
  /// (`GET /drive/billing/workspaces/:id/quota`).
  Future<WorkspaceDriveUsage> getWorkspaceDriveUsage(String workspaceId) async {
    final ws = workspaceId.trim();
    if (ws.isEmpty) {
      throw const OAuthException('Workspace id is required for storage usage.');
    }
    final client = await _authenticatedSdk();
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/drive/billing/workspaces/$ws/quota',
      );
      return WorkspaceDriveUsage.fromJson(response.data ?? const {});
    } on DioException catch (error) {
      throw OAuthException(driveApiErrorMessage(error));
    } finally {
      client.close();
    }
  }

  Future<SnCloudFile> getCloudFileInfo(String fileId) async {
    final client = await _authenticatedSdk();
    try {
      return await client.drive.getFileInfo(fileId);
    } finally {
      client.close();
    }
  }

  Future<void> deleteCloudFile(String fileId) async {
    final client = await _authenticatedSdk();
    try {
      await client.drive.deleteFile(fileId);
    } finally {
      client.close();
    }
  }

  Future<SnCloudFile> renameCloudFile(String fileId, String name) async {
    final client = await _authenticatedSdk();
    try {
      return await client.drive.updateFileName(fileId, name);
    } finally {
      client.close();
    }
  }

  PaginatedResult<DriveFileEntry> _parseDrivePage(
    Response<List<dynamic>> response,
  ) {
    final totalHeader =
        response.headers.value('x-total') ??
        response.headers.value('X-Total') ??
        '0';
    final totalCount = int.tryParse(totalHeader) ?? 0;
    final items = (response.data ?? const [])
        .whereType<Map>()
        .map((item) => DriveFileEntry.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    return PaginatedResult(items: items, totalCount: totalCount);
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

/// Workspace plan tiers from WattEngine.Valve (`WorkspacePlan`).
abstract final class WorkspacePlanTier {
  static const free = 0;
  static const pro = 1;
  static const enterprise = 2;

  static String nameOf(int plan) => switch (plan) {
    free => 'Free',
    pro => 'Pro',
    enterprise => 'Enterprise',
    _ => 'Plan $plan',
  };
}

class Workspace {
  const Workspace({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
    this.type = WorkspaceType.individual,
    this.ownerAccountId,
    this.picture,
    this.background,
    this.plan = 0,
    this.planExpiresAt,
    this.isBundled = false,
  });
  final String id;
  final String slug;
  final String name;
  final String? description;
  final int type;
  final String? ownerAccountId;
  final SnCloudFileReference? picture;
  final SnCloudFileReference? background;
  final int plan;
  final DateTime? planExpiresAt;
  final bool isBundled;

  String get planName => WorkspacePlanTier.nameOf(plan);
  bool get isIndividual => type == WorkspaceType.individual;
  bool get isOrganization => type == WorkspaceType.organization;
  String get typeName => isIndividual ? 'Individual' : 'Organization';

  factory Workspace.fromJson(Map<String, dynamic> json) => Workspace(
    id: json['id']?.toString() ?? '',
    slug: json['slug']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Untitled workspace',
    description: json['description']?.toString(),
    type: _parseOptionalInt(json['type']) ?? 0,
    ownerAccountId: (json['owner_account_id'] ?? json['ownerAccountId'])
        ?.toString(),
    picture: parseCloudFileReference(json['picture']),
    background: parseCloudFileReference(json['background']),
    plan: _parseOptionalInt(json['plan']) ?? 0,
    planExpiresAt: _parseOptionalDateTime(
      json['plan_expires_at'] ?? json['planExpiresAt'],
    ),
    isBundled: json['is_bundled'] == true || json['isBundled'] == true,
  );
}

abstract final class WorkspaceType {
  static const individual = 0;
  static const organization = 1;
}

/// [SnCloudFile] plus the optional `workspace_id` field that the SDK model
/// does not yet surface. Used for workspace-scoped Drive browsing.
class DriveFileEntry {
  const DriveFileEntry({required this.file, this.workspaceId});

  final SnCloudFile file;
  final String? workspaceId;

  String get id => file.id;
  String get name => file.name;
  bool get isFolder => file.isFolder;
  int get size => file.size;
  String get mimeType => file.mimeType;
  String? get parentId => file.parentId;
  String? get storageUrl => file.storageUrl;

  bool belongsToWorkspace(String workspaceId) =>
      this.workspaceId != null && this.workspaceId == workspaceId;

  factory DriveFileEntry.fromJson(Map<String, dynamic> json) {
    final workspaceRaw = json['workspace_id']?.toString();
    return DriveFileEntry(
      file: SnCloudFile.fromJson(json),
      workspaceId: (workspaceRaw == null || workspaceRaw.isEmpty)
          ? null
          : workspaceRaw,
    );
  }
}

class WorkspaceQuota {
  const WorkspaceQuota({required this.plan, required this.limits});
  final int plan;
  final Map<String, dynamic> limits;

  String get planName => WorkspacePlanTier.nameOf(plan);

  /// Plan storage cap in bytes (`max_storage_bytes`), if present.
  int? get maxStorageBytes {
    final raw = limits['max_storage_bytes'];
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  factory WorkspaceQuota.fromJson(Map<String, dynamic> json) => WorkspaceQuota(
    plan: _parseOptionalInt(json['plan']) ?? 0,
    limits: Map<String, dynamic>.from(json['quotas'] as Map? ?? const {}),
  );
}

/// Live storage usage for a workspace from DysonFS billing.
///
/// Distinct from [WorkspaceQuota] (WattEngine plan limits). This is the
/// actual used/total storage charged to the workspace plan.
class WorkspaceDriveUsage {
  const WorkspaceDriveUsage({
    required this.workspaceId,
    required this.usedBytes,
    required this.totalBytes,
    required this.remainingBytes,
    required this.totalFileCount,
  });

  final String workspaceId;
  final int usedBytes;
  final int totalBytes;
  final int remainingBytes;
  final int totalFileCount;

  double get usageRatio =>
      totalBytes > 0 ? (usedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  factory WorkspaceDriveUsage.fromJson(Map<String, dynamic> json) =>
      WorkspaceDriveUsage(
        workspaceId: json['workspace_id']?.toString() ?? '',
        usedBytes: _parseOptionalInt(json['used_bytes']) ?? 0,
        totalBytes: _parseOptionalInt(json['total_bytes']) ?? 0,
        remainingBytes: _parseOptionalInt(json['remaining_bytes']) ?? 0,
        totalFileCount: _parseOptionalInt(json['total_file_count']) ?? 0,
      );
}

/// Account-level bundled Pro perk assignment info from `GET …/plan/status`.
///
/// Seat counts are optional for forward-compat: today the perk grants one free
/// Pro workspace; when more bundled seats are added the API can surface
/// `total_seats` / `used_seats` without a UI rewrite.
class BundledPlanInfo {
  const BundledPlanInfo({
    required this.isEnabled,
    this.workspaceId,
    this.lastReassignedAt,
    this.cooldownActive = false,
    this.totalSeats,
    this.usedSeats,
  });

  final bool isEnabled;
  final String? workspaceId;
  final DateTime? lastReassignedAt;
  final bool cooldownActive;

  /// Total bundled Pro seats granted to the account, when the API provides it.
  final int? totalSeats;

  /// Seats currently assigned, when the API provides it.
  final int? usedSeats;

  bool get hasAssignment =>
      isEnabled && workspaceId != null && workspaceId!.isNotEmpty;

  factory BundledPlanInfo.fromJson(Map<String, dynamic> json) =>
      BundledPlanInfo(
        isEnabled: json['is_enabled'] == true || json['isEnabled'] == true,
        workspaceId: (json['workspace_id'] ?? json['workspaceId'])?.toString(),
        lastReassignedAt: _parseOptionalDateTime(
          json['last_reassigned_at'] ?? json['lastReassignedAt'],
        ),
        cooldownActive:
            json['cooldown_active'] == true || json['cooldownActive'] == true,
        totalSeats: _parseOptionalInt(
          json['total_seats'] ?? json['totalSeats'],
        ),
        usedSeats: _parseOptionalInt(json['used_seats'] ?? json['usedSeats']),
      );
}

class WorkspacePlanPrices {
  const WorkspacePlanPrices({
    required this.pro,
    required this.enterprise,
    this.currency = 'golds',
  });

  final num pro;
  final num enterprise;
  final String currency;

  factory WorkspacePlanPrices.fromJson(Map<String, dynamic> json) =>
      WorkspacePlanPrices(
        pro: _parseOptionalNum(json['pro']) ?? 0,
        enterprise: _parseOptionalNum(json['enterprise']) ?? 0,
        currency: json['currency']?.toString() ?? 'golds',
      );
}

class WorkspacePlanStatus {
  const WorkspacePlanStatus({
    required this.plan,
    this.planExpiresAt,
    this.isBundled = false,
    this.bundledPlan,
    this.prices,
  });

  final int plan;
  final DateTime? planExpiresAt;
  final bool isBundled;
  final BundledPlanInfo? bundledPlan;
  final WorkspacePlanPrices? prices;

  String get planName => WorkspacePlanTier.nameOf(plan);

  factory WorkspacePlanStatus.fromJson(Map<String, dynamic> json) {
    final bundledRaw = json['bundled_plan'] ?? json['bundledPlan'];
    final pricesRaw = json['prices'];
    return WorkspacePlanStatus(
      plan: _parseOptionalInt(json['plan']) ?? 0,
      planExpiresAt: _parseOptionalDateTime(
        json['plan_expires_at'] ?? json['planExpiresAt'],
      ),
      isBundled: json['is_bundled'] == true || json['isBundled'] == true,
      bundledPlan: bundledRaw is Map
          ? BundledPlanInfo.fromJson(Map<String, dynamic>.from(bundledRaw))
          : null,
      prices: pricesRaw is Map
          ? WorkspacePlanPrices.fromJson(Map<String, dynamic>.from(pricesRaw))
          : null,
    );
  }
}

/// Paid plan order created by `POST …/plan/subscribe`.
class WorkspacePlanOrder {
  const WorkspacePlanOrder({
    required this.orderId,
    required this.amount,
    required this.currency,
    required this.plan,
  });

  final String orderId;
  final num amount;
  final String currency;
  final int plan;

  String get planName => WorkspacePlanTier.nameOf(plan);

  /// Solian checkout for this order.
  Uri get paymentUrl => Uri.parse('https://solian.app/orders/$orderId');

  factory WorkspacePlanOrder.fromJson(Map<String, dynamic> json) =>
      WorkspacePlanOrder(
        orderId: json['order_id']?.toString() ?? '',
        amount: _parseOptionalNum(json['amount']) ?? 0,
        currency: json['currency']?.toString() ?? 'golds',
        plan: _parseOptionalInt(json['plan']) ?? 0,
      );
}

DateTime? _parseOptionalDateTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}

/// Accepts JSON numbers or numeric strings (APIs sometimes serialize amounts
/// as strings). Returns null when missing or non-numeric.
num? _parseOptionalNum(Object? value) {
  if (value == null) return null;
  if (value is num) return value;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return num.tryParse(text);
}

int? _parseOptionalInt(Object? value) => _parseOptionalNum(value)?.toInt();

/// Best-effort human message from a WattEngine (or other gateway) API error.
String wattApiErrorMessage(Object error) {
  if (error is OAuthException) return error.message;
  if (error is DioException) {
    final data = error.response?.data;
    final fromBody = _messageFromResponseData(data);
    if (fromBody != null) return fromBody;
    final status = error.response?.statusCode;
    if (status != null) {
      return 'Request failed (HTTP $status).';
    }
    return error.message ?? 'Network request failed.';
  }
  return error.toString();
}

String? _messageFromResponseData(Object? data) {
  if (data == null) return null;
  if (data is String) {
    final trimmed = data.trim();
    if (trimmed.isEmpty) return null;
    // ASP.NET often returns a JSON-encoded string: `"error text"`.
    if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is String && decoded.trim().isNotEmpty) {
          return decoded.trim();
        }
      } catch (_) {}
    }
    return trimmed;
  }
  if (data is List && data.isNotEmpty) {
    // ASP.NET validation errors can be a list of strings.
    final first = data.first;
    if (first is String && first.trim().isNotEmpty) return first.trim();
  }
  if (data is Map) {
    final errors = data['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final parts = <String>[];
      for (final entry in errors.entries) {
        final value = entry.value;
        if (value is List) {
          for (final item in value) {
            final text = item.toString().trim();
            if (text.isNotEmpty) parts.add(text);
          }
        } else {
          final text = value.toString().trim();
          if (text.isNotEmpty) parts.add(text);
        }
      }
      if (parts.isNotEmpty) return parts.join(' ');
    }
    final message =
        data['error'] ??
        data['message'] ??
        data['detail'] ??
        data['title'] ??
        data['Message'];
    if (message != null && message.toString().trim().isNotEmpty) {
      return message.toString().trim();
    }
  }
  return null;
}

class WorkspaceMember {
  const WorkspaceMember({
    required this.id,
    required this.accountId,
    required this.role,
    this.account,
    this.profilePicture,
    this.fallbackNick,
    this.fallbackUsername,
    this.joinedAt,
  });

  final String id;
  final String accountId;
  final int role;

  /// Populated by Valve `LoadMemberAccounts` (`SnAccount?` on the wire).
  final SnAccount? account;

  /// Profile picture from [account] or a partial account payload.
  final SnCloudFileReference? profilePicture;
  final String? fallbackNick;
  final String? fallbackUsername;
  final DateTime? joinedAt;

  String? get displayName {
    final account = this.account;
    if (account != null) return account.solWattDisplayName;
    final nick = fallbackNick?.trim();
    if (nick != null && nick.isNotEmpty) return nick;
    final username = fallbackUsername?.trim();
    if (username != null && username.isNotEmpty) return '@$username';
    return null;
  }

  String? get username => account?.name ?? fallbackUsername;

  /// Best-available profile picture reference for avatars.
  SnCloudFileReference? get picture =>
      profilePicture ?? account?.profilePicture;

  String? get avatarUrl {
    final file = picture;
    if (file == null) return null;
    return cloudFileDisplayUrl(file);
  }

  String get label => displayName ?? 'Account ${_shortId(accountId)}';

  String get subtitleHandle {
    final name = username;
    if (name != null && name.isNotEmpty) return '@$name';
    return accountId;
  }

  String get initial {
    final source = displayName ?? username ?? accountId;
    if (source.isEmpty) return '?';
    return source[0].toUpperCase();
  }

  factory WorkspaceMember.fromJson(Map<String, dynamic> json) {
    final accountRaw = json['account'];
    SnAccount? account;
    SnCloudFileReference? picture;
    String? fallbackNick;
    String? fallbackUsername;
    String? accountIdFromAccount;

    if (accountRaw is Map) {
      final map = Map<String, dynamic>.from(accountRaw);
      accountIdFromAccount = map['id']?.toString();
      fallbackNick = map['nick']?.toString();
      fallbackUsername = map['name']?.toString();
      final profileRaw = map['profile'];
      if (profileRaw is Map) {
        picture = parseCloudFileReference(profileRaw['picture']);
      }
      try {
        account = SnAccount.fromJson(map);
        picture ??= account.profilePicture;
      } catch (_) {
        // gRPC-populated accounts can omit fields the SDK model requires.
        // Keep nick/username/picture from the partial payload.
      }
    }

    final accountId =
        json['account_id']?.toString() ??
        account?.id ??
        accountIdFromAccount ??
        '';
    return WorkspaceMember(
      id: json['id']?.toString() ?? '',
      accountId: accountId,
      role: (json['role'] as num?)?.toInt() ?? 25,
      account: account,
      profilePicture: picture,
      fallbackNick: fallbackNick,
      fallbackUsername: fallbackUsername,
      joinedAt: _parseOptionalDateTime(json['joined_at'] ?? json['JoinedAt']),
    );
  }
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
    this.taskPrefix,
    this.backgroundImage,
    this.iconImage,
  });
  final String id;
  final String name;
  final String? description;
  final String? content;
  final String? workspaceId;
  final int visibility;
  final String? taskPrefix;
  final SnCloudFileReference? backgroundImage;
  final SnCloudFileReference? iconImage;
  factory Broad.fromJson(Map<String, dynamic> json) => Broad(
    id: json['id']?.toString() ?? '',
    name: (json['name'] ?? json['title'])?.toString() ?? 'Untitled board',
    description: nonEmptyString(json['description']?.toString()),
    content: nonEmptyString(json['content']?.toString()),
    workspaceId: json['workspace_id']?.toString(),
    visibility: (json['visibility'] as num?)?.toInt() ?? 0,
    taskPrefix: nonEmptyString(json['task_prefix']?.toString()),
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

/// Server-side filters accepted by a board's task list endpoint.
class TaskListFilters {
  const TaskListFilters({
    this.search,
    this.status,
    this.priority,
    this.groupId,
    this.ungrouped,
    this.assigneeAccountId,
    this.tag,
    this.deadlineFrom,
    this.deadlineTo,
  }) : assert(groupId == null || ungrouped != true);

  final String? search;
  final TaskStatus? status;
  final int? priority;
  final String? groupId;
  final bool? ungrouped;
  final String? assigneeAccountId;
  final String? tag;
  final DateTime? deadlineFrom;
  final DateTime? deadlineTo;

  bool get isEmpty =>
      search == null &&
      status == null &&
      priority == null &&
      groupId == null &&
      ungrouped != true &&
      assigneeAccountId == null &&
      tag == null &&
      deadlineFrom == null &&
      deadlineTo == null;

  Map<String, dynamic> toQueryParameters() => {
    if (search?.trim().isNotEmpty == true) 'search': search!.trim(),
    if (status != null) 'status': status!.apiValue,
    if (priority != null) 'priority': priority,
    if (groupId?.isNotEmpty == true) 'groupId': groupId,
    if (ungrouped == true) 'ungrouped': true,
    if (assigneeAccountId?.trim().isNotEmpty == true)
      'assigneeAccountId': assigneeAccountId!.trim(),
    if (tag?.trim().isNotEmpty == true) 'tag': tag!.trim(),
    if (deadlineFrom != null)
      'deadlineFrom': deadlineFrom!.toUtc().toIso8601String(),
    if (deadlineTo != null) 'deadlineTo': deadlineTo!.toUtc().toIso8601String(),
  };

  TaskListFilters copyWith({
    String? search,
    TaskStatus? status,
    int? priority,
    String? groupId,
    bool? ungrouped,
    String? assigneeAccountId,
    String? tag,
    DateTime? deadlineFrom,
    DateTime? deadlineTo,
    bool clearSearch = false,
    bool clearStatus = false,
    bool clearPriority = false,
    bool clearGroup = false,
    bool clearAssigneeAccountId = false,
    bool clearTag = false,
    bool clearDeadlineFrom = false,
    bool clearDeadlineTo = false,
  }) => TaskListFilters(
    search: clearSearch ? null : search ?? this.search,
    status: clearStatus ? null : status ?? this.status,
    priority: clearPriority ? null : priority ?? this.priority,
    groupId: clearGroup ? null : groupId ?? this.groupId,
    ungrouped: clearGroup ? null : ungrouped ?? this.ungrouped,
    assigneeAccountId: clearAssigneeAccountId
        ? null
        : assigneeAccountId ?? this.assigneeAccountId,
    tag: clearTag ? null : tag ?? this.tag,
    deadlineFrom: clearDeadlineFrom ? null : deadlineFrom ?? this.deadlineFrom,
    deadlineTo: clearDeadlineTo ? null : deadlineTo ?? this.deadlineTo,
  );

  @override
  bool operator ==(Object other) =>
      other is TaskListFilters &&
      other.search == search &&
      other.status == status &&
      other.priority == priority &&
      other.groupId == groupId &&
      other.ungrouped == ungrouped &&
      other.assigneeAccountId == assigneeAccountId &&
      other.tag == tag &&
      other.deadlineFrom == deadlineFrom &&
      other.deadlineTo == deadlineTo;

  @override
  int get hashCode => Object.hash(
    search,
    status,
    priority,
    groupId,
    ungrouped,
    assigneeAccountId,
    tag,
    deadlineFrom,
    deadlineTo,
  );
}

enum TaskStatus {
  open('Open'),
  completed('Completed'),
  skipped('Skipped'),
  duplicated('Duplicated');

  const TaskStatus(this.apiValue);
  final String apiValue;
}

class TaskListRequest {
  const TaskListRequest({
    required this.broadId,
    this.filters = const TaskListFilters(),
  });

  final String broadId;
  final TaskListFilters filters;

  @override
  bool operator ==(Object other) =>
      other is TaskListRequest &&
      other.broadId == broadId &&
      other.filters == filters;

  @override
  int get hashCode => Object.hash(broadId, filters);
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
    this.serialNumber,
    this.taskKey,
    this.deadlineAt,
    this.completedAt,
    this.completeReason,
    this.broadId,
    this.parentTaskId,
    this.groupId,
    this.assignees = const [],
    this.gitHubIssue,
  });
  final String id;
  final String name;
  final String? description;
  final String? content;
  final List<SnCloudFileReference> attachments;
  final List<String> tags;
  final int priority;
  final int? serialNumber;
  final String? taskKey;
  final DateTime? deadlineAt;
  final DateTime? completedAt;
  final int? completeReason;
  final String? broadId;
  final String? parentTaskId;
  final String? groupId;
  final List<TaskAssignee> assignees;
  final GitHubIssueLink? gitHubIssue;

  bool get isCompleted => completedAt != null || completeReason != null;

  /// Non-blank description for list/card UI (empty string counts as absent).
  String? get displayDescription => nonEmptyString(description);

  /// Non-blank rich content for detail UI (empty string counts as absent).
  String? get displayContent => nonEmptyString(content);

  bool get hasDescription => displayDescription != null;
  bool get hasContent => displayContent != null;
  bool get isLinkedToGitHub => gitHubIssue != null;
  String? get displayKey => taskKey ?? serialNumber?.toString();

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
    serialNumber: serialNumber,
    taskKey: taskKey,
    deadlineAt: deadlineAt,
    completedAt: completedAt,
    completeReason: completeReason,
    broadId: broadId,
    parentTaskId: parentTaskId,
    groupId: groupId,
    assignees: assignees,
    gitHubIssue: gitHubIssue,
  );

  /// Copy with the completion flag flipped, timestamped when first completed.
  /// The pushed detail screen owns its task copy, so it can show the toggle
  /// before the round trip; [withGroupId] mirrors the same fields.
  WorkTask withCompletion(bool completed) => WorkTask(
    id: id,
    name: name,
    description: description,
    content: content,
    attachments: attachments,
    tags: tags,
    priority: priority,
    serialNumber: serialNumber,
    taskKey: taskKey,
    deadlineAt: deadlineAt,
    completedAt: completed ? (completedAt ?? DateTime.now()) : null,
    completeReason: completed ? (completeReason ?? 0) : null,
    broadId: broadId,
    parentTaskId: parentTaskId,
    groupId: groupId,
    assignees: assignees,
    gitHubIssue: gitHubIssue,
  );

  factory WorkTask.fromJson(Map<String, dynamic> json) {
    final issueRaw = json['git_hub_issue'] ?? json['github_issue'];
    return WorkTask(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled task',
      description: nonEmptyString(json['description']?.toString()),
      content: nonEmptyString(json['content']?.toString()),
      attachments: parseCloudFileReferenceList(json['attachments']),
      tags:
          (json['tags'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList() ??
          const [],
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      serialNumber: (json['serial_number'] as num?)?.toInt(),
      taskKey: nonEmptyString(
        (json['task_key'] ?? json['taskKey'])?.toString(),
      ),
      deadlineAt: parseInstant(json['deadline_at']),
      completedAt: parseInstant(json['completed_at']),
      completeReason: (json['complete_reason'] as num?)?.toInt(),
      broadId: json['broad_id']?.toString(),
      parentTaskId: json['parent_task_id']?.toString(),
      groupId: json['group_id']?.toString(),
      assignees:
          (json['assignees'] as List?)
              ?.whereType<Map>()
              .map(
                (item) =>
                    TaskAssignee.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList() ??
          const [],
      gitHubIssue: issueRaw is Map
          ? GitHubIssueLink.fromJson(Map<String, dynamic>.from(issueRaw))
          : null,
    );
  }
}

/// Link between an Ideask task and a GitHub issue.
class GitHubIssueLink {
  const GitHubIssueLink({
    required this.issueNumber,
    required this.htmlUrl,
    this.gitHubIssueId,
    this.isPullRequest = false,
    this.repositoryFullName,
  });

  final int issueNumber;
  final String htmlUrl;
  final int? gitHubIssueId;
  final bool isPullRequest;
  final String? repositoryFullName;

  String? get resolvedRepositoryFullName {
    if (repositoryFullName?.isNotEmpty == true) return repositoryFullName;
    final uri = Uri.tryParse(htmlUrl);
    if (uri == null ||
        uri.host != 'github.com' ||
        uri.pathSegments.length < 2) {
      return null;
    }
    return '${uri.pathSegments[0]}/${uri.pathSegments[1]}';
  }

  String get reference => resolvedRepositoryFullName != null
      ? '$resolvedRepositoryFullName#$issueNumber'
      : '#$issueNumber';
  String get kindLabel => isPullRequest ? 'PR' : 'Issue';
  String get label => '$reference $kindLabel';

  factory GitHubIssueLink.fromJson(Map<String, dynamic> json) =>
      GitHubIssueLink(
        issueNumber: (json['issue_number'] as num?)?.toInt() ?? 0,
        htmlUrl: json['html_url']?.toString() ?? '',
        gitHubIssueId: (json['git_hub_issue_id'] as num?)?.toInt(),
        isPullRequest: json['is_pull_request'] == true,
        repositoryFullName: nonEmptyString(
          (json['repository_full_name'] ?? json['repositoryFullName'])
              ?.toString(),
        ),
      );
}

/// Board ↔ repository GitHub App integration status.
class GitHubIntegration {
  const GitHubIntegration({
    required this.id,
    required this.broadId,
    required this.installationId,
    required this.owner,
    required this.repository,
    this.gitHubRepositoryId,
    this.lastSyncedAt,
    this.lastError,
  });

  final String id;
  final String broadId;
  final int installationId;
  final String owner;
  final String repository;
  final int? gitHubRepositoryId;
  final DateTime? lastSyncedAt;
  final String? lastError;

  String get fullName => '$owner/$repository';

  factory GitHubIntegration.fromJson(Map<String, dynamic> json) =>
      GitHubIntegration(
        id: json['id']?.toString() ?? '',
        broadId: json['broad_id']?.toString() ?? '',
        installationId: (json['installation_id'] as num?)?.toInt() ?? 0,
        owner: json['owner']?.toString() ?? '',
        repository: json['repository']?.toString() ?? '',
        gitHubRepositoryId: (json['git_hub_repository_id'] as num?)?.toInt(),
        lastSyncedAt: parseInstant(json['last_synced_at']),
        lastError: nonEmptyString(json['last_error']?.toString()),
      );
}

/// Repository available to a GitHub App installation.
class GitHubRepository {
  const GitHubRepository({
    required this.id,
    required this.fullName,
    required this.owner,
    required this.name,
    this.htmlUrl,
  });

  final int id;
  final String fullName;
  final String owner;
  final String name;
  final String? htmlUrl;

  factory GitHubRepository.fromJson(Map<String, dynamic> json) {
    final owner = json['owner']?.toString() ?? '';
    final name = json['name']?.toString() ?? '';
    final fullName = json['full_name']?.toString();
    return GitHubRepository(
      id: (json['id'] as num?)?.toInt() ?? 0,
      fullName: (fullName != null && fullName.isNotEmpty)
          ? fullName
          : (owner.isEmpty ? name : '$owner/$name'),
      owner: owner,
      name: name,
      htmlUrl: nonEmptyString(json['html_url']?.toString()),
    );
  }
}

/// Task comment (local or mirrored from GitHub).
// --- ElecPostal mail models --------------------------------------------------

class MailMailbox {
  const MailMailbox({
    required this.id,
    required this.accountId,
    required this.address,
    this.workspaceId,
    this.name,
    this.isDefault = false,
    this.isVerified = false,
  });

  final String id;
  final String accountId;
  final String? workspaceId;
  final String address;
  final String? name;
  final bool isDefault;
  final bool isVerified;

  String get displayName => name?.trim().isNotEmpty == true ? name! : address;

  /// Returns the full email address for display. When [mailHost] is provided
  /// and the stored address is local-only, the host is appended.
  String fullAddress(String? mailHost) {
    final local = address.trim().toLowerCase();
    final host = mailHost?.trim().toLowerCase() ?? '';
    if (local.isEmpty || host.isEmpty || local.contains('@')) return local;
    return '$local@$host';
  }

  factory MailMailbox.fromJson(Map<String, dynamic> json) => MailMailbox(
    id: json['id']?.toString() ?? '',
    accountId: json['account_id']?.toString() ?? '',
    workspaceId: json['workspace_id']?.toString(),
    address: json['address']?.toString() ?? '',
    name: nonEmptyString(json['name']?.toString()),
    isDefault: json['is_default'] == true,
    isVerified: json['is_verified'] == true,
  );
}

class MailRecipient {
  const MailRecipient({required this.address, this.name, this.kind = 'to'});

  final String address;
  final String? name;
  final String kind;

  String get displayName => name?.trim().isNotEmpty == true ? name! : address;

  /// Returns the full email address for display. When [mailHost] is provided
  /// and the stored address is local-only, the host is appended.
  String fullAddress(String? mailHost) {
    final local = address.trim().toLowerCase();
    final host = mailHost?.trim().toLowerCase() ?? '';
    if (local.isEmpty || host.isEmpty || local.contains('@')) return local;
    return '$local@$host';
  }

  Map<String, dynamic> toJson() => {
    'address': address,
    if (name != null && name!.isNotEmpty) 'name': name,
    'kind': kind,
  };

  factory MailRecipient.fromJson(Map<String, dynamic> json) => MailRecipient(
    address: json['address']?.toString() ?? '',
    name: nonEmptyString(json['name']?.toString()),
    kind: json['kind']?.toString() ?? 'to',
  );
}

class MailEmail {
  const MailEmail({
    required this.id,
    required this.mailboxId,
    required this.subject,
    required this.body,
    required this.isDraft,
    this.threadId,
    this.messageId,
    this.contentType,
    this.from,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.attachments = const [],
    this.inlineAttachments = const {},
    this.isRead = false,
    this.isStarred = false,
    this.folder,
    this.createdAt,
    this.mailbox,
    this.deliveryStatus,
    this.deliveryAttempts = 0,
    this.lastDeliveryAttemptAt,
    this.deliveryError,
    this.providerMessageId,
    this.summary,
  });

  final String id;
  final String mailboxId;
  final MailMailbox? mailbox;

  /// Conversation this message belongs to. ElecPostal assigns every message a
  /// thread, so this is null only for payloads that predate threading.
  final String? threadId;

  /// RFC 5322 `Message-ID` header without angle brackets, when the message
  /// carried one. The per-mailbox import dedupe key, not a routing hint.
  final String? messageId;
  final String subject;
  final String body;
  final bool isDraft;
  final String? contentType;
  final MailRecipient? from;
  final List<MailRecipient> to;
  final List<MailRecipient> cc;
  final List<MailRecipient> bcc;
  final List<SnCloudFileReference> attachments;

  /// Inline MIME attachments keyed by their RFC 2392 Content-ID.
  final Map<String, SnCloudFileReference> inlineAttachments;
  final bool isRead;
  final bool isStarred;

  /// Server-side folder this message lives in
  /// (`inbox`, `sent`, `drafts`, `spam`, `trash`, `archive`).
  final String? folder;
  final DateTime? createdAt;
  final String? deliveryStatus;
  final int deliveryAttempts;
  final DateTime? lastDeliveryAttemptAt;
  final String? deliveryError;
  final String? providerMessageId;

  /// Assistant-generated summary of the message (ElecPostal's `summary`), null
  /// for messages the account never summarized — the feature is opt-in, and a
  /// message carrying a verification code or security event is never sent to
  /// the agent either.
  ///
  /// Listings reuse the same text as the message's `body` preview, so a list
  /// row already shows it while the detail pane has the full body to read.
  final String? summary;

  bool get hasDeliveryStatus =>
      deliveryStatus != null && deliveryStatus!.isNotEmpty;

  bool get isHtml => contentType?.toLowerCase() == 'text/html';

  /// Conversation key for this message: the server thread id, falling back to
  /// the message id for payloads without one (each message is its own thread).
  String get threadKey {
    final thread = threadId?.trim();
    return thread == null || thread.isEmpty ? id : thread;
  }

  String get displaySubject =>
      subject.trim().isNotEmpty ? subject : '(no subject)';

  String get previewText {
    final stripped = isHtml
        ? body
              .replaceAll(RegExp(r'<[^>]*>'), ' ')
              .replaceAll(RegExp(r'&[^;]+;'), ' ')
        : body;
    // Inline-image markers and content-id refs are internal plumbing, not
    // message copy: drop them (with or without a matching attachment) so
    // preview-generation markup never shows up in the list preview.
    return stripped
        .replaceAll(
          RegExp(r'\[image:\s*[^\]\r\n]+\]', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'''cid:[^"'\s>]+''', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  factory MailEmail.fromJson(Map<String, dynamic> json) {
    final mailboxRaw = json['mailbox'];
    final fromAddress = nonEmptyString(json['from_address']?.toString());
    final fromName = nonEmptyString(json['from_name']?.toString());
    final fromRaw = json['from'];
    final recipientsRaw = json['recipients'];

    MailRecipient? from;
    if (fromRaw is Map) {
      from = MailRecipient.fromJson(Map<String, dynamic>.from(fromRaw));
    } else if (fromAddress != null) {
      from = MailRecipient(address: fromAddress, name: fromName, kind: 'from');
    }

    final allRecipients = recipientsRaw is List
        ? recipientsRaw
              .whereType<Map>()
              .map(
                (item) =>
                    MailRecipient.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : <MailRecipient>[];

    final parsedAttachments = parseMailAttachments(json['attachments']);
    return MailEmail(
      id: json['id']?.toString() ?? '',
      mailboxId: json['mailbox_id']?.toString() ?? '',
      mailbox: mailboxRaw is Map
          ? MailMailbox.fromJson(Map<String, dynamic>.from(mailboxRaw))
          : null,
      subject: json['subject']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      isDraft: json['is_draft'] == true,
      threadId: nonEmptyString(json['thread_id']?.toString()),
      messageId: nonEmptyString(json['message_id']?.toString()),
      contentType: nonEmptyString(json['content_type']?.toString()),
      from: from,
      to: allRecipients.where((r) => r.kind == 'to').toList(),
      cc: allRecipients.where((r) => r.kind == 'cc').toList(),
      bcc: allRecipients.where((r) => r.kind == 'bcc').toList(),
      attachments: parsedAttachments.map((item) => item.file).toList(),
      inlineAttachments: {
        for (final attachment in parsedAttachments)
          if (attachment.contentId != null)
            attachment.contentId!: attachment.file,
      },
      isRead: json['is_read'] == true,
      isStarred: json['is_starred'] == true,
      folder: nonEmptyString(json['folder']?.toString()),
      createdAt: parseInstant(json['created_at']),
      deliveryStatus: nonEmptyString(json['delivery_status']?.toString()),
      deliveryAttempts: (json['delivery_attempts'] as num?)?.toInt() ?? 0,
      lastDeliveryAttemptAt: parseInstant(json['last_delivery_attempt_at']),
      deliveryError: nonEmptyString(json['delivery_error']?.toString()),
      providerMessageId: nonEmptyString(
        json['provider_message_id']?.toString(),
      ),
      summary: nonEmptyString(json['summary']?.toString()),
    );
  }
}

/// One conversation, as listed by `GET /postal/mailboxes/{id}/threads`.
///
/// [latestMessage] carries the newest message's header data plus a body
/// preview, so the list needs no per-thread fetch; the full conversation comes
/// from [WattEngineClient.getThread].
class MailThread {
  const MailThread({
    required this.id,
    required this.mailboxId,
    required this.subject,
    required this.messageCount,
    required this.unreadCount,
    required this.participants,
    required this.latestMessage,
    this.latestAt,
  });

  final String id;
  final String mailboxId;
  final String subject;
  final int messageCount;
  final int unreadCount;

  /// Every address seen on the conversation: senders and recipients.
  final List<String> participants;
  final MailEmail latestMessage;
  final DateTime? latestAt;

  bool get isRead => unreadCount == 0;

  bool get isMultiMessage => messageCount > 1;

  String get displaySubject => subject.trim().isNotEmpty
      ? subject
      : latestMessage.displaySubject;

  factory MailThread.fromJson(Map<String, dynamic> json) {
    final latestRaw = json['latest_message'];
    final latest = latestRaw is Map
        ? MailEmail.fromJson(Map<String, dynamic>.from(latestRaw))
        : const MailEmail(
            id: '',
            mailboxId: '',
            subject: '',
            body: '',
            isDraft: false,
          );
    final id = json['id']?.toString() ?? latest.threadKey;
    return MailThread(
      id: id,
      mailboxId: json['mailbox_id']?.toString() ?? latest.mailboxId,
      subject: json['subject']?.toString() ?? latest.subject,
      messageCount: (json['message_count'] as num?)?.toInt() ?? 1,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      participants:
          (json['participants'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList(growable: false) ??
          const [],
      latestMessage: latest,
      latestAt: parseInstant(json['latest_at']) ?? latest.createdAt,
    );
  }
}

class MailAttachment {
  const MailAttachment({required this.file, this.contentId});

  final SnCloudFileReference file;
  final String? contentId;
}

List<MailAttachment> parseMailAttachments(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) {
        final json = Map<String, dynamic>.from(item);
        final reference = json['file'] is Map
            ? Map<String, dynamic>.from(json['file'] as Map)
            : json;
        final fileId =
            (reference['id'] ??
                    json['storage_key'] ??
                    json['file_id'] ??
                    json['id'])
                ?.toString();
        if (fileId == null || fileId.isEmpty) return null;
        try {
          final file = SnCloudFileReference.fromJson({
            ...reference,
            'id': fileId,
            'name': reference['name'] ?? json['filename'] ?? fileId,
            'mime_type':
                reference['mime_type'] ??
                json['mime_type'] ??
                'application/octet-stream',
            'size': reference['size'] ?? json['size'] ?? 0,
          });
          final contentId = json['content_id']?.toString().trim();
          return MailAttachment(
            file: file,
            contentId: contentId == null || contentId.isEmpty
                ? null
                : contentId.replaceAll(RegExp(r'^<|>$'), ''),
          );
        } catch (_) {
          return null;
        }
      })
      .whereType<MailAttachment>()
      .toList(growable: false);
}

class MailCredential {
  const MailCredential({
    required this.id,
    required this.accountId,
    required this.mailboxId,
    required this.label,
    required this.protocols,
    this.createdAt,
  });

  final String id;
  final String accountId;
  final String mailboxId;
  final String label;
  final List<String> protocols;
  final DateTime? createdAt;

  factory MailCredential.fromJson(Map<String, dynamic> json) => MailCredential(
    id: json['id']?.toString() ?? '',
    accountId: json['account_id']?.toString() ?? '',
    mailboxId: json['mailbox_id']?.toString() ?? '',
    label: json['label']?.toString() ?? 'Credential',
    protocols:
        (json['protocols'] as List?)
            ?.map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList() ??
        const [],
    createdAt: parseInstant(json['created_at']),
  );
}

class MailCredentialCreated {
  const MailCredentialCreated({required this.credential, required this.secret});

  final MailCredential credential;
  final String secret;

  factory MailCredentialCreated.fromJson(Map<String, dynamic> json) {
    final credentialRaw = json['credential'];
    return MailCredentialCreated(
      credential: credentialRaw is Map
          ? MailCredential.fromJson(Map<String, dynamic>.from(credentialRaw))
          : MailCredential(
              id: '',
              accountId: '',
              mailboxId: '',
              label: json['label']?.toString() ?? 'Credential',
              protocols: const [],
            ),
      secret: json['secret']?.toString() ?? '',
    );
  }
}

/// One address assigned to a mailbox on a verified workspace custom domain.
class MailAlias {
  const MailAlias({
    required this.id,
    required this.mailboxId,
    required this.customDomainId,
    required this.address,
    this.name,
    this.createdAt,
  });

  final String id;
  final String mailboxId;
  final String customDomainId;
  final String address;
  final String? name;
  final DateTime? createdAt;

  factory MailAlias.fromJson(Map<String, dynamic> json) => MailAlias(
    id: json['id']?.toString() ?? '',
    mailboxId: json['mailbox_id']?.toString() ?? '',
    customDomainId: json['custom_domain_id']?.toString() ?? '',
    address: json['address']?.toString() ?? '',
    name: nonEmptyString(json['name']?.toString()),
    createdAt: parseInstant(json['created_at']),
  );
}

/// Forwards mail received through one alias to an external address.
class MailForwarding {
  const MailForwarding({
    required this.id,
    required this.mailboxId,
    required this.aliasId,
    required this.destination,
    this.createdAt,
  });

  final String id;
  final String mailboxId;
  final String aliasId;
  final String destination;
  final DateTime? createdAt;

  factory MailForwarding.fromJson(Map<String, dynamic> json) =>
      MailForwarding(
        id: json['id']?.toString() ?? '',
        mailboxId: json['mailbox_id']?.toString() ?? '',
        aliasId: json['alias_id']?.toString() ?? '',
        destination: json['destination']?.toString() ?? '',
        createdAt: parseInstant(json['created_at']),
      );
}

/// Workspace-shared mail storage usage and its plan limit.
class MailboxQuota {
  const MailboxQuota({
    required this.workspaceId,
    this.usedBytes = 0,
    this.limitBytes = 0,
    this.remainingBytes = 0,
  });

  final String workspaceId;
  final int usedBytes;
  final int limitBytes;
  final int remainingBytes;

  factory MailboxQuota.fromJson(Map<String, dynamic> json) => MailboxQuota(
    workspaceId: json['workspace_id']?.toString() ?? '',
    usedBytes: (json['used_bytes'] as num?)?.toInt() ?? 0,
    limitBytes: (json['limit_bytes'] as num?)?.toInt() ?? 0,
    remainingBytes: (json['remaining_bytes'] as num?)?.toInt() ?? 0,
  );
}

/// Block rule keeping a sender or domain out of a mailbox or workspace.
class MailBlockRule {
  const MailBlockRule({
    required this.id,
    required this.accountId,
    this.workspaceId,
    this.mailboxId,
    required this.pattern,
    required this.matchType,
    this.createdAt,
  });

  final String id;
  final String accountId;
  final String? workspaceId;
  final String? mailboxId;
  final String pattern;
  final String matchType;
  final DateTime? createdAt;

  factory MailBlockRule.fromJson(Map<String, dynamic> json) => MailBlockRule(
    id: json['id']?.toString() ?? '',
    accountId: json['account_id']?.toString() ?? '',
    workspaceId: json['workspace_id']?.toString(),
    mailboxId: json['mailbox_id']?.toString(),
    pattern: json['pattern']?.toString() ?? '',
    matchType: json['match_type']?.toString() ?? 'address',
    createdAt: parseInstant(json['created_at']),
  );
}

/// Account-level incoming-mail notification preferences.
class MailNotificationSettings {
  const MailNotificationSettings({
    required this.accountId,
    this.highlight = true,
    this.summarize = false,
  });

  final String accountId;
  final bool highlight;
  final bool summarize;

  factory MailNotificationSettings.fromJson(Map<String, dynamic> json) =>
      MailNotificationSettings(
        accountId: json['account_id']?.toString() ?? '',
        highlight: json['highlight'] != false,
        summarize: json['summarize'] == true,
      );
}

/// One DNS record a custom domain needs before it verifies.
class MailDnsRecord {
  const MailDnsRecord({required this.name, required this.type, required this.value});

  final String name;
  final String type;
  final String value;

  factory MailDnsRecord.fromJson(Map<String, dynamic> json) => MailDnsRecord(
    name: json['name']?.toString() ?? '',
    type: json['type']?.toString() ?? '',
    value: json['value']?.toString() ?? '',
  );
}

/// Used/limit/remaining triple shared by the mailbox and send-usage endpoints.
class MailUsageSummary {
  const MailUsageSummary({
    this.used = 0,
    this.limit = 0,
    this.remaining = 0,
  });

  final int used;
  final int limit;
  final int remaining;

  factory MailUsageSummary.fromJson(Map<String, dynamic> json) =>
      MailUsageSummary(
        used: (json['used'] as num?)?.toInt() ?? 0,
        limit: (json['limit'] as num?)?.toInt() ?? 0,
        remaining: (json['remaining'] as num?)?.toInt() ?? 0,
      );
}

/// Outbound mail sent from a workspace today and this month.
class MailSendUsage {
  const MailSendUsage({required this.daily, required this.monthly});

  final MailUsageSummary daily;
  final MailUsageSummary monthly;

  factory MailSendUsage.fromJson(Map<String, dynamic> json) => MailSendUsage(
    daily: MailUsageSummary.fromJson(
      Map<String, dynamic>.from(json['daily'] as Map? ?? const {}),
    ),
    monthly: MailUsageSummary.fromJson(
      Map<String, dynamic>.from(json['monthly'] as Map? ?? const {}),
    ),
  );
}

/// Workspace-owned SES sending domain.
class MailCustomDomain {
  const MailCustomDomain({
    required this.id,
    required this.workspaceId,
    required this.domain,
    this.verificationStatus,
    this.verifiedForSending = false,
    this.stage,
    this.dkimStatus,
    this.mailFromDomain,
    this.mailFromStatus,
    this.dnsRecords = const [],
  });

  final String id;
  final String workspaceId;
  final String domain;
  final String? verificationStatus;
  final bool verifiedForSending;
  final String? stage;
  final String? dkimStatus;
  final String? mailFromDomain;
  final String? mailFromStatus;
  final List<MailDnsRecord> dnsRecords;

  /// Whether the domain is fully verified and may send mail.
  bool get isReady =>
      verifiedForSending ||
      (verificationStatus ?? '').toLowerCase() == 'verified';

  factory MailCustomDomain.fromJson(Map<String, dynamic> json) {
    final rawRecords = json['dns_records'];
    return MailCustomDomain(
      id: json['id']?.toString() ?? '',
      workspaceId: json['workspace_id']?.toString() ?? '',
      domain: json['domain']?.toString() ?? '',
      verificationStatus: json['verification_status']?.toString(),
      verifiedForSending: json['verified_for_sending_status'] == true,
      stage: json['stage']?.toString(),
      dkimStatus: nonEmptyString(json['dkim_status']?.toString()),
      mailFromDomain: nonEmptyString(json['mail_from_domain']?.toString()),
      mailFromStatus: nonEmptyString(json['mail_from_status']?.toString()),
      dnsRecords: rawRecords is List
          ? rawRecords
                .whereType<Map>()
                .map(
                  (item) => MailDnsRecord.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

/// Outcome of one message in an import batch, mirroring the ElecPostal
/// `POST /postal/import` item result. [source] is a client-side enrichment
/// naming the origin file/message (`.eml` path, or `file.mbox#3`).
class MailImportItemResult {
  const MailImportItemResult({
    required this.index,
    required this.status,
    this.emailId,
    this.error,
    this.source,
  });

  /// Position of the message in the whole import (not per request).
  final int index;

  /// `imported`, `duplicate`, or `failed`.
  final String status;
  final String? emailId;
  final String? error;
  final String? source;

  factory MailImportItemResult.fromJson(Map<String, dynamic> json) =>
      MailImportItemResult(
        index: (json['index'] as num?)?.toInt() ?? 0,
        status: json['status']?.toString() ?? '',
        emailId: nonEmptyString(json['email_id']?.toString()),
        error: nonEmptyString(json['error']?.toString()),
      );

  MailImportItemResult withPosition(int globalIndex, String? sourceLabel) =>
      MailImportItemResult(
        index: globalIndex,
        status: status,
        emailId: emailId,
        error: error,
        source: sourceLabel ?? source,
      );
}

/// Aggregate of one or more `POST /postal/import` batches.
class MailImportResult {
  MailImportResult({
    this.imported = 0,
    this.duplicates = 0,
    this.failed = 0,
    List<MailImportItemResult>? items,
  }) : items = items ?? [];

  int imported;
  int duplicates;
  int failed;
  final List<MailImportItemResult> items;

  factory MailImportResult.fromJson(Map<String, dynamic> json) =>
      MailImportResult(
        imported: (json['imported'] as num?)?.toInt() ?? 0,
        duplicates: (json['duplicates'] as num?)?.toInt() ?? 0,
        failed: (json['failed'] as num?)?.toInt() ?? 0,
        items:
            (json['items'] as List?)
                ?.whereType<Map>()
                .map(
                  (item) => MailImportItemResult.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false) ??
            const [],
      );
}

class TaskComment {
  const TaskComment({
    required this.id,
    required this.taskId,
    required this.content,
    this.authorAccountId,
    this.externalAuthorLogin,
    this.externalAuthorAvatarUrl,
    this.createdAt,
    this.updatedAt,
    this.hasGitHubLink = false,
  });

  final String id;
  final String taskId;
  final String content;
  final String? authorAccountId;
  final String? externalAuthorLogin;
  final String? externalAuthorAvatarUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool hasGitHubLink;

  /// Comments authored on GitHub (no local account) are read-only in SolWatt.
  bool get isFromGitHub =>
      externalAuthorLogin != null && externalAuthorLogin!.isNotEmpty;

  bool isOwnedBy(String? accountId) =>
      accountId != null &&
      authorAccountId != null &&
      authorAccountId == accountId;

  bool canEditOrDelete(String? accountId) =>
      !isFromGitHub && isOwnedBy(accountId);

  String authorLabel({String? currentAccountId}) {
    if (isFromGitHub) return externalAuthorLogin!;
    if (isOwnedBy(currentAccountId)) return 'You';
    if (authorAccountId != null && authorAccountId!.isNotEmpty) {
      return 'Member ${_shortId(authorAccountId!)}';
    }
    return 'Unknown';
  }

  factory TaskComment.fromJson(Map<String, dynamic> json) {
    final github = json['git_hub_comment'] ?? json['github_comment'];
    return TaskComment(
      id: json['id']?.toString() ?? '',
      taskId: json['task_id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      authorAccountId: json['author_account_id']?.toString(),
      externalAuthorLogin: nonEmptyString(
        json['external_author_login']?.toString(),
      ),
      externalAuthorAvatarUrl: nonEmptyString(
        json['external_author_avatar_url']?.toString(),
      ),
      createdAt: parseInstant(json['created_at']),
      updatedAt: parseInstant(json['updated_at']),
      hasGitHubLink: github != null,
    );
  }
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
    'description': nonEmptyString(description),
    // API accepts empty string; send '' only when explicitly cleared vs omit.
    'content': nonEmptyString(content) ?? '',
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
    'description': nonEmptyString(description),
    'content': nonEmptyString(content) ?? '',
    'attachment_ids': attachmentIds,
    'priority': priority,
    'deadline_at': deadlineAt?.toUtc().toIso8601String(),
    'complete_reason': ?completeReason,
    'group_id': ?groupId,
    if (ungroup == true) 'ungroup': true,
    'tags': ?tags,
  };
}

/// Trims and returns null when blank (null, empty, or whitespace-only).
String? nonEmptyString(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

/// Resolves a display URL for a cloud file reference.
String cloudFileDisplayUrl(IDisplayableCloudFile file) =>
    file.storageUrl ?? '$_issuer/drive/files/${file.id}';

/// Best-effort human message from a Drive / DysonFS API error response.
String driveApiErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    String? serverMessage;
    if (data is Map) {
      final message =
          data['error'] ?? data['message'] ?? data['detail'] ?? data['title'];
      if (message != null && message.toString().trim().isNotEmpty) {
        serverMessage = message.toString().trim();
      }
    } else if (data is String && data.trim().isNotEmpty) {
      serverMessage = data.trim();
    }

    if (serverMessage != null) {
      return _friendlyWorkspaceDriveMessage(serverMessage);
    }
    final status = error.response?.statusCode;
    if (status != null) {
      return 'Drive request failed (HTTP $status). ${error.message ?? ''}'
          .trim();
    }
    return error.message ?? error.toString();
  }
  if (error is OAuthException) {
    return _friendlyWorkspaceDriveMessage(error.message);
  }
  return error.toString();
}

/// Maps DysonFS workspace-drive errors into clearer SolWatt copy.
String _friendlyWorkspaceDriveMessage(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('workspace uploads are not configured') ||
      lower.contains('workspace gRPC'.toLowerCase())) {
    return 'Workspace Drive is not enabled on the server. '
        'DysonFS needs [workspace] target pointing at WattEngine '
        '(see FileSystem WORKSPACE_FILES.md).';
  }
  if (lower.contains('workspace membership')) {
    return 'You need Member (or higher) role in this workspace to manage files.';
  }
  if (lower.contains('invalid workspace id')) {
    return 'Invalid workspace. Switch workspace and try again.';
  }
  if (lower.contains('quota exceeded') || lower.contains('remaining=')) {
    return 'Workspace storage quota exceeded. $message';
  }
  return message;
}

String _guessContentType(String fileName) {
  final name = fileName.toLowerCase();
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
  if (name.endsWith('.gif')) return 'image/gif';
  if (name.endsWith('.webp')) return 'image/webp';
  if (name.endsWith('.svg')) return 'image/svg+xml';
  if (name.endsWith('.pdf')) return 'application/pdf';
  if (name.endsWith('.mp4')) return 'video/mp4';
  if (name.endsWith('.mov')) return 'video/quicktime';
  if (name.endsWith('.mp3')) return 'audio/mpeg';
  if (name.endsWith('.wav')) return 'audio/wav';
  if (name.endsWith('.zip')) return 'application/zip';
  if (name.endsWith('.json')) return 'application/json';
  if (name.endsWith('.txt')) return 'text/plain';
  if (name.endsWith('.md')) return 'text/markdown';
  if (name.endsWith('.csv')) return 'text/csv';
  return 'application/octet-stream';
}

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

/// Current bearer token for signed URLs and image requests, mirroring
/// Solian's `tokenProvider` (used by the ported drive's UniversalImage).
final tokenProvider = Provider<AppToken?>((ref) {
  final session = ref.watch(authSessionProvider).value;
  if (session == null) return null;
  return AppToken(token: session.accessToken);
});
final solWattProfileProvider = FutureProvider<SolWattProfile?>((ref) async {
  final session = await ref.watch(authSessionProvider.future);
  if (session == null) return null;
  return ref.watch(authenticatorProvider).getCurrentProfile();
});

final userInfoProvider = FutureProvider<SnAccount?>((ref) async {
  final profile = await ref.watch(solWattProfileProvider.future);
  return profile?.account;
});

/// Bundled Pro seat for the signed-in account (perk 3+), resolved against the
/// workspace list so the UI can show which workspace holds the assignment.
final bundledProOverviewProvider = FutureProvider<BundledProOverview?>((
  ref,
) async {
  final profile = await ref.watch(solWattProfileProvider.future);
  if (profile == null) return null;

  final workspaces = await ref.watch(workspacesProvider.future);
  final selected = await ref.watch(selectedWorkspaceProvider.future);
  final probe =
      selected ??
      workspaces.where((w) => w.ownerAccountId == profile.id).firstOrNull ??
      workspaces.firstOrNull;

  BundledPlanInfo? bundled;
  if (probe != null) {
    try {
      final status = await ref
          .watch(wattEngineClientProvider)
          .getWorkspacePlanStatus(probe.slug);
      bundled = status.bundledPlan;
    } catch (_) {
      // Plan status is optional for the overview card.
    }
  }

  Workspace? assigned;
  final assignedId = bundled?.isEnabled == true ? bundled?.workspaceId : null;
  if (assignedId != null && assignedId.isNotEmpty) {
    assigned = workspaces.where((w) => w.id == assignedId).firstOrNull;
  }

  return BundledProOverview(
    eligible: profile.canAssignBundledPro,
    perkLevel: profile.perkLevel,
    bundled: bundled,
    assignedWorkspace: assigned,
  );
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
  ref.invalidate(solWattProfileProvider);
  ref.invalidate(userInfoProvider);
  ref.invalidate(bundledProOverviewProvider);
  ref.invalidate(workspacesProvider);
  ref.invalidate(selectedWorkspaceProvider);
  ref.invalidate(broadsProvider);
  ref.invalidate(workspaceFilesProvider);
  ref.invalidate(workspaceFolderChildrenProvider);
  ref.invalidate(workspaceUnindexedFilesProvider);
  ref.invalidate(workspaceDriveUsageProvider);
  ref.invalidate(solarNetworkClientProvider);
}

void invalidateWorkspaceScope(WidgetRef ref) {
  ref.invalidate(selectedWorkspaceProvider);
  ref.invalidate(bundledProOverviewProvider);
  ref.invalidate(broadsProvider);
  ref.invalidate(workspaceFilesProvider);
  ref.invalidate(workspaceFolderChildrenProvider);
  ref.invalidate(workspaceUnindexedFilesProvider);
  ref.invalidate(workspaceDriveUsageProvider);
}

/// Invalidates workspace Drive listings and usage after upload/delete/rename.
void invalidateWorkspaceDrive(WidgetRef ref) {
  ref.invalidate(workspaceFilesProvider);
  ref.invalidate(workspaceFolderChildrenProvider);
  ref.invalidate(workspaceUnindexedFilesProvider);
  ref.invalidate(workspaceDriveUsageProvider);
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

final tasksProvider = FutureProvider.family<List<WorkTask>, TaskListRequest>(
  (ref, request) async => ref
      .watch(wattEngineClientProvider)
      .listTasks(request.broadId, filters: request.filters),
);

final taskGroupsProvider = FutureProvider.family<List<TaskGroup>, String>(
  (ref, broadId) async =>
      ref.watch(wattEngineClientProvider).listTaskGroups(broadId),
);

/// Linked GitHub repositories for a board.
final gitHubIntegrationProvider =
    FutureProvider.family<List<GitHubIntegration>, String>(
      (ref, broadId) async =>
          ref.watch(wattEngineClientProvider).getGitHubIntegrations(broadId),
    );

final taskCommentsProvider = FutureProvider.family<List<TaskComment>, String>(
  (ref, taskId) async =>
      ref.watch(wattEngineClientProvider).listTaskComments(taskId),
);

/// Soft filter when the API may still embed `workspace_id` on each row.
List<DriveFileEntry> _filterWorkspaceEntries(
  List<DriveFileEntry> items,
  String workspaceId,
) => items
    .where(
      (entry) =>
          entry.workspaceId == null || entry.belongsToWorkspace(workspaceId),
    )
    .toList(growable: false);

/// Recent Drive files for the active workspace (`workspace_id` query).
final workspaceFilesProvider = FutureProvider<List<DriveFileEntry>>((
  ref,
) async {
  final workspace = await ref.watch(selectedWorkspaceProvider.future);
  if (workspace == null) return const [];
  final page = await ref
      .watch(wattEngineClientProvider)
      .listMyCloudFiles(take: 100, workspaceId: workspace.id);
  return _filterWorkspaceEntries(page.items, workspace.id);
});

/// Indexed folder children for the active workspace.
///
/// [parentId] empty string means workspace root (`/files/root/children`).
final workspaceFolderChildrenProvider =
    FutureProvider.family<List<DriveFileEntry>, String>((ref, parentId) async {
      final workspace = await ref.watch(selectedWorkspaceProvider.future);
      if (workspace == null) return const [];
      final page = await ref
          .watch(wattEngineClientProvider)
          .listCloudFolderChildren(
            parentId: parentId.isEmpty ? null : parentId,
            workspaceId: workspace.id,
            take: 100,
          );
      return _filterWorkspaceEntries(page.items, workspace.id);
    });

/// Unindexed workspace files (logos, board backgrounds, other loose assets).
///
/// Flat list — unindexed files are outside the folder hierarchy.
final workspaceUnindexedFilesProvider = FutureProvider<List<DriveFileEntry>>((
  ref,
) async {
  final workspace = await ref.watch(selectedWorkspaceProvider.future);
  if (workspace == null) return const [];
  final page = await ref
      .watch(wattEngineClientProvider)
      .listUnindexedCloudFiles(workspaceId: workspace.id, take: 100);
  return _filterWorkspaceEntries(page.items, workspace.id);
});

/// Live workspace storage usage (used / plan cap / file count).
final workspaceDriveUsageProvider = FutureProvider<WorkspaceDriveUsage?>((
  ref,
) async {
  final workspace = await ref.watch(selectedWorkspaceProvider.future);
  if (workspace == null) return null;
  return ref
      .watch(wattEngineClientProvider)
      .getWorkspaceDriveUsage(workspace.id);
});

/// All ElecPostal mailboxes for the signed-in account.
final mailboxesProvider = FutureProvider<List<MailMailbox>>((ref) async {
  final session = await ref.watch(authSessionProvider.future);
  if (session == null) return const [];
  final workspace = await ref.watch(selectedWorkspaceProvider.future);
  return ref
      .watch(wattEngineClientProvider)
      .listMailboxes(workspaceId: workspace?.id);
});

/// Currently selected mailbox within the active workspace.
///
/// Shared between the mail list and the mailbox bottom navigation bar so the
/// inbox can be switched from either surface. Resolves to the default mailbox
/// when unset or stale.
final selectedMailboxIdProvider =
    NotifierProvider<SelectedMailboxIdNotifier, String?>(
      SelectedMailboxIdNotifier.new,
    );

class SelectedMailboxIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

/// Currently selected mail folder (`inbox`, `sent`, `drafts`, `spam`,
/// `trash`, `archive`), shared between the mail folder tabs and the desktop
/// navigation rail.
final selectedFolderProvider = NotifierProvider<SelectedFolderNotifier, String>(
  SelectedFolderNotifier.new,
);

class SelectedFolderNotifier extends Notifier<String> {
  @override
  String build() => 'inbox';

  void select(String folder) => state = folder;
}

/// Filters the mail list applies to a conversation query. Mirrors the
/// ElecPostal list parameters the UI exposes; unset fields are not sent.
typedef EmailListFilter = ({
  String? mailboxId,
  String? folder,
  String? q,
  String? status,
  bool? isFlagged,
  String? from,
  String? to,
  bool? hasAttachments,
});

/// Unread Inbox count per mailbox id, driving the Inbox badge.
final mailboxUnreadCountsProvider = FutureProvider<Map<String, int>>((
  ref,
) async {
  final mailboxes = await ref.watch(mailboxesProvider.future);
  final client = ref.watch(wattEngineClientProvider);
  final counts = <String, int>{};
  for (final mailbox in mailboxes) {
    counts[mailbox.id] = await client
        .listUnreadInboxCount(mailbox.id)
        .catchError((_) => 0);
  }
  return counts;
});

/// Marks every mail surface stale after a write: the conversation list, the
/// conversations the detail pane can open, the message detail, and the unread
/// count behind the Inbox badge on the rail and bottom bar.
///
/// The badge is easy to miss here — it is its own round-trip per mailbox, not
/// a view over the thread list.
void invalidateMailSurfaces(WidgetRef ref) {
  ref.invalidate(threadsProvider);
  ref.invalidate(threadProvider);
  ref.invalidate(emailProvider);
  ref.invalidate(mailboxUnreadCountsProvider);
}

/// [invalidateMailSurfaces] for code that holds a provider [Ref] rather than a
/// [WidgetRef] — the realtime bridge refreshes mail outside a widget build.
/// Ref and WidgetRef are unrelated types and riverpod does not export the
/// `ProviderOrFamily` both `invalidate`s take, so the two entries cannot share
/// a body; keep the lists identical.
void invalidateMailSurfacesFrom(Ref ref) {
  ref.invalidate(threadsProvider);
  ref.invalidate(threadProvider);
  ref.invalidate(emailProvider);
  ref.invalidate(mailboxUnreadCountsProvider);
}

final mailAddressSuggestionsProvider =
    FutureProvider.family<
      List<MailAddressSuggestion>,
      ({String query, bool senders})
    >((ref, request) async {
      final client = ref.watch(wattEngineClientProvider);
      if (request.senders) return client.listSenders(query: request.query);
      return client.listContacts(query: request.query);
    });

/// The senders index, keyed by lowercase address: everything the server knows
/// about the addresses a message talks about.
///
/// The emails endpoint carries no avatar or contact data, so the list, the
/// conversation strip and the message header all join against this index the
/// same way compose autocomplete does — which is also how an address that is an
/// alias of one of the account's own mailboxes is recognised (`alias`), and how
/// a sender gets a name the message itself did not carry. A failure degrades to
/// an empty map so mail never depends on it.
final mailSenderIndexProvider =
    FutureProvider<Map<String, MailAddressSuggestion>>((ref) async {
      final client = ref.watch(wattEngineClientProvider);
      final senders = await client
          .listSenders(query: '', take: 200)
          .catchError((_) => const <MailAddressSuggestion>[]);
      return {
        for (final sender in senders)
          if (sender.address.trim().isNotEmpty)
            sender.address.trim().toLowerCase(): sender,
      };
    });

/// Thread page request: the active mail-list filter plus how many
/// conversations to show. The list grows [take] rather than paging offsets so
/// each fetch is a superset of the previous one — no offset drift, no stitched
/// duplicate keys — and the per-thread counts stay whole-conversation.
typedef MailThreadsQuery = ({EmailListFilter filter, int take});

/// Conversation summaries for the mail list, keyed by filter and page size.
///
/// Every `take` is its own family entry, so the provider is auto-disposed:
/// only the size the list currently shows stays cached.
final threadsProvider =
    FutureProvider.family<PaginatedResult<MailThread>, MailThreadsQuery>((
      ref,
      query,
    ) async {
      // A search is about finding a message, not about where it happens to sit,
      // so it runs across every mailbox and folder of the account. Choosing a
      // mailbox and folder scopes the browse list only.
      final searching = (query.filter.q ?? '').trim().isNotEmpty;
      final mailboxId = searching ? null : query.filter.mailboxId;
      if (!searching && (mailboxId == null || mailboxId.isEmpty)) {
        // No mailbox resolves yet (account without inboxes): nothing to list.
        return const PaginatedResult<MailThread>(items: [], totalCount: 0);
      }
      return ref
          .watch(wattEngineClientProvider)
          .listThreads(
            mailboxId,
            folder: searching ? null : query.filter.folder,
            q: query.filter.q,
            status: query.filter.status,
            isFlagged: query.filter.isFlagged,
            from: query.filter.from,
            to: query.filter.to,
            hasAttachments: query.filter.hasAttachments,
            take: query.take,
          );
    }, isAutoDispose: true);

/// The full conversation a message belongs to, oldest message first.
final threadProvider = FutureProvider.family<List<MailEmail>, String>(
  (ref, threadId) async =>
      ref.watch(wattEngineClientProvider).getThread(threadId),
);

/// Detailed email by id.
final emailProvider = FutureProvider.family<MailEmail, String>(
  (ref, emailId) async => ref.watch(wattEngineClientProvider).getEmail(emailId),
);

/// App-password credentials for mail protocols (SMTP/IMAP/POP3).
final mailCredentialsProvider = FutureProvider<List<MailCredential>>(
  (ref) async => ref.watch(wattEngineClientProvider).listMailCredentials(),
);

/// Configured canonical mail domain from ElecPostal (e.g. "example.com").
final mailHostProvider = FutureProvider<String>(
  (ref) async => ref.watch(wattEngineClientProvider).getMailHost(),
);

/// Per-mailbox alias addresses (`GET /postal/mailboxes/{id}/aliases`).
final mailboxAliasesProvider = FutureProvider.family<List<MailAlias>, String>(
  (ref, mailboxId) async =>
      ref.watch(wattEngineClientProvider).listMailboxAliases(mailboxId),
);

/// Per-mailbox alias forwarding rules (`GET /postal/mailboxes/{id}/forwarding`).
final mailboxForwardingsProvider =
    FutureProvider.family<List<MailForwarding>, String>(
      (ref, mailboxId) async =>
          ref.watch(wattEngineClientProvider).listMailForwardings(mailboxId),
    );

/// Workspace-shared mail storage usage for a mailbox's workspace.
final mailboxQuotaProvider = FutureProvider.family<MailboxQuota, String>(
  (ref, mailboxId) async =>
      ref.watch(wattEngineClientProvider).getMailboxQuota(mailboxId),
);

/// Sender/domain block rules for the account.
final mailBlockRulesProvider = FutureProvider<List<MailBlockRule>>(
  (ref) async => ref.watch(wattEngineClientProvider).listBlockRules(),
);

/// Account-level incoming-mail notification preferences.
final mailNotificationSettingsProvider =
    FutureProvider<MailNotificationSettings>(
      (ref) async =>
          ref.watch(wattEngineClientProvider).getNotificationSettings(),
    );

/// Workspace-owned custom domains, used to pick a domain for new aliases.
final customDomainsProvider = FutureProvider.family<List<MailCustomDomain>, String>(
  (ref, workspaceId) async =>
      ref.watch(wattEngineClientProvider).listCustomDomains(
        workspaceId: workspaceId,
      ),
);

/// Logic layer for `.eml`/`.mbox` mail import: parsing, attachment upload to
/// workspace Drive, chunking, and `POST /postal/import` calls. Consumed by
/// the import UI; see `MailImportService` for the API.
final mailImportServiceProvider = Provider(
  (ref) => MailImportService(client: ref.watch(wattEngineClientProvider)),
);

/// Authenticated Solar Network SDK client (Ring, Drive helpers, etc.).
///
/// Injects the current OAuth bearer on every request. Prefer this for typed
/// SDK domains such as [SolarNetworkClient.notifications].
final solarNetworkClientProvider = Provider<SolarNetworkClient>((ref) {
  final authenticator = ref.watch(authenticatorProvider);
  final dio = _createLoggedDio(
    BaseOptions(
      baseUrl: _issuer,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );
  dio.interceptors.insert(
    0,
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          final session = await authenticator.validSession();
          if (session != null && session.accessToken.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer ${session.accessToken}';
          }
        } catch (_) {
          // Leave the request unauthenticated; the API will return 401.
        }
        handler.next(options);
      },
    ),
  );
  final client = SolarNetworkClient.fromDio(dio);
  ref.onDispose(client.close);
  return client;
});
