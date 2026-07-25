import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/notifications/notifications.dart';
import 'package:solwatt/websocket.dart';

final _log = Logger('SolWatt.Realtime');

/// Keeps the gateway websocket connected while a session exists, and routes
/// packets into Riverpod invalidations (notifications + Ideask tasks/boards).
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
  RealtimeBridge(this._ref) {
    final ws = _ref.read(websocketServiceProvider);
    _packetSub = ws.dataStream.listen(_onPacket);
  }

  final Ref _ref;
  StreamSubscription<WebSocketPacket>? _packetSub;
  final Map<String, Timer> _taskDebounce = {};
  Timer? _boardsDebounce;
  Timer? _notificationDebounce;

  Future<void> ensureConnected() async {
    final session = await _ref.read(authSessionProvider.future);
    if (session == null) return;
    final ws = _ref.read(websocketServiceProvider);
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
    _boardsDebounce?.cancel();
    _notificationDebounce?.cancel();
    await _ref.read(websocketServiceProvider).disconnect();
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

  void _handleIdeask(String type, Map<String, dynamic>? data) {
    final event = type.substring('ideask.'.length);
    final broadId = _extractBroadId(data);

    switch (event) {
      case 'task_created':
      case 'task_updated':
      case 'task_assigned':
      case 'task_due_reminder':
        if (broadId != null && broadId.isNotEmpty) {
          _debounceTaskRefresh(broadId);
        } else {
          // Fall back: refresh all currently cached task families is not
          // possible; boards list is enough for navigation.
          _debounceBoardsRefresh();
        }
      case 'broad_created':
      case 'broad_updated':
        _debounceBoardsRefresh();
      default:
        _log.fine('Unhandled ideask event: $event');
    }
  }

  void _debounceTaskRefresh(String broadId) {
    _taskDebounce[broadId]?.cancel();
    _taskDebounce[broadId] = Timer(const Duration(milliseconds: 250), () {
      _taskDebounce.remove(broadId);
      _log.info('Refreshing tasks for board $broadId');
      _ref.invalidate(tasksProvider(broadId));
      _ref.invalidate(taskGroupsProvider(broadId));
    });
  }

  void _debounceBoardsRefresh() {
    _boardsDebounce?.cancel();
    _boardsDebounce = Timer(const Duration(milliseconds: 250), () {
      _log.info('Refreshing boards list');
      _ref.invalidate(broadsProvider);
    });
  }
}

/// Walks nested maps to find a board id from Ideask payloads.
///
/// Supports both the clean payload shape and the double-wrapped packet that
/// RealtimeDeliveryService currently publishes (full packet JSON as `data`).
String? _extractBroadId(Map<String, dynamic>? root) {
  if (root == null) return null;

  String? fromMap(Map<dynamic, dynamic> map) {
    for (final key in const ['broad_id', 'broadId', 'board_id', 'boardId']) {
      final value = map[key];
      if (value != null && value.toString().isNotEmpty) {
        return value.toString();
      }
    }
    final broad = map['broad'];
    if (broad is Map) {
      final id = broad['id'];
      if (id != null && id.toString().isNotEmpty) return id.toString();
    }
    final task = map['task'];
    if (task is Map) {
      final nested = fromMap(task);
      if (nested != null) return nested;
    }
    return null;
  }

  // Flatten possible wraps: data / data.data / nested type envelope.
  final queue = <Map<dynamic, dynamic>>[root];
  final seen = <Map<dynamic, dynamic>>{};
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    if (!seen.add(current)) continue;

    final hit = fromMap(current);
    if (hit != null) return hit;

    for (final value in current.values) {
      if (value is Map) {
        queue.add(value);
      }
    }
  }
  return null;
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
