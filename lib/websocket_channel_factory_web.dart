import 'package:web_socket_channel/web_socket_channel.dart';

/// Web websocket: browsers cannot set Authorization headers, so pass `tk`.
/// Preserves existing query params such as `namespace`.
Future<WebSocketChannel> openWebSocketChannel(
  Uri uri, {
  required String token,
}) async {
  final withToken = uri.replace(
    queryParameters: {...uri.queryParameters, 'tk': token},
  );
  return WebSocketChannel.connect(withToken);
}
