import 'dart:typed_data';

import 'package:jet_server/jet_server.dart';

Uint8List handle(HttpRequest req) {
  const body = 'hello, jet';
  final headers =
      'HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\nConnection: keep-alive\r\nContent-Type: text/plain\r\n\r\n';
  final bytes = Uint8List(headers.length + body.length);
  bytes.setAll(0, headers.codeUnits);
  bytes.setAll(headers.length, body.codeUnits);
  return bytes;
}

void main() {
  final server = JetServer(handler: handle, port: 3000, bufferSize: 16 * 1024);
  server.serve();
}
