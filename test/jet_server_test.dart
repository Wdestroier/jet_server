import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as ffi show calloc;
import 'package:jet_server/jet_server.dart';
import 'package:jet_server/src/syscall.dart' as sys;
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

    test('finds header end and reports incomplete', () {
      final full = Uint8List.fromList(
        'GET / HTTP/1.1\r\nHost: x\r\n\r\n'.codeUnits,
      );
      expect(findHeadersEnd(full, 0, full.length), full.length);
      final frag = Uint8List.fromList(
        'GET / HTTP/1.1\r\nHost: x\r\n'.codeUnits,
      );
      expect(findHeadersEnd(frag, 0, frag.length), -1);
    });

    test('parses pipelined requests', () {
      final raw = Uint8List.fromList(
        'GET / HTTP/1.1\r\nHost: x\r\n\r\n'
        'GET /user/42 HTTP/1.1\r\nHost: x\r\n\r\n'
            .codeUnits,
      );
      final e1 = findHeadersEnd(raw, 0, raw.length);
      expect(e1, greaterThan(0));
      final p1 = parseOne(raw, 0, e1);
      expect(_slice(raw, p1.path), '/');
      expect(p1.keepAlive, isTrue);
      final e2 = findHeadersEnd(raw, e1, raw.length);
      expect(e2, raw.length);
      final p2 = parseOne(raw, e1, e2);
      expect(_slice(raw, p2.path), '/user/42');
    });

    test('reads content length and keeps http/1.0 closed', () {
      final post = Uint8List.fromList(
        'POST /user HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nhello'
            .codeUnits,
      );
      final he = findHeadersEnd(post, 0, post.length - 5);
      expect(he, greaterThan(0));
      final p = parseOne(post, 0, he);
      expect(p.contentLength, 5);
      expect(p.keepAlive, isTrue);

      final http10 = Uint8List.fromList(
        'GET / HTTP/1.0\r\nHost: x\r\n\r\n'.codeUnits,
      );
      final p10 = parseOne(
        http10,
        0,
        findHeadersEnd(http10, 0, http10.length),
      );
      expect(p10.keepAlive, isFalse);
    });
  });

  group('epoll event layout', () {
    test('uses the kernel 12-byte stride, not the 16-byte FFI stride', () {
      // Regression test: Dart FFI lays `struct epoll_event` out as 16 bytes
      // (natural alignment) while Linux uses 12 bytes (packed). Reading a
      // batch with stride 16 corrupts every entry after the first, which
      // collapsed throughput under concurrency.
      expect(ffi.sizeOf<sys.EpollEvent>(), isNot(12));
      final batch = ffi.calloc<ffi.Uint8>(2 * sys.epollEventStride);
      try {
        sys.storeCtlEvent(batch, 0x001, 7);
        sys.storeCtlEvent(batch + sys.epollEventStride, 0x005, 9);
        expect(sys.loadEventMask(batch, 0), 0x001);
        expect(sys.loadEventFd(batch, 0), 7);
        expect(sys.loadEventMask(batch, 1), 0x005);
        expect(sys.loadEventFd(batch, 1), 9);
      } finally {
        ffi.calloc.free(batch);
      }
    });
  });
}

String _slice(Uint8List buf, Slice s) =>
    String.fromCharCodes(buf.sublist(s.start, s.start + s.len));
