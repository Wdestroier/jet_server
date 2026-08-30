import 'dart:io';
import 'dart:typed_data';

import 'package:jet_server/jet_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

void main(List<String> args) async {
  final server = _arg(args, '--server')!;
  final port = int.parse(_arg(args, '--port')!);

  if (server == 'jet') {
    _runJet(port);
  } else if (server == 'shelf') {
    await _runShelf(port);
  } else {
    stdout.writeln('Unknown server "$server". Use --server=jet|shelf');
    exit(64);
  }
}

void _runJet(int port) {
  stdout.writeln('Starting jet_server on $port');
  JetServer(handler: _helloJet, port: port, bufferSize: 16 * 1024).serve();
}

Uint8List _helloJet(HttpRequest req) {
  const body = 'hello from jet';
  final headers =
      'HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\nConnection: keep-alive\r\nContent-Type: text/plain\r\n\r\n';
  return Uint8List(headers.length + body.length)
    ..setAll(0, headers.codeUnits)
    ..setAll(headers.length, body.codeUnits);
}

Future<void> _runShelf(int port) async {
  final router = Router()..get('/', _helloShelf);
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);
  final srv = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('Starting shelf on ${srv.port}');
}

Response _helloShelf(Request request) {
  return Response.ok('hello from shelf');
}

String? _arg(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('$name=')) {
      return a.split('=').last;
    }
  }
  return null;
}
