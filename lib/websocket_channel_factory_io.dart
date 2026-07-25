import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Native (IO) websocket: bearer token in the Authorization header.
Future<WebSocketChannel> openWebSocketChannel(
  Uri uri, {
  required String token,
}) async {
  return IOWebSocketChannel.connect(
    uri,
    headers: {'Authorization': 'Bearer $token'},
  );
}
