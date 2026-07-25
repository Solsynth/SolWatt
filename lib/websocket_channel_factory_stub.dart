import 'package:web_socket_channel/web_socket_channel.dart';

Future<WebSocketChannel> openWebSocketChannel(
  Uri uri, {
  required String token,
}) {
  throw UnsupportedError('WebSocket is not supported on this platform.');
}
