import 'dart:typed_data';

@pragma('vm:always-consider-inlining')
bool _isSpace(int byte) => byte == 0x20;

final class Slice {
  final int start;
  final int len;
  const Slice(this.start, this.len);
}

final class HttpRequest {
  final Uint8List buffer;
  final int length;
  final Slice method;
  final Slice path;
  final Slice version;
  final bool keepAlive;

  const HttpRequest({
    required this.buffer,
    required this.length,
    required this.method,
    required this.path,
    required this.version,
    required this.keepAlive,
  });

  @pragma('vm:always-consider-inlining')
  Slice header(String name) {
    final target = name.codeUnits;
    var pos = version.start + version.len + 2; // skip \r\n
    while (pos < length) {
      if (buffer[pos] == 13 /*\r*/ &&
          pos + 1 < length &&
          buffer[pos + 1] == 10) {
        break; // end of headers
      }
      var i = 0;
      while (i < target.length &&
          pos + i < length &&
          buffer[pos + i] == target[i]) {
        i++;
      }
      if (i == target.length &&
          pos + i < length &&
          buffer[pos + i] == 58 /*:*/ ) {
        pos += i + 1;
        while (pos < length && (buffer[pos] == 32 || buffer[pos] == 9)) {
          pos++;
        }
        final start = pos;
        while (pos < length && buffer[pos] != 13) {
          pos++;
        }
        return Slice(start, pos - start);
      }
      while (pos < length &&
          !(buffer[pos] == 13 && pos + 1 < length && buffer[pos + 1] == 10)) {
        pos++;
      }
      pos += 2; // skip CRLF
    }
    return const Slice(0, 0);
  }
}

HttpRequest parseHttpRequest(Uint8List buffer, int length) {
  var i = 0;

  while (i < length && !_isSpace(buffer[i])) {
    i++;
  }
  final method = Slice(0, i);
  i++; // space

  final pathStart = i;
  while (i < length && !_isSpace(buffer[i])) {
    i++;
  }
  final path = Slice(pathStart, i - pathStart);
  i++; // space

  final verStart = i;
  while (i < length && buffer[i] != 13) {
    i++;
  }
  final version = Slice(verStart, i - verStart);

  // Move past CRLF of request line
  if (i + 1 < length && buffer[i] == 13 && buffer[i + 1] == 10) {
    i += 2;
  } else {
    throw const FormatException('Invalid request line termination');
  }

  // Minimal keep-alive detection: HTTP/1.1 default keep-alive unless Connection: close
  final conn = _findConnection(buffer, length, i);
  final keepAlive =
      conn == null || !_asciiEquals(buffer, conn.start, conn.len, 'close');

  return HttpRequest(
    buffer: buffer,
    length: length,
    method: method,
    path: path,
    version: version,
    keepAlive: keepAlive,
  );
}

@pragma('vm:unsafe:no-bounds-checks')
Slice? _findConnection(Uint8List buf, int length, int start) {
  const name = [
    0x43,
    0x6f,
    0x6e,
    0x6e,
    0x65,
    0x63,
    0x74,
    0x69,
    0x6f,
    0x6e,
    0x3a,
  ]; // Connection:
  var pos = start;
  while (pos + name.length < length) {
    var matched = true;
    for (var j = 0; j < name.length; j++) {
      if (buf[pos + j] != name[j]) {
        matched = false;
        break;
      }
    }
    if (matched) {
      var vStart = pos + name.length;
      while (vStart < length && (buf[vStart] == 32 || buf[vStart] == 9)) {
        vStart++;
      }
      final s = vStart;
      while (vStart < length && buf[vStart] != 13) {
        vStart++;
      }
      return Slice(s, vStart - s);
    }
    // skip to next line
    while (pos < length &&
        !(buf[pos] == 13 && pos + 1 < length && buf[pos + 1] == 10)) {
      pos++;
    }
    pos += 2;
  }
  return null;
}

@pragma('vm:always-consider-inlining')
bool _asciiEquals(Uint8List buf, int start, int len, String text) {
  final codes = text.codeUnits;
  if (len != codes.length) return false;
  for (var i = 0; i < len; i++) {
    if (buf[start + i] != codes[i]) return false;
  }
  return true;
}
