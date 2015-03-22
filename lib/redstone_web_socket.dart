library redstone_web_socket;

import "dart:async";
import "dart:mirrors";

import "package:redstone/redstone.dart";
import "package:shelf/shelf.dart" as shelf;
import "package:shelf_web_socket/shelf_web_socket.dart";
import 'package:http_parser/http_parser.dart';
import "package:di/di.dart";
import 'package:logging/logging.dart';

/**
 * An annotation to define a web socket handler.
 *
 * A web socket handler can be a function or a class. If defined
 * as a function, it'll be invoked for every new connection established:
 *
 *      @WebSocketHandler("/ws")
 *      onConnection(websocket) {
 *        websocket.listen((message) {
 *          websocket.add("echo $message");
 *        });
 *      }
 *
 * If the handler is a class, it must provide methods annotated
 * with [OnOpen], [OnMessage], [OnError] or [OnClose].
 *
 */
class WebSocketHandler {

  final String urlPattern;
  final List<String> protocols;
  final List<String> allowedOrigins;

  const WebSocketHandler(this.urlPattern, {this.protocols, this.allowedOrigins});

}

/**
 * Methods annotated with [OnOpen] will be invoked when a new web
 * socket connection is established.
 *
 * Usage:
 *
 *      @OnOpen()
 *      void onOpen(WebSocketSession session) {
 *        ...
 *      }
 *
 *
 */
class OnOpen {

  const OnOpen();

}

/**
 * Methods annotated with [OnMessage] will be invoked when
 * a message is received.
 *
 * Usage:
 *
 *      @OnMessage()
 *      void onMessage(String message, WebSocketSession session) {
 *        ...
 *      }
 *
 */
class OnMessage {

  const OnMessage();

}

/**
 * Methods annotated with [OnError] will be invoked when
 * a error is thrown.
 *
 * Usage:
 *
 *      @OnError()
 *      void onError(Object error, WebSocketSession session) {
 *        ...
 *      }
 *
 */
class OnError {

  const OnError();

}

/**
 * Methods annotated with [OnClose] will be invoked
 * when a connection is closed.
 *
 * Usage:
 *
 *      @OnClose()
 *      void onClose(WebSocketSession session) {
 *        ...
 *      }
 *
 */
class OnClose {

  const OnClose();

}

///A web socket session
class WebSocketSession {

  ///The [attributes] map can be used to share
  ///data between web socket events
  final DynamicMap attributes = new DynamicMap({});

  ///The web socket connection
  final CompatibleWebSocket connection;

  ///The subprotocol associated with this web socket connection
  final String protocol;

  WebSocketSession(this.connection, [this.protocol]);

}

List<_EndPoint> _currentEndPoints = null;

/**
 * A web socket plugin.
 *
 * This plugin will create a web socket endpoint for every
 * function or class annotated with [WebSocketHandler].
 *
 * If [protocols] or [allowedOrigins] are provided, they
 * will be applied to every web socket handler.
 */
RedstonePlugin getWebSocketPlugin({Iterable<String> protocols,
                                   Iterable<String> allowedOrigins}) {

  return (Manager manager) {

    var logger = new Logger("redstone_web_socket");

    _currentEndPoints = null;
    final List<_EndPoint> endPoints = [];

    //scan top level functions
    _installFunctions(manager, endPoints, protocols, allowedOrigins, logger);

    //scan classes
    _installClasses(manager, endPoints, protocols, allowedOrigins, logger);

    //install shelf handler
    var currentShelfHandler = manager.shelfHandler;
    var shelfHandler = (shelf.Request req) {

      var path = req.requestedUri.path;
      var wsEndPoint = endPoints.firstWhere((e) => _testEndPoint(path, e),
                                            orElse: () => null);

      if (wsEndPoint != null) {
        return wsEndPoint.handler(req);
      }

      if (currentShelfHandler != null) {
        return currentShelfHandler(req);
      }

      return new shelf.Response.notFound("not_found");
    };
    manager.shelfHandler = shelfHandler;

    _currentEndPoints = endPoints;

  };
  
}

/**
 * A simple web socket client which can be used in unit tests.
 *
 * See also [openMockConnection].
 */
class MockWebSocket extends Stream implements StreamSink {

  final _MockServerWebSocket _server = new _MockServerWebSocket();

  int get closeCode => _server.closeCode;
  String get closeReason => _server.closeReason;

