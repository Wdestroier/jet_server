import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart' as ffi show calloc;

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

/// NOTE: Linux's `struct epoll_event` is 12 bytes (packed: u32 events + u64
/// data with 4-byte alignment). Dart FFI structs use natural alignment and
/// would lay this out as 16 bytes, which silently corrupts every event after
/// the first in an `epoll_wait` batch. We therefore NEVER use [EpollEvent]
/// for the events array: the array is handled as raw bytes with stride 12
/// (see [epollEventStride], [loadEventMask], [loadEventFd], [storeCtlEvent]).
final class EpollEvent extends ffi.Struct {
  @ffi.Uint32()
  external int events;

  external EpollData data;
}

/// Kernel stride of `struct epoll_event`.
const int epollEventStride = 12;

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
      ffi.Pointer<ffi.Void>,
    );
typedef _EpollCtlDart = int Function(int, int, int, ffi.Pointer<ffi.Void>);

typedef _EpollWaitNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Pointer<ffi.Void>,
      ffi.Int32,
      ffi.Int32,
    );
typedef _EpollWaitDart = int Function(int, ffi.Pointer<ffi.Void>, int, int);

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
  final addr = ffi.calloc<SockAddrIn>();
  addr.ref
    ..sinFamily = afInet
    ..sinPort = htons(port)
    ..sinAddr.sAddr = inaddrAny;
  for (var i = 0; i < 8; i++) {
    addr.ref.sinZero[i] = 0;
  }
  final rc = _bind(fd, addr, ffi.sizeOf<SockAddrIn>());
  ffi.calloc.free(addr);
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
  final ptr = ffi.calloc<ffi.Int32>();
  ptr.value = value;
  final rc = _setsockopt(fd, level, opt, ptr.cast(), ffi.sizeOf<ffi.Int32>());
  ffi.calloc.free(ptr);
  return rc;
}

/// Fast variant reusing a caller-provided Int32 cell (avoids malloc per call).
@pragma('vm:always-consider-inlining')
int setSockOptIntFast(
  int fd,
  int level,
  int opt,
  int value,
  ffi.Pointer<ffi.Int32> cell,
) {
  cell.value = value;
  return _setsockopt(fd, level, opt, cell.cast(), ffi.sizeOf<ffi.Int32>());
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

/// 12-byte kernel-layout scratch reuse: caller passes a preallocated buffer
/// of at least [epollEventStride] bytes.
@pragma('vm:always-consider-inlining')
int epollAddReuse(
  int epfd,
  int fd,
  int events,
  ffi.Pointer<ffi.Uint8> scratch,
) {
  storeCtlEvent(scratch, events, fd);
  return _epollCtl(epfd, epollCtlAdd, fd, scratch.cast());
}

@pragma('vm:always-consider-inlining')
int epollModReuse(
  int epfd,
  int fd,
  int events,
  ffi.Pointer<ffi.Uint8> scratch,
) {
  storeCtlEvent(scratch, events, fd);
  return _epollCtl(epfd, epollCtlMod, fd, scratch.cast());
}

int epollAdd(int epfd, int fd, int events) {
  final scratch = ffi.calloc<ffi.Uint8>(epollEventStride);
  storeCtlEvent(scratch, events, fd);
  final rc = _epollCtl(epfd, epollCtlAdd, fd, scratch.cast());
  ffi.calloc.free(scratch);
  return rc;
}

int epollMod(int epfd, int fd, int events) {
  final scratch = ffi.calloc<ffi.Uint8>(epollEventStride);
  storeCtlEvent(scratch, events, fd);
  final rc = _epollCtl(epfd, epollCtlMod, fd, scratch.cast());
  ffi.calloc.free(scratch);
  return rc;
}

int epollDel(int epfd, int fd) =>
    _epollCtl(epfd, epollCtlDel, fd, ffi.nullptr.cast());

int epollWait(
  int epfd,
  ffi.Pointer<ffi.Uint8> events,
  int maxEvents,
  int timeoutMs,
) {
  return _epollWait(epfd, events.cast(), maxEvents, timeoutMs);
}

/// Writes a kernel-layout control event (events u32 @0, fd i32 @4, zero @8).
@pragma('vm:always-consider-inlining')
void storeCtlEvent(ffi.Pointer<ffi.Uint8> scratch, int events, int fd) {
  scratch.cast<ffi.Uint32>().value = events;
  (scratch + 4).cast<ffi.Int32>().value = fd;
  (scratch + 8).cast<ffi.Uint32>().value = 0;
}

/// Reads the events mask of batch entry [i] (kernel 12-byte stride).
@pragma('vm:always-consider-inlining')
int loadEventMask(ffi.Pointer<ffi.Uint8> base, int i) =>
    (base + i * epollEventStride).cast<ffi.Uint32>().value;

/// Reads the fd of batch entry [i] (kernel 12-byte stride).
@pragma('vm:always-consider-inlining')
int loadEventFd(ffi.Pointer<ffi.Uint8> base, int i) =>
    (base + 4 + i * epollEventStride).cast<ffi.Int32>().value;

@pragma('vm:always-consider-inlining')
int recvInto(int fd, ffi.Pointer<ffi.Uint8> buf, int len) =>
    _recv(fd, buf.cast(), len, 0);

int sendBuf(
  int fd,
  ffi.Pointer<ffi.Uint8> buf,
  int len, {
  int flags = msgNoSignal,
}) => _send(fd, buf.cast(), len, flags);

/// Send from [offset] within the native buffer.
@pragma('vm:always-consider-inlining')
int sendBufAt(
  int fd,
  ffi.Pointer<ffi.Uint8> base,
  int offset,
  int len, {
  int flags = msgNoSignal,
}) => _send(fd, (base + offset).cast(), len, flags);

int errnoValue() => _errno();

ffi.Pointer<ffi.Uint8> allocEvents(int count) =>
    ffi.calloc<ffi.Uint8>(count * epollEventStride);

void freeEvents(ffi.Pointer<ffi.Uint8> ptr) => ffi.calloc.free(ptr);
