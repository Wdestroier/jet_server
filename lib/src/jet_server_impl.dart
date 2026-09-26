import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as ffi show calloc;

import 'buffer_pool.dart';
import 'http_parser.dart';
import 'constants.dart';
import 'syscall.dart' as sys;

typedef RequestHandler = Uint8List Function(HttpRequest req);

/// Per-connection receive stash. Holds bytes that arrived but have not yet
/// formed a complete request (fragmentation) or extra pipelined bytes.
final class _Conn {
  Uint8List buf;
  int start = 0;
  int end = 0;

  _Conn(int cap) : buf = Uint8List(cap);

  int get length => end - start;

  void ensure(int needed) {
    if (needed <= buf.length) return;
    var cap = buf.length * 2;
    while (cap < needed) {
      cap *= 2;
    }
    if (cap > (1 << 20)) {
      throw const FormatException('header too large');
    }
    final next = Uint8List(cap);
    next.setRange(0, end - start, buf, start);
    end -= start;
    start = 0;
    buf = next;
  }

  void compact() {
    if (start == 0) return;
    if (start == end) {
      start = 0;
      end = 0;
      return;
    }
    buf.setRange(0, end - start, buf, start);
    end -= start;
    start = 0;
  }
}

final class _Pending {
  final Uint8List bytes;
  int offset = 0;
  final bool closeAfter;

  _Pending(this.bytes, {this.closeAfter = false});
}

final class JetServer {
  final int port;
  final RequestHandler handler;
  final int maxEvents;
  final int backlog;
  final int bufferSize;
  final bool reusePort;
  final bool enableTcpFastOpen;
  final BufferPool _pool;

  JetServer({
    required this.handler,
    this.port = 3000,
    this.maxEvents = 4096,
    this.backlog = 4096,
    this.bufferSize = 8192,
    this.reusePort = true,
    this.enableTcpFastOpen = true,
    BufferPool? pool,
  }) : _pool = pool ?? BufferPool(bufferSize: bufferSize, capacity: 16) {
    if (!Platform.isLinux) {
      throw UnsupportedError('JetServer targets Linux/WSL only.');
    }
  }

  /// Starts the blocking epoll loop. Call from a dedicated isolate for best throughput.
  void serve() {
    final serverFd = sys.socketTcp();
    if (serverFd < 0) {
      throw Exception('socket() failed errno=${sys.errnoValue()}');
    }
    sys.setSockOptInt(serverFd, solSocket, soReuseAddr, 1);
    if (reusePort) {
      sys.setSockOptInt(serverFd, solSocket, soReusePort, 1);
    }
    if (enableTcpFastOpen) {
      // Queue length 16 is a sane default; value 1 starves under burst.
      sys.setSockOptInt(serverFd, tcpLevel, tcpFastOpen, 16);
    }
    final rcBind = sys.bindAny(serverFd, port);
    if (rcBind != 0) {
      final e = sys.errnoValue();
      sys.closeFd(serverFd);
      throw Exception('bind(:$port) failed rc=$rcBind errno=$e');
    }
    final rcListen = sys.listenFd(serverFd, backlog);
    if (rcListen != 0) {
      final e = sys.errnoValue();
      sys.closeFd(serverFd);
      throw Exception('listen() failed rc=$rcListen errno=$e');
    }

    final epfd = sys.epollCreate();
    if (epfd < 0) {
      sys.closeFd(serverFd);
      throw Exception('epoll_create1 failed errno=${sys.errnoValue()}');
    }
    sys.epollAdd(epfd, serverFd, epollIn);

    final events = sys.allocEvents(maxEvents);

    // Per-loop scratch: one recv buffer + one send buffer, reused for every
    // request. No per-request malloc in the hot path.
    final recvSize = 64 * 1024;
    final recvPtr = ffi.calloc<ffi.Uint8>(recvSize);
    final recvView = recvPtr.asTypedList(recvSize);
    final sendSize = 64 * 1024;
    final sendPtr = ffi.calloc<ffi.Uint8>(sendSize);
    final ctlEv = ffi.calloc<ffi.Uint8>(sys.epollEventStride);
    final optCell = ffi.calloc<ffi.Int32>();
    final conns = <int, _Conn>{};
    final pending = <int, _Pending>{};

    try {
      _loop(
        epfd,
        serverFd,
        events,
        recvPtr,
        recvView,
        recvSize,
        sendPtr,
        sendSize,
        ctlEv,
        optCell,
        conns,
        pending,
      );
    } finally {
      ffi.calloc.free(recvPtr);
      ffi.calloc.free(sendPtr);
      ffi.calloc.free(ctlEv);
      ffi.calloc.free(optCell);
      sys.freeEvents(events);
      sys.closeFd(serverFd);
      sys.closeFd(epfd);
      _pool.dispose();
    }
  }

