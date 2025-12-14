import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart' as pkg_ffi;

import 'constants.dart';

@pragma('vm:prefer-inline')
int _errno() => _errnoLocation().value;

final ffi.Pointer<ffi.Int32> Function() _errnoLocation = () {
  final libc = _openLibc();
  // glibc exposes __errno_location; musl uses __errno_location as well.
  return libc.lookupFunction<
    ffi.Pointer<ffi.Int32> Function(),
    ffi.Pointer<ffi.Int32> Function()
  >('__errno_location');
}();

ffi.DynamicLibrary _openLibc() {
  if (!Platform.isLinux) {
    throw UnsupportedError('This server targets Linux/WSL only.');
  }
  try {
    return ffi.DynamicLibrary.open('libc.so.6');
  } catch (_) {
    return ffi.DynamicLibrary.process();
  }
}

final ffi.DynamicLibrary _libc = _openLibc();

final class InAddr extends ffi.Struct {
  @ffi.Uint32()
  external int sAddr;
}

final class SockAddrIn extends ffi.Struct {
  @ffi.Uint16()
  external int sinFamily;

  @ffi.Uint16()
  external int sinPort;

  external InAddr sinAddr;

  @ffi.Array.multi([8])
  external ffi.Array<ffi.Uint8> sinZero;
}

final class EpollData extends ffi.Union {
  @ffi.Int32()
  external int fd;

  external ffi.Pointer<ffi.Void> ptr;

  @ffi.Uint64()
  external int u64;
}

final class EpollEvent extends ffi.Struct {
  @ffi.Uint32()
  external int events;

  external EpollData data;
}

typedef _SocketNative = ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Int32);
typedef _SocketDart = int Function(int, int, int);

typedef _BindNative =
    ffi.Int32 Function(ffi.Int32, ffi.Pointer<SockAddrIn>, ffi.Uint32);
typedef _BindDart = int Function(int, ffi.Pointer<SockAddrIn>, int);

typedef _ListenNative = ffi.Int32 Function(ffi.Int32, ffi.Int32);
typedef _ListenDart = int Function(int, int);

typedef _Accept4Native =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Pointer<SockAddrIn>,
      ffi.Pointer<ffi.Uint32>,
      ffi.Int32,
    );
typedef _Accept4Dart =
    int Function(int, ffi.Pointer<SockAddrIn>, ffi.Pointer<ffi.Uint32>, int);

typedef _CloseNative = ffi.Int32 Function(ffi.Int32);
typedef _CloseDart = int Function(int);

typedef _SetSockOptNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Pointer<ffi.Void>,
      ffi.Uint32,
    );
typedef _SetSockOptDart =
    int Function(int, int, int, ffi.Pointer<ffi.Void>, int);

typedef _RecvNative =
    ffi.IntPtr Function(
      ffi.Int32,
      ffi.Pointer<ffi.Void>,
      ffi.UintPtr,
      ffi.Int32,
    );
typedef _RecvDart = int Function(int, ffi.Pointer<ffi.Void>, int, int);

typedef _SendNative =
    ffi.IntPtr Function(
      ffi.Int32,
      ffi.Pointer<ffi.Void>,
      ffi.UintPtr,
      ffi.Int32,
    );
typedef _SendDart = int Function(int, ffi.Pointer<ffi.Void>, int, int);

typedef _FcntlNative = ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Int32);
typedef _FcntlDart = int Function(int, int, int);

typedef _EpollCreateNative = ffi.Int32 Function(ffi.Int32);
typedef _EpollCreateDart = int Function(int);

typedef _EpollCtlNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Pointer<EpollEvent>,
    );
typedef _EpollCtlDart = int Function(int, int, int, ffi.Pointer<EpollEvent>);

typedef _EpollWaitNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Pointer<EpollEvent>,
      ffi.Int32,
      ffi.Int32,
    );
typedef _EpollWaitDart = int Function(int, ffi.Pointer<EpollEvent>, int, int);

typedef _HtonsNative = ffi.Uint16 Function(ffi.Uint16);
typedef _HtonsDart = int Function(int);

final _SocketDart _socket = _libc.lookupFunction<_SocketNative, _SocketDart>(
  'socket',
);
final _BindDart _bind = _libc.lookupFunction<_BindNative, _BindDart>('bind');
final _ListenDart _listen = _libc.lookupFunction<_ListenNative, _ListenDart>(
  'listen',
);
final _Accept4Dart _accept4 = _libc
    .lookupFunction<_Accept4Native, _Accept4Dart>('accept4');
