import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkg_ffi;

/// A tiny fixed-size buffer pool backed by native memory to avoid GC moves.
final class BufferPool {
  final int bufferSize;
  final int capacity;
  final List<ffi.Pointer<ffi.Uint8>> _buffers;
  final List<Uint8List> _views;
  int _cursor = 0;

  BufferPool({this.bufferSize = 8192, this.capacity = 1024})
    : _buffers = List.filled(capacity, ffi.nullptr),
      _views = List.filled(capacity, Uint8List(0)) {
    for (var i = 0; i < capacity; i++) {
      final ptr = pkg_ffi.calloc<ffi.Uint8>(bufferSize);
      _buffers[i] = ptr;
      _views[i] = ptr.asTypedList(bufferSize);
    }
  }

  @pragma('vm:unsafe:no-interrupts')
  @pragma('vm:always-consider-inlining')
  BufferHandle acquire() {
    final idx = _cursor;
    final ptr = _buffers[idx];
    final view = _views[idx];
    _cursor = (_cursor + 1) % capacity;
    return BufferHandle(ptr, view);
  }

  void dispose() {
    for (final ptr in _buffers) {
      if (ptr != ffi.nullptr) {
        pkg_ffi.calloc.free(ptr);
      }
    }
  }
}

final class BufferHandle {
  final ffi.Pointer<ffi.Uint8> ptr;
  final Uint8List view;

  BufferHandle(this.ptr, this.view);
}