  @pragma('vm:unsafe:no-interrupts')
  void _loop(
    int epfd,
    int serverFd,
    ffi.Pointer<ffi.Uint8> events,
    ffi.Pointer<ffi.Uint8> recvPtr,
    Uint8List recvView,
    int recvSize,
    ffi.Pointer<ffi.Uint8> sendPtr,
    int sendSize,
    ffi.Pointer<ffi.Uint8> ctlEv,
    ffi.Pointer<ffi.Int32> optCell,
    Map<int, _Conn> conns,
    Map<int, _Pending> pending,
  ) {
    while (true) {
      final n = sys.epollWait(epfd, events, maxEvents, -1);
      if (n <= 0) {
        continue;
      }
      for (var i = 0; i < n; i++) {
        final mask = sys.loadEventMask(events, i);
        final fd = sys.loadEventFd(events, i);
        if (fd == serverFd) {
          _drainAccept(epfd, ctlEv, optCell, serverFd);
          continue;
        }
        if ((mask & (epollErr | epollHup)) != 0) {
          _closeClient(epfd, fd, conns, pending);
          continue;
        }
        // Flush pending writes first (EPOLLOUT or IN|OUT).
        if ((mask & epollOut) != 0) {
          final done = _flushPending(
              epfd, fd, sendPtr, sendSize, ctlEv, conns, pending);
          if (!done) {
            continue; // still blocked; keep EPOLLOUT armed.
          }
          // Pending drained: fall through to read if IN is also ready,
          // otherwise re-process any stashed pipelined bytes.
          if ((mask & epollIn) == 0) {
            final c = conns[fd];
            if (c != null && c.length > 0) {
              _processStash(epfd, fd, c, conns, pending, sendPtr, sendSize, ctlEv);
            }
            continue;
          }
        }
        if ((mask & (epollIn | epollRdhup)) != 0) {
          _handleRead(
            epfd,
            fd,
            conns,
            pending,
            recvPtr,
            recvView,
            recvSize,
            sendPtr,
            sendSize,
            ctlEv,
          );
        }
      }
    }
  }

  void _drainAccept(
    int epfd,
    ffi.Pointer<ffi.Uint8> ctlEv,
    ffi.Pointer<ffi.Int32> optCell,
    int serverFd,
  ) {
    while (true) {
      final fd = sys.acceptConn(serverFd);
      if (fd < 0) {
        // EAGAIN / EWOULDBLOCK stops the loop.
        break;
      }
      // accept4 already applied SOCK_NONBLOCK; no fcntl round-trip needed.
      // Disable Nagle: tiny benchmark responses must not wait for ACKs.
      sys.setSockOptIntFast(fd, tcpLevel, tcpNoDelay, 1, optCell);
      sys.epollAddReuse(epfd, fd, epollIn | epollRdhup, ctlEv);
    }
  }

  void _handleRead(
    int epfd,
    int fd,
    Map<int, _Conn> conns,
    Map<int, _Pending> pending,
    ffi.Pointer<ffi.Uint8> recvPtr,
    Uint8List recvView,
    int recvSize,
    ffi.Pointer<ffi.Uint8> sendPtr,
    int sendSize,
    ffi.Pointer<ffi.Uint8> ctlEv,
  ) {
    // While a previous response is still blocked, preserve order: don't
    // consume more input until the pending bytes drain.
    if (pending.containsKey(fd)) {
      return;
    }
    final conn = conns[fd] ??= _Conn(8192);

    // Drain until EAGAIN (level-triggered, so a short drain is still safe,
    // but a full drain minimizes wakeups).
    while (true) {
      final rc = sys.recvInto(fd, recvPtr, recvSize);
      if (rc > 0) {
        try {
          conn.ensure(conn.end + rc);
        } catch (_) {
          _sendClose(epfd, fd, _tiny400, conns, pending, sendPtr, sendSize, ctlEv);
          return;
        }
        conn.buf.setRange(conn.end, conn.end + rc, recvView, 0);
        conn.end += rc;
        if (rc < recvSize) {
          // Socket drained for now (heuristic + LT safety: LT re-fires if
          // more arrives, so stopping here is correct).
          break;
        }
        // rc == recvSize: buffer may hold more; loop to EAGAIN.
        // Guard against unbounded single-read growth (slowloris / huge body).
        if (conn.end - conn.start > (1 << 20)) {
          _sendClose(epfd, fd, _tiny400, conns, pending, sendPtr, sendSize, ctlEv);
          return;
        }
      } else if (rc == 0) {
        _closeClient(epfd, fd, conns, pending);
        return;
      } else {
        final err = sys.errnoValue();
        if (err == eAgain) {
          break;
        }
        _closeClient(epfd, fd, conns, pending);
        return;
      }
    }

    if (conn.length == 0) {
      // Spurious wakeup: must NOT close a healthy keep-alive connection.
      return;
    }

    _processStash(epfd, fd, conn, conns, pending, sendPtr, sendSize, ctlEv);
  }

