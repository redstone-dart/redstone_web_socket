library redstone_services;

import 'package:redstone_web_socket/redstone_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

List<String> wsEvents;

@WebSocketHandler("/ws")
websocketHandler(WebSocketChannel webSocketChannel) {
  webSocketChannel.stream.listen((event) {
    wsEvents.add("server_received_$event");
    webSocketChannel.sink.add("pong");
    wsEvents.add("server_sent_pong");
  });
}

@WebSocketHandler("/ws-protocol", protocols: const ["protocol_test"])
handlerWithProtocol(WebSocketChannel webSocketChannel, protocol) {
  webSocketChannel.sink.add("protocol: $protocol");
}

@WebSocketHandler("/ws-class")
class WebSocketClass {
  @OnOpen()
  void onOpen(WebSocketSession session) {
    wsEvents.add("open");
  }

  @OnMessage()
  void onMessage(String message, WebSocketSession session) {
    wsEvents.add("server_received_$message");
    session.connection.sink.add("pong");
    wsEvents.add("server_sent_pong");
  }

  @OnError()
  void onError(error, WebSocketSession session) {
    wsEvents.add("server_received_$error");
  }

  @OnClose()
  void onClose(WebSocketSession session) {
    wsEvents.add("close");
  }

}

