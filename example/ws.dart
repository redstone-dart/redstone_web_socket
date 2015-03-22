library ws_example;

import 'package:redstone/redstone.dart';
import 'package:redstone_web_socket/redstone_web_socket.dart';

@WebSocketHandler("/ws")
class ServerEndPoint {

  @OnOpen()
  void onOpen(WebSocketSession session) {
    print("connection established");
  }

  @OnMessage()
  void onMessage(String message, WebSocketSession session) {
    print("message received: $message");
    session.connection.add("pong");
  }

  @OnError()
  void onError(error, WebSocketSession session) {
    print("error: $error");
  }

  @OnClose()
  void onClose(WebSocketSession session) {
    print("connection closed");
  }

}

@Route('/', responseType: "text/html; charset=utf-8;")
index() => """<!DOCTYPE html>
<html>
  <head lang="en">
    <meta charset="UTF-8">
    <title>redstone_web_socket example</title>
  </head>
  <body>
    <h1>redstone_web_socket example</h1>
    <script>
      var connection = new WebSocket('ws://localhost:8080/ws');
      connection.onopen = function () {
        connection.send('ping');
      };
      connection.onmessage = function (e) {
        console.log('Client: ' + e.data);
      };
    </script>
  </body>
</html>""";

void main() {
  setupConsoleLog();
  addPlugin(getWebSocketPlugin());
  start();
}