  /// Parses and responds to every complete pipelined request in [conn].
  void _processStash(
    int epfd,
    int fd,
    _Conn conn,
    Map<int, _Conn> conns,
    Map<int, _Pending> pending,
    ffi.Pointer<ffi.Uint8> sendPtr,
    int sendSize,
    ffi.Pointer<ffi.Uint8> ctlEv,
  ) {
    while (true) {
      if (pending.containsKey(fd)) {
        return; // preserve response order.
      }
      final start = conn.start;
      final end = conn.end;
      if (start == end) {
        conn.start = 0;
        conn.end = 0;
        return;
      }
      final headerEnd = findHeadersEnd(conn.buf, start, end);
      if (headerEnd < 0) {
        if (end - start > 64 * 1024) {
          _sendClose(epfd, fd, _tiny400, conns, pending, sendPtr, sendSize, ctlEv);
          return;
        }
        conn.compact();
        return; // wait for more bytes.
      }
      ParsedRequest parsed;
      try {
        parsed = parseOne(conn.buf, start, headerEnd);
      } catch (_) {
        _sendClose(epfd, fd, _tiny400, conns, pending, sendPtr, sendSize, ctlEv);
        return;
      }
      final total = headerEnd + parsed.contentLength;
      if (end < total) {
        // Body fragmented: wait for the rest. Cap abuse at 1MB.
        if (total - start > (1 << 20)) {
          _sendClose(epfd, fd, _tiny400, conns, pending, sendPtr, sendSize, ctlEv);
          return;
        }
        try {
          conn.ensure(total - start + (end - start));
        } catch (_) {
          _sendClose(epfd, fd, _tiny400, conns, pending, sendPtr, sendSize, ctlEv);
          return;
        }
        conn.compact();
        return;
      }

      final req = HttpRequest(
        buffer: conn.buf,
        length: total,
        method: parsed.method,
        path: parsed.path,
        version: parsed.version,
        keepAlive: parsed.keepAlive,
      );
      Uint8List response;
      try {
        response = handler(req);
      } catch (_) {
        _sendClose(epfd, fd, _tiny500, conns, pending, sendPtr, sendSize, ctlEv);
        return;
      }

      // Consume before sending so pipelined remainder survives a blocked send.
      conn.start = total;

      final st = _sendAll(epfd, fd, response, parsed.keepAlive, conns, pending,
          sendPtr, sendSize, ctlEv);
      if (st == _SendResult.closed) {
        return; // fd gone.
      }
      if (st == _SendResult.blocked) {
        return; // EPOLLOUT armed; remainder stays in conn.
      }
      // Sent fully.
      if (!parsed.keepAlive) {
        // RFC: ignore any pipelined bytes after a close-delimited response.
        _closeClient(epfd, fd, conns, pending);
        return;
      }
      // Loop: another pipelined request may already be in the buffer.
    }
  }

