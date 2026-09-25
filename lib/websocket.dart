import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:solwatt/network.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:solwatt/websocket_channel_factory.dart';

final _log = Logger('SolWatt.WebSocket');

/// Connection lifecycle for the Solar Network websocket gateway (`/ws`).
enum WebSocketConnectionState {
  disconnected,
  connecting,
  connected,
  serverDown,
  error,
}

/// On-wire packet from Blade (`type` + optional JSON `data`).
class WebSocketPacket {
  const WebSocketPacket({
    required this.type,
    this.data,
    this.endpoint,
    this.errorMessage,
  });

  final String type;
  final Map<String, dynamic>? data;
  final String? endpoint;
  final String? errorMessage;

  factory WebSocketPacket.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    Map<String, dynamic>? data;
    if (rawData is Map) {
      data = Map<String, dynamic>.from(rawData);
    }
    return WebSocketPacket(
      type: json['type']?.toString() ?? '',
      data: data,
      endpoint: json['endpoint']?.toString(),
      errorMessage:
          json['error_message']?.toString() ?? json['errorMessage']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    if (data != null) 'data': data,
    if (endpoint != null) 'endpoint': endpoint,
    if (errorMessage != null) 'error_message': errorMessage,
  };
}

/// Authenticated client for the Solar Network websocket gateway.
///
/// Connects to `{api}/ws` with the OAuth bearer (header on native, `tk` query
/// on web), heartbeats with `ping`/`pong`, and reconnects with backoff.
class WebSocketService {
  WebSocketService(this._authenticator);

  final SolarNetworkAuthenticator _authenticator;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  final _packets = StreamController<WebSocketPacket>.broadcast();
  final _status = StreamController<WebSocketConnectionState>.broadcast();

  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _connectionGeneration = 0;
  var _isClosing = false;
  var _isConnecting = false;
  var _wantConnected = false;
  var _reconnectCount = 0;
  DateTime? _reconnectWindowStart;
  DateTime? _heartbeatAt;
  Duration? heartbeatDelay;

  static const _maxReconnectsPerMinute = 5;
  static const _baseReconnectDelay = Duration(milliseconds: 500);
  static const _maxReconnectDelay = Duration(seconds: 30);

  Stream<WebSocketPacket> get dataStream => _packets.stream;
  Stream<WebSocketConnectionState> get statusStream => _status.stream;

  WebSocketConnectionState _currentState =
      WebSocketConnectionState.disconnected;
  WebSocketConnectionState get currentState => _currentState;

  Future<void> connect() async {
    _wantConnected = true;
    _isClosing = false;
    if (_isConnecting) {
      _log.fine('Connect already in progress; skipping');
      return;
    }
    await _connectInternal();
  }

  Future<void> disconnect() async {
    _wantConnected = false;
    _isClosing = true;
    _cancelTimers();
    await _disposeActiveChannel();
    _setStatus(WebSocketConnectionState.disconnected);
    _isClosing = false;
  }

  Future<void> _connectInternal() async {
    _isConnecting = true;
    final generation = ++_connectionGeneration;
    await _disposeActiveChannel();

    _setStatus(WebSocketConnectionState.connecting);

    final session = await _authenticator.validSession();
    final token = session?.accessToken;
    if (token == null || token.isEmpty) {
      _log.warning('No session token; not connecting websocket');
      _isConnecting = false;
      _setStatus(WebSocketConnectionState.disconnected);
      return;
    }

    // Blade multi-tenant isolation: same product id as Ring `app` /
    // `app_id`. Empty namespace would land in `_default` and mix with Solian.
    // See Blade docs/WEBSOCKET_GATEWAY.md.
    final uri = Uri.parse(
      '$kSolarNetworkApiBase/ws'.replaceFirst('http', 'ws'),
    ).replace(queryParameters: {'namespace': kWebsocketNamespace});
    _log.info('Connecting to $uri (namespace=$kWebsocketNamespace)');

    try {
      final channel = await openWebSocketChannel(uri, token: token);
      _channel = channel;
      await channel.ready;
      _isConnecting = false;

      if (generation != _connectionGeneration || !_wantConnected) {
        await channel.sink.close();
        return;
      }

      _reconnectCount = 0;
      _reconnectWindowStart = null;
      _setStatus(WebSocketConnectionState.connected);
      _scheduleHeartbeat();

      _channelSubscription = channel.stream.listen(
        (raw) {
          if (generation != _connectionGeneration) return;
          _handleRawMessage(raw);
        },
        onDone: () {
          if (generation != _connectionGeneration || _isClosing) return;
          _log.info('Connection closed; scheduling reconnect');
          _setStatus(WebSocketConnectionState.disconnected);
          _scheduleReconnect();
        },
        onError: (Object error, StackTrace stack) {
          if (generation != _connectionGeneration || _isClosing) return;
          _log.severe('Stream error: $error', error, stack);
          _setStatus(WebSocketConnectionState.error);
          _scheduleReconnect();
        },
      );
    } catch (error, stack) {
      if (generation != _connectionGeneration || _isClosing) return;
      _isConnecting = false;
      _log.severe('Failed to connect: $error', error, stack);
      _setStatus(WebSocketConnectionState.error);
      _scheduleReconnect();
    }
  }

