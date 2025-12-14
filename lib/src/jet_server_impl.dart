import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkg_ffi;

import 'buffer_pool.dart';
import 'http_parser.dart';
import 'constants.dart';
import 'syscall.dart' as sys;

typedef RequestHandler = Uint8List Function(HttpRequest req);

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
    this.maxEvents = 1024,
    this.backlog = 1024,
    this.bufferSize = 8192,
    this.reusePort = true,
    this.enableTcpFastOpen = true,
    BufferPool? pool,
  }) : _pool = pool ?? BufferPool(bufferSize: bufferSize, capacity: 1024) {
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
      sys.setSockOptInt(serverFd, tcpLevel, tcpFastOpen, 1);
    }
    sys.bindAny(serverFd, port);
    sys.listenFd(serverFd, backlog);

    final epfd = sys.epollCreate();
    if (epfd < 0) {
      sys.closeFd(serverFd);
      throw Exception('epoll_create1 failed errno=${sys.errnoValue()}');
    }
    sys.epollAdd(epfd, serverFd, epollIn);

    final events = sys.allocEvents(maxEvents);

    try {
      _loop(epfd, serverFd, events);
    } finally {
      sys.freeEvents(events);
      sys.closeFd(serverFd);
      sys.closeFd(epfd);
      _pool.dispose();
    }
  }

  @pragma('vm:unsafe:no-interrupts')
  void _loop(int epfd, int serverFd, ffi.Pointer<sys.EpollEvent> events) {
    while (true) {
      final n = sys.epollWait(epfd, events, maxEvents, -1);
      if (n <= 0) {
        continue;
      }
      for (var i = 0; i < n; i++) {
        final ev = events.elementAt(i).ref;
        final fd = ev.data.fd;
        final mask = ev.events;
        if (fd == serverFd) {
          _drainAccept(epfd, serverFd);
          continue;
        }
        if ((mask & (epollErr | epollHup | epollRdhup)) != 0) {
          _closeClient(epfd, fd);
          continue;
        }
        if ((mask & epollIn) != 0) {
          _handleRead(epfd, fd);
        }
      }
    }
  }

  void _drainAccept(int epfd, int serverFd) {
    while (true) {
      final fd = sys.acceptConn(serverFd);
      if (fd < 0) {
        // EAGAIN / EWOULDBLOCK stops the loop.
        break;
      }
      sys.setSockOptInt(fd, solSocket, soKeepAlive, 1);
      sys.setNonBlocking(fd);
      sys.epollAdd(epfd, fd, epollIn | epollEt);
    }
  }

  void _handleRead(int epfd, int fd) {
    final handle = _pool.acquire();
    final builder = BytesBuilder(copy: false);

    while (true) {
      final rc = sys.recvInto(fd, handle.ptr, bufferSize);
      if (rc > 0) {
        builder.add(handle.view.sublist(0, rc));
        if (rc < bufferSize) break; // drained
      } else if (rc == 0) {
        _closeClient(epfd, fd);
        return;
      } else {
        final err = sys.errnoValue();
        // 11 -> EAGAIN
        if (err == 11) {
          break;
        }
        _closeClient(epfd, fd);
        return;
      }
    }

    final data = builder.takeBytes();
    if (data.isEmpty) {
      _closeClient(epfd, fd);
      return;
    }

    HttpRequest req;
    try {
      req = parseHttpRequest(data, data.length);
    } catch (_) {
      _sendStatic(fd, _tiny400);
      _closeClient(epfd, fd);
      return;
    }

    final response = handler(req);
    _send(fd, response);
    if (!req.keepAlive) {
      _closeClient(epfd, fd);
    }
  }

  void _send(int fd, Uint8List data) {
    final ptr = pkg_ffi.calloc<ffi.Uint8>(data.length);
    final view = ptr.asTypedList(data.length);
    view.setAll(0, data);
    final sent = sys.sendBuf(
      fd,
      ptr,
      data.length,
      flags: msgNoSignal | msgZeroCopy,
    );
    pkg_ffi.calloc.free(ptr);
    if (sent < 0) {
      _closeClient(-1, fd);
    }
  }

  void _sendStatic(int fd, Uint8List data) {
    final ptr = pkg_ffi.calloc<ffi.Uint8>(data.length);
    ptr.asTypedList(data.length).setAll(0, data);
    sys.sendBuf(fd, ptr, data.length, flags: msgNoSignal);
    pkg_ffi.calloc.free(ptr);
  }

  void _closeClient(int epfd, int fd) {
    if (epfd >= 0) {
      sys.epollDel(epfd, fd);
    }
    sys.closeFd(fd);
  }
}

final Uint8List _tiny400 = Uint8List.fromList(
  'HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'
      .codeUnits,
);