  _SendResult _sendAll(
    int epfd,
    int fd,
    Uint8List data,
    bool keepAlive,
    Map<int, _Conn> conns,
    Map<int, _Pending> pending,
    ffi.Pointer<ffi.Uint8> sendPtr,
    int sendSize,
    ffi.Pointer<ffi.Uint8> ctlEv,
  ) {
    if (data.isEmpty) {
      return _SendResult.ok;
    }
    if (data.length <= sendSize) {
      final view = sendPtr.asTypedList(data.length);
      view.setAll(0, data);
      var off = 0;
      while (off < data.length) {
        final rc = sys.sendBufAt(fd, sendPtr, off, data.length - off);
        if (rc > 0) {
          off += rc;
          continue;
        }
        final err = sys.errnoValue();
        if (err == eAgain) {
          // Stash the tail on the Dart heap (scratch will be reused).
          final tail = Uint8List(data.length - off);
          tail.setRange(0, tail.length, view, off);
          pending[fd] = _Pending(tail, closeAfter: !keepAlive);
          sys.epollModReuse(epfd, fd, epollIn | epollOut | epollRdhup, ctlEv);
          return _SendResult.blocked;
        }
        _closeClient(epfd, fd, conns, pending);
        return _SendResult.closed;
      }
      return _SendResult.ok;
    }
    // Large response: send directly from a pinned copy.
    final ptr = ffi.calloc<ffi.Uint8>(data.length);
    try {
      ptr.asTypedList(data.length).setAll(0, data);
      var off = 0;
      while (off < data.length) {
        final rc = sys.sendBufAt(fd, ptr, off, data.length - off);
        if (rc > 0) {
          off += rc;
          continue;
        }
        final err = sys.errnoValue();
        if (err == eAgain) {
          final tail = Uint8List(data.length - off);
          tail.setAll(0, ptr.asTypedList(data.length).sublist(off));
          pending[fd] = _Pending(tail, closeAfter: !keepAlive);
          sys.epollModReuse(epfd, fd, epollIn | epollOut | epollRdhup, ctlEv);
          return _SendResult.blocked;
        }
        _closeClient(epfd, fd, conns, pending);
        return _SendResult.closed;
      }
      return _SendResult.ok;
    } finally {
      ffi.calloc.free(ptr);
    }
  }

  /// Returns true when the pending queue fully drained.
  bool _flushPending(
    int epfd,
    int fd,
    ffi.Pointer<ffi.Uint8> sendPtr,
    int sendSize,
    ffi.Pointer<ffi.Uint8> ctlEv,
    Map<int, _Conn> conns,
    Map<int, _Pending> pending,
  ) {
    final p = pending[fd];
    if (p == null) {
      return true;
    }
    while (p.offset < p.bytes.length) {
      final remaining = p.bytes.length - p.offset;
      final chunk = remaining > sendSize ? sendSize : remaining;
      final view = sendPtr.asTypedList(chunk);
      view.setRange(0, chunk, p.bytes, p.offset);
      final rc = sys.sendBuf(fd, sendPtr, chunk);
      if (rc > 0) {
        p.offset += rc;
        continue;
      }
      final err = sys.errnoValue();
      if (err == eAgain) {
        return false; // stay armed.
      }
      pending.remove(fd);
      sys.epollDel(epfd, fd);
      sys.closeFd(fd);
      conns.remove(fd);
      return false;
    }
    pending.remove(fd);
    if (p.closeAfter) {
      sys.epollDel(epfd, fd);
      sys.closeFd(fd);
      return false;
    }
    sys.epollModReuse(epfd, fd, epollIn | epollRdhup, ctlEv);
    return true;
  }

  void _sendClose(
    int epfd,
    int fd,
    Uint8List data,
    Map<int, _Conn> conns,
    Map<int, _Pending> pending,
    ffi.Pointer<ffi.Uint8> sendPtr,
    int sendSize,
    ffi.Pointer<ffi.Uint8> ctlEv,
  ) {
    final st = _sendAll(
        epfd, fd, data, false, conns, pending, sendPtr, sendSize, ctlEv);
    if (st == _SendResult.ok) {
      _closeClient(epfd, fd, conns, pending);
    }
    // blocked -> closeAfter pending will close on drain; closed -> already gone.
  }

  void _closeClient(
    int epfd,
    int fd,
    Map<int, _Conn> conns,
    Map<int, _Pending> pending,
  ) {
    // Always remove from epoll BEFORE close: otherwise the stale fd number
    // can be recycled by accept() while epoll still watches it.
    if (epfd >= 0) {
      sys.epollDel(epfd, fd);
    }
    sys.closeFd(fd);
    conns.remove(fd);
    pending.remove(fd);
  }
}

enum _SendResult { ok, blocked, closed }

final Uint8List _tiny400 = Uint8List.fromList(
  'HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'
      .codeUnits,
);

final Uint8List _tiny500 = Uint8List.fromList(
  'HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'
      .codeUnits,
);