  void _handleRawMessage(dynamic raw) {
    String text;
    try {
      if (raw is String) {
        text = raw;
      } else if (raw is Uint8List) {
        text = utf8.decode(raw);
      } else if (raw is List<int>) {
        text = utf8.decode(raw);
      } else {
        text = raw.toString();
      }
    } catch (error) {
      _log.warning('Failed to decode frame: $error');
      return;
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        _log.warning('Ignoring non-object packet');
        return;
      }
      final packet = WebSocketPacket.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (packet.type.isEmpty) return;

      if (packet.type == 'error.dupe') {
        _log.warning('Duplicate device: ${packet.errorMessage}');
        _wantConnected = false;
        _cancelTimers();
        _setStatus(WebSocketConnectionState.error);
        unawaited(_channel?.sink.close() ?? Future<void>.value());
        return;
      }
      if (packet.type == 'error') {
        _log.warning('Gateway error: ${packet.errorMessage}');
        // Keep the socket; some errors are soft.
      }

      if (!_packets.isClosed) {
        _packets.add(packet);
      }

      if (packet.type == 'pong' && _heartbeatAt != null) {
        heartbeatDelay = DateTime.now().difference(_heartbeatAt!);
        _log.fine('Pong RTT ${heartbeatDelay!.inMilliseconds} ms');
      }
    } catch (error) {
      _log.warning('Failed to parse packet: $error');
    }
  }

  void _scheduleHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _beat();
    });
  }

  void _beat() {
    if (_channel == null || _isClosing) return;
    _heartbeatAt = DateTime.now();
    sendMessage(const WebSocketPacket(type: 'ping'));
  }

  bool sendMessage(WebSocketPacket packet) {
    final channel = _channel;
    if (channel == null || _isClosing) return false;
    try {
      channel.sink.add(jsonEncode(packet.toJson()));
      return true;
    } catch (error) {
      _log.warning('Failed to send: $error');
      return false;
    }
  }

  void _scheduleReconnect() {
    if (!_wantConnected || _isClosing) return;

    final now = DateTime.now();
    if (_reconnectWindowStart == null ||
        now.difference(_reconnectWindowStart!).inMinutes >= 1) {
      _reconnectWindowStart = now;
      _reconnectCount = 0;
    }
    _reconnectCount++;

    if (_reconnectCount > _maxReconnectsPerMinute) {
      _log.severe('Reconnect rate limit hit; retrying in 30s');
      _setStatus(WebSocketConnectionState.serverDown);
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 30), () {
        if (!_wantConnected || _isClosing) return;
        _reconnectWindowStart = null;
        _reconnectCount = 0;
        unawaited(connect());
      });
      return;
    }

    final backoffMs =
        (_baseReconnectDelay.inMilliseconds * (1 << (_reconnectCount - 1)))
            .clamp(
              _baseReconnectDelay.inMilliseconds,
              _maxReconnectDelay.inMilliseconds,
            );
    final jitter = Random().nextInt(200) - 100;
    final delayMs = (backoffMs + jitter).clamp(
      100,
      _maxReconnectDelay.inMilliseconds,
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!_wantConnected || _isClosing) return;
      unawaited(connect());
    });
  }

  void manualReconnect() {
    if (!_wantConnected) {
      unawaited(connect());
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectCount = 0;
    _reconnectWindowStart = null;
    _connectionGeneration++;
    unawaited(() async {
      await _disposeActiveChannel();
      await connect();
    }());
  }

  void _setStatus(WebSocketConnectionState state) {
    _currentState = state;
    if (!_status.isClosed) {
      _status.add(state);
    }
  }

  void _cancelTimers() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatAt = null;
    heartbeatDelay = null;
  }

  Future<void> _disposeActiveChannel() async {
    _cancelTimers();
    try {
      await _channelSubscription?.cancel().timeout(
        const Duration(milliseconds: 200),
      );
    } catch (_) {
      // Ignore cancel timeouts.
    } finally {
      _channelSubscription = null;
    }
    try {
      await _channel?.sink.close().timeout(const Duration(milliseconds: 300));
    } catch (_) {
      // Ignore close timeouts.
    } finally {
      _channel = null;
    }
    _isConnecting = false;
  }

  Future<void> dispose() async {
    _wantConnected = false;
    _isClosing = true;
    await _disposeActiveChannel();
    await _packets.close();
    await _status.close();
  }
}

final websocketServiceProvider = Provider<WebSocketService>((ref) {
  final service = WebSocketService(ref.watch(authenticatorProvider));
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});

/// Live connection state for UI indicators.
final websocketStateProvider =
    NotifierProvider<WebSocketStateNotifier, WebSocketConnectionState>(
      WebSocketStateNotifier.new,
    );

class WebSocketStateNotifier extends Notifier<WebSocketConnectionState> {
  StreamSubscription<WebSocketConnectionState>? _sub;

  @override
  WebSocketConnectionState build() {
    final service = ref.watch(websocketServiceProvider);
    _sub?.cancel();
    _sub = service.statusStream.listen((event) {
      state = event;
    });
    ref.onDispose(() {
      _sub?.cancel();
    });
    return service.currentState;
  }

  Future<void> connect() => ref.read(websocketServiceProvider).connect();

  Future<void> disconnect() => ref.read(websocketServiceProvider).disconnect();

  void manualReconnect() =>
      ref.read(websocketServiceProvider).manualReconnect();
}
