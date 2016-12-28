library web_socket_tests;

import 'dart:async';

import 'package:redstone/redstone.dart';
import 'package:redstone_web_socket/redstone_web_socket.dart';
import 'package:test/test.dart';

import 'redstone_services.dart';

main() {
  setUp(() async {
    wsEvents = [];
    addPlugin(getWebSocketPlugin());
    await redstoneSetUp([#redstone_services]);
  });

  group("function handler: ", () {
    test("messages", () {
      var completer = new Completer();
      var socket = new MockWebSocket();

      socket.listen((event) {
        wsEvents.add("client_received_$event");

        expect(
            wsEvents, equals(["client_sent_ping", "server_received_ping", "server_sent_pong", "client_received_pong"]));

        completer.complete();
      });

      openMockConnection("/ws", socket);

      socket.add("ping");
      wsEvents.add("client_sent_ping");

      return completer.future;
    });

    test("open connection w/ protocol", () {
      var completer = new Completer();
      var socket = new MockWebSocket();

      socket.listen((event) {
        expect(event, equals("protocol: protocol_test"));
        completer.complete();
      });

      openMockConnection("/ws-protocol", socket, "protocol_test");

      return completer.future;
    });
  });

  test("class handler", () {
    var completer = new Completer();
    var socket = new MockWebSocket();

    socket.listen((event) {
      wsEvents.add("client_received_$event");
      socket.addError("error");
      wsEvents.add("socket_error");
      wsEvents.add("client_closed");

      socket.close().then((_) {
        expect(
            wsEvents,
            equals([
              "open",
              "client_sent_ping",
              "server_received_ping",
              "server_sent_pong",
              "client_received_pong",
              "socket_error",
              "client_closed",
              "server_received_error",
              "close"
            ]));

        completer.complete();
      });
    });

    openMockConnection("/ws-class", socket);
    socket.add("ping");
    wsEvents.add("client_sent_ping");

    return completer.future;
  });
}
