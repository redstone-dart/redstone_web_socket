library redstone_web_socket;

import "dart:async";
import "dart:mirrors";

import "package:redstone/server.dart";
import "package:redstone/query_map.dart";
import "package:shelf/shelf.dart" as shelf;
import "package:shelf_web_socket/shelf_web_socket.dart";
import 'package:http_parser/http_parser.dart';
import "package:di/di.dart";
import 'package:logging/logging.dart';

/**
 *
 *
 */
class WebSocketHandler {

  final String urlPattern;
  final List<String> protocols;
  final List<String> allowedOrigins;

  const WebSocketHandler(this.urlPattern, {this.protocols, this.allowedOrigins});

}

/**
 *
 *
 */
class OnOpen {

  const OnOpen();

}

/**
 *
 *
 */
class OnMessage {

  const OnMessage();

}

/**
 *
 *
 */
class OnError {

  const OnError();

}

/**
 *
 *
 */
class OnClose {

  const OnClose();

}

/**
 *
 *
 */
class WebSocketSession {

  final QueryMap attributes = new QueryMap({});
  final CompatibleWebSocket connection;
  final String protocol;

  WebSocketSession(this.connection, [this.protocol]);

}

List<_EndPoint> _currentEndPoints = null;

/**
 *
 * 
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
    var currentShelfHandler = manager.getShelfHandler();
    var shelfHandler = (shelf.Request req) {

      var path = req.url.path;
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
    manager.setShelfHandler(shelfHandler);

    _currentEndPoints = endPoints;

  };
  
}

/**
 *
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
    LibraryMirror lib = clazz.owner;
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