import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';
// The SDK ships its own gateway frame type; this app's realtime bridge talks
// to its local WebSocketService, whose frames are solwatt's WebSocketPacket.
import 'package:solar_network_sdk/solar_network_sdk.dart' hide WebSocketPacket;
import 'package:solwatt/ideask/ideask_providers.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/notifications/notifications.dart';
import 'package:solwatt/websocket.dart';

final _log = Logger('SolWatt.Realtime');

/// Keeps the gateway websocket connected while a session exists, and routes
/// packets into Riverpod invalidations (notifications and the Ideask tree).
///
/// Watch this from the app shell so the bridge stays alive for the signed-in
/// session.
final realtimeBridgeProvider = Provider<RealtimeBridge>((ref) {
  final bridge = RealtimeBridge(ref);
  ref.onDispose(bridge.dispose);
  // React to auth changes.
  ref.listen<AsyncValue<OAuthSession?>>(authSessionProvider, (previous, next) {
    next.when(
      data: (session) {
        if (session != null) {
          unawaited(bridge.ensureConnected());
        } else {
          unawaited(bridge.disconnect());
        }
      },
      loading: () {},
      error: (_, _) => unawaited(bridge.disconnect()),
    );
  }, fireImmediately: true);
  return bridge;
});

class RealtimeBridge {
  RealtimeBridge(this._ref) : _ws = _ref.read(websocketServiceProvider) {
    _packetSub = _ws.dataStream.listen(_onPacket);
  }

  final Ref _ref;

  /// Captured up-front: [dispose] must not touch the container, which is
  /// already torn down when the provider is disposed.
  final WebSocketService _ws;
  StreamSubscription<WebSocketPacket>? _packetSub;
  final Map<String, Timer> _taskDebounce = {};
  Timer? _treeDebounce;
  Timer? _notificationDebounce;
  Timer? _mailDebounce;

  Future<void> ensureConnected() async {
    final session = await _ref.read(authSessionProvider.future);
    if (session == null) return;
    final ws = _ws;
    if (ws.currentState == WebSocketConnectionState.connected ||
        ws.currentState == WebSocketConnectionState.connecting) {
      return;
    }
    await ws.connect();
  }

  Future<void> disconnect() async {
    for (final timer in _taskDebounce.values) {
      timer.cancel();
    }
    _taskDebounce.clear();
    _treeDebounce?.cancel();
    _notificationDebounce?.cancel();
    _mailDebounce?.cancel();
    await _ws.disconnect();
  }

  void dispose() {
    unawaited(disconnect());
    _packetSub?.cancel();
    _packetSub = null;
  }

  void _onPacket(WebSocketPacket packet) {
    final type = packet.type;
    if (type.isEmpty || type == 'ping' || type == 'pong') return;

    _log.info('Packet: $type');

    if (type == 'notifications.new') {
      _handleNotification(packet);
      return;
    }

    if (type.startsWith('mail.')) {
      _scheduleMailRefresh();
      return;
    }

    if (type.startsWith('ideask.')) {
      _handleIdeask(type, packet.data);
      return;
    }
  }

  void _handleNotification(WebSocketPacket packet) {
    final raw = packet.data;
    if (raw == null) {
      _scheduleNotificationRefresh();
      return;
    }

    // Prefer the nested object when Ideask-style double-wrap is present.
    final payload = _unwrapPayloadMap(raw) ?? raw;

    try {
      final notification = SnNotification.fromJson(payload);
      // Multi-tenant: only react to SolWatt (or unscoped) notifications.
      final appId = notification.appId;
      if (appId != null &&
          appId.isNotEmpty &&
          appId != kNotificationTenantAppId) {
        _log.fine('Ignoring notification for other app: $appId');
        return;
      }
    } catch (error) {
      _log.fine('Notification payload parse soft-fail: $error');
    }

    _scheduleNotificationRefresh();
  }

  void _scheduleNotificationRefresh() {
    _notificationDebounce?.cancel();
    _notificationDebounce = Timer(const Duration(milliseconds: 200), () {
      _ref.invalidate(notificationUnreadCountProvider);
      _ref.invalidate(notificationListProvider);
    });
  }

  void _scheduleMailRefresh() {
    _mailDebounce?.cancel();
    _mailDebounce = Timer(const Duration(milliseconds: 200), () {
      _log.info('Refreshing mail after realtime update');
      invalidateMailSurfacesFrom(_ref);
    });
  }

  void _handleIdeask(String type, Map<String, dynamic>? data) {
    final event = type.substring('ideask.'.length);

    switch (event) {
      // Tasks and their comments change what a list shows, not the tree.
      case 'task_created':
      case 'task_updated':
      case 'task_assigned':
      case 'task_due_reminder':
        _debounceTaskRefresh();
      // The tree's own nodes: folders, pages, collections and their views.
      case 'folder_created':
      case 'folder_updated':
      case 'folder_deleted':
      case 'page_created':
      case 'page_updated':
      case 'page_deleted':
      case 'collection_created':
      case 'collection_updated':
      case 'collection_deleted':
      case 'view_created':
      case 'view_updated':
      case 'view_deleted':
        _debounceTreeRefresh();
      // A body save only changes the document being read; the page's own
      // provider is invalidated by the save it made. Nothing to fan out.
      case 'page_body_updated':
        _debounceTreeRefresh();
      // A collection row is a page: the collection's query and the page both
      // change.
      case 'collection_row_changed':
        _debounceTaskRefresh();
        _debounceTreeRefresh();
      default:
        _log.fine('Unhandled ideask event: $event');
    }
  }

  void _debounceTaskRefresh() {
    _taskDebounce['*']?.cancel();
    _taskDebounce['*'] = Timer(const Duration(milliseconds: 250), () {
      _taskDebounce.remove('*');
      _log.info('Refreshing Ideask tasks');
      _ref.invalidate(tasksProvider);
    });
  }

  void _debounceTreeRefresh() {
    _treeDebounce?.cancel();
    _treeDebounce = Timer(const Duration(milliseconds: 250), () {
      _log.info('Refreshing the Ideask tree');
      _ref.invalidate(ideaskTreeProvider);
      _ref.invalidate(ideaskBrowserProvider);
    });
  }
}

/// Prefer the innermost map that looks like a domain payload.
Map<String, dynamic>? _unwrapPayloadMap(Map<String, dynamic> root) {
  // Envelope: { type, data: { entity, data: payload } }
  var cursor = root;
  for (var i = 0; i < 4; i++) {
    final nested = cursor['data'];
    if (nested is! Map) break;
    final next = Map<String, dynamic>.from(nested);
    // Ideask inner payload has task/broad keys or is the notification itself.
    if (next.containsKey('task') ||
        next.containsKey('broad') ||
        next.containsKey('title') && next.containsKey('topic')) {
      return next;
    }
    if (next.containsKey('data') && next['data'] is Map) {
      cursor = next;
      continue;
    }
    // notifications.new often is the SnNotification itself one level down.
    if (next.containsKey('id') && next.containsKey('topic')) {
      return next;
    }
    cursor = next;
  }
  if (root.containsKey('id') && root.containsKey('topic')) return root;
  return null;
}
