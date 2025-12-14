// Linux socket and epoll constants used by the FFI layer.
// These values mirror the glibc headers for x86_64 Linux.
// Keep this file small and constexpr so the JIT can inline everything.

// Socket families / types
const int afInet = 2; // AF_INET
const int sockStream = 1; // SOCK_STREAM

// Socket options
const int solSocket = 1; // SOL_SOCKET
const int soReuseAddr = 2;
const int soReusePort = 15;
const int soKeepAlive = 9;
const int tcpFastOpen = 23; // at TCP level
const int tcpLevel = 6; // IPPROTO_TCP

// fcntl
const int fGetFl = 3;
const int fSetFl = 4;
const int oNonBlock = 0x800;

// epoll
const int epollCtlAdd = 1;
const int epollCtlDel = 2;
const int epollCtlMod = 3;

const int epollIn = 0x001;
const int epollOut = 0x004;
const int epollErr = 0x008;
const int epollHup = 0x010;
const int epollRdhup = 0x2000;
const int epollEt = 1 << 31; // EPOLLET

// accept4 flags
const int sockCloExec = 0x80000;
const int sockNonBlock = 0x800;

// send/recv flags
const int msgNoSignal = 0x4000;
const int msgZeroCopy = 0x4000000; // may be ignored depending on kernel/config

// misc
const int inaddrAny = 0x00000000;