final _CloseDart _close = _libc.lookupFunction<_CloseNative, _CloseDart>(
  'close',
);
final _SetSockOptDart _setsockopt = _libc
    .lookupFunction<_SetSockOptNative, _SetSockOptDart>('setsockopt');
final _RecvDart _recv = _libc.lookupFunction<_RecvNative, _RecvDart>('recv');
final _SendDart _send = _libc.lookupFunction<_SendNative, _SendDart>('send');
final _FcntlDart _fcntl = _libc.lookupFunction<_FcntlNative, _FcntlDart>(
  'fcntl',
);
final _EpollCreateDart _epollCreate1 = _libc
    .lookupFunction<_EpollCreateNative, _EpollCreateDart>('epoll_create1');
final _EpollCtlDart _epollCtl = _libc
    .lookupFunction<_EpollCtlNative, _EpollCtlDart>('epoll_ctl');
final _EpollWaitDart _epollWait = _libc
    .lookupFunction<_EpollWaitNative, _EpollWaitDart>('epoll_wait');
final _HtonsDart _htons = _libc.lookupFunction<_HtonsNative, _HtonsDart>(
  'htons',
);

@pragma('vm:always-consider-inlining')
int closeFd(int fd) => _close(fd);

@pragma('vm:always-consider-inlining')
int socketTcp() => _socket(afInet, sockStream | sockNonBlock | sockCloExec, 0);

@pragma('vm:always-consider-inlining')
int htons(int port) => _htons(port);

int bindAny(int fd, int port) {
  final addr = pkg_ffi.calloc<SockAddrIn>();
  addr.ref
    ..sinFamily = afInet
    ..sinPort = htons(port)
    ..sinAddr.sAddr = inaddrAny;
  for (var i = 0; i < 8; i++) {
    addr.ref.sinZero[i] = 0;
  }
  final rc = _bind(fd, addr, ffi.sizeOf<SockAddrIn>());
  pkg_ffi.calloc.free(addr);
  return rc;
}

int listenFd(int fd, int backlog) => _listen(fd, backlog);

@pragma('vm:always-consider-inlining')
int setNonBlocking(int fd) {
  final flags = _fcntl(fd, fGetFl, 0);
  if (flags < 0) return flags;
  return _fcntl(fd, fSetFl, flags | oNonBlock);
}

int setSockOptInt(int fd, int level, int opt, int value) {
  final ptr = pkg_ffi.calloc<ffi.Int32>();
  ptr.value = value;
  final rc = _setsockopt(fd, level, opt, ptr.cast(), ffi.sizeOf<ffi.Int32>());
  pkg_ffi.calloc.free(ptr);
  return rc;
}

int acceptConn(int serverFd) {
  return _accept4(
    serverFd,
    ffi.nullptr.cast(),
    ffi.nullptr.cast(),
    sockCloExec | sockNonBlock,
  );
}

@pragma('vm:always-consider-inlining')
int epollCreate() => _epollCreate1(0);

int epollAdd(int epfd, int fd, int events) {
  final ev = pkg_ffi.calloc<EpollEvent>();
  ev.ref.events = events;
  ev.ref.data.fd = fd;
  final rc = _epollCtl(epfd, epollCtlAdd, fd, ev);
  pkg_ffi.calloc.free(ev);
  return rc;
}

int epollDel(int epfd, int fd) =>
    _epollCtl(epfd, epollCtlDel, fd, ffi.nullptr.cast());

int epollWait(
  int epfd,
  ffi.Pointer<EpollEvent> events,
  int maxEvents,
  int timeoutMs,
) {
  return _epollWait(epfd, events, maxEvents, timeoutMs);
}

int recvInto(int fd, ffi.Pointer<ffi.Uint8> buf, int len) =>
    _recv(fd, buf.cast(), len, 0);

int sendBuf(
  int fd,
  ffi.Pointer<ffi.Uint8> buf,
  int len, {
  int flags = msgNoSignal,
}) => _send(fd, buf.cast(), len, flags);

int errnoValue() => _errno();

ffi.Pointer<EpollEvent> allocEvents(int count) =>
    pkg_ffi.calloc<EpollEvent>(count);

void freeEvents(ffi.Pointer<EpollEvent> ptr) => pkg_ffi.calloc.free(ptr);