  @override
  StreamSubscription listen(void onData(event),
                            {Function onError, void onDone(),
                            bool cancelOnError}) {
    return _server._out.stream.listen(onData, onError: onError,
    onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  void add(event) => _server._in.add(event);

  @override
  void addError(errorEvent, [StackTrace stackTrace]) =>
  _server._in.addError(errorEvent, stackTrace);

  Future close([int closeCode = 1005, String closeReason]) {
    _server.closeCode = closeCode;
    _server.closeReason = closeReason;
    return _server._in.close();
  }

  @override
  Future addStream(Stream stream) => _server._in.addStream(stream);

  @override
  Future get done => _server._in.done;

}

/**
 * Initiate a [mockConnection] to [path].
 *
 * Usage:
 *
 *     var conn = new MockConnection();
 *     openMockConnection("/ws", conn);
 *
 */
void openMockConnection(String path, MockWebSocket mockConnection,
                        [String protocol]) {

  var wsEndPoint = _currentEndPoints.firstWhere((e) => _testEndPoint(path, e),
      orElse: () => null);

  if (wsEndPoint == null) {
    throw "no endpoint found for $path.";
  }

  if (wsEndPoint.hasProtocol) {
    wsEndPoint.onConnection(mockConnection._server, protocol);
  } else {
    wsEndPoint.onConnection(mockConnection._server);
  }
}



class _EndPoint {

  final RegExp urlPattern;
  final Function handler;
  final Function onConnection;
  final bool hasProtocol;

  _EndPoint(this.urlPattern, this.handler,
            this.onConnection, this.hasProtocol);

}

class _MockServerWebSocket extends Stream implements CompatibleWebSocket {

  final StreamController _in = new StreamController();
  final StreamController _out = new StreamController();

  int closeCode;
  String closeReason;
  Duration pingInterval;

  @override
  StreamSubscription listen(void onData(event),
                            {Function onError, void onDone(),
                            bool cancelOnError}) {
    return _in.stream.listen(onData, onError: onError,
    onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  void add(event) => _out.add(event);

  @override
  void addError(errorEvent, [StackTrace stackTrace]) =>
    _out.addError(errorEvent, stackTrace);

  @override
  Future close([int closeCode = 1005, String closeReason]) {
    this.closeCode = closeCode;
    this.closeReason = closeReason;
    return _out.close();
  }

  @override
  Future addStream(Stream stream) => _out.addStream(stream);

  @override
  Future get done => _out.done;

}

void _installFunctions(Manager manager, List<_EndPoint> endPoints,
                       List<String> protocols, List<String> allowedOrigins,
                       Logger logger) {

  var functions = manager.findFunctions(WebSocketHandler);

  functions.forEach((annotateType) {

    MethodMirror method = annotateType.mirror;
    LibraryMirror lib = method.owner;
    WebSocketHandler metadata = annotateType.metadata;

    var pattern = new RegExp(metadata.urlPattern);
    var endPointProtocols = metadata.protocols != null ?
    metadata.protocols : protocols;
    var endPointAllowedOrigins = metadata.allowedOrigins != null ?
    metadata.allowedOrigins : allowedOrigins;

    var onConnection;
    var hasProtocol = false;

    if (method.parameters.length == 1) {
      onConnection = (websocket) =>
      lib.invoke(method.simpleName, [websocket]);
    } else {
      hasProtocol = true;
      onConnection = (websocket, protocol) =>
      lib.invoke(method.simpleName, [websocket, protocol]);
    }

    var handler = webSocketHandler(onConnection,
    protocols: endPointProtocols,
    allowedOrigins: endPointAllowedOrigins);

    endPoints.add(new _EndPoint(pattern, handler, onConnection, hasProtocol));

    var handlerName = MirrorSystem.getName(method.qualifiedName);
    logger.info("configured websocket handler for ${metadata.urlPattern}: $handlerName");
  });

}

void _installClasses(Manager manager, List<_EndPoint> endPoints,
                     List<String> protocols, List<String> allowedOrigins,
                     Logger logger) {

  var classes = manager.findClasses(WebSocketHandler);

  var module = new Module();
  classes.forEach((t) => module.bind(t.mirror.reflectedType));
  var injector = manager.createInjector([module]);

  classes.forEach((annotatedType) {

    ClassMirror clazz = annotatedType.mirror;
    WebSocketHandler metadata = annotatedType.metadata;

    var objMirror = reflect(injector.get(clazz.reflectedType));

    var onOpen = _getHandler(manager, clazz, OnOpen);
    var onMessage = _getHandler(manager, clazz, OnMessage);
    var onError = _getHandler(manager, clazz, OnError);
    var onClose = _getHandler(manager, clazz, OnClose);

    var pattern = new RegExp(metadata.urlPattern);
    var endPointProtocols = metadata.protocols != null ?
    metadata.protocols : protocols;
    var endPointAllowedOrigins = metadata.allowedOrigins != null ?
    metadata.allowedOrigins : allowedOrigins;

    var onConnection = (CompatibleWebSocket websocket, String protocol) {

      var session = new WebSocketSession(websocket, protocol);

      _invokeHandler(objMirror, onOpen, [session]);

      websocket.listen((event) {
        _invokeHandler(objMirror, onMessage, [event, session]);
      }, onError: (error) {
        _invokeHandler(objMirror, onError, [error, session]);
      }, onDone: () {
        _invokeHandler(objMirror, onClose, [session]);
      });

    };

    var hasProtocol = true;
    if (endPointProtocols == null) {
      hasProtocol = false;
      var f = onConnection;
      onConnection = (websocket) => f(websocket, null);
    }

    var handler = webSocketHandler(onConnection,
      protocols: endPointProtocols,
      allowedOrigins: endPointAllowedOrigins);

    endPoints.add(new _EndPoint(pattern, handler, onConnection, hasProtocol));

    var handlerName = MirrorSystem.getName(clazz.qualifiedName);
    logger.info("configured websocket handler for ${metadata.urlPattern}: $handlerName");
  });

}

bool _testEndPoint(String requestedUrl, _EndPoint endPoint) {
  var match = endPoint.urlPattern.firstMatch(requestedUrl);
  if (match != null) {
    return match[0] == requestedUrl;
  }
  return false;
}

MethodMirror _getHandler(Manager manager, ClassMirror clazz,
                                        Type annotation) {
  var methods = manager.findMethods(clazz, annotation);
  if (methods.isEmpty) {
    return null;
  }
  return methods.first.mirror;
}

void _invokeHandler(InstanceMirror objMirror,
                    MethodMirror handler,
                    List arguments) {
  if (handler == null) {
    return;
  }

  var params = handler.parameters.length;
  if (params < arguments.length) {
    arguments = arguments.sublist(0, params);
  }

  objMirror.invoke(handler.simpleName, arguments);

}