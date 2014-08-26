library redstone_services;

import 'package:redstone/server.dart' as app;
import 'package:redstone_web_socket/redstone_web_socket.dart';

List<String> wsEvents;

@WebSocketHandler("/ws")
websocketHandler(websocket) {
  websocket.listen((event) {
    wsEvents.add("server_received_$event");
    websocket.add("pong");
    wsEvents.add("server_sent_pong");
  });
}

@WebSocketHandler("/ws-protocol", protocols: const ["protocol_test"])
handlerWithProtocol(websocket, protocol) {
  websocket.add("protocol: $protocol");
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
    session.connection.add("pong");
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

