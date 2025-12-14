import 'dart:typed_data';

import 'package:jet_server/jet_server.dart';
import 'package:test/test.dart';

void main() {
  group('http parser', () {
    test('parses request line', () {
      final raw = Uint8List.fromList(
        'GET /hello HTTP/1.1\r\nHost: example\r\n\r\n'.codeUnits,
      );
      final req = parseHttpRequest(raw, raw.length);
      expect(_slice(raw, req.method), 'GET');
      expect(_slice(raw, req.path), '/hello');
      expect(req.keepAlive, isTrue);
    });

    test('detects connection close', () {
      final raw = Uint8List.fromList(
        'GET / HTTP/1.1\r\nHost: ex\r\nConnection: close\r\n\r\n'.codeUnits,
      );
      final req = parseHttpRequest(raw, raw.length);
      expect(req.keepAlive, isFalse);
    });
  });
}

String _slice(Uint8List buf, Slice s) =>
    String.fromCharCodes(buf.sublist(s.start, s.start + s.len));
