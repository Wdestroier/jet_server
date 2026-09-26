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
          buffer[pos + i] == 58 /*:*/) {
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

/// Incremental parse result. [consumed] is the offset just past the headers
/// (i.e. start of body), relative to the buffer start passed in.
final class ParsedRequest {
  final Slice method;
  final Slice path;
  final Slice version;
  final bool keepAlive;
  final int contentLength;
  final int headerEnd;

  const ParsedRequest({
    required this.method,
    required this.path,
    required this.version,
    required this.keepAlive,
    required this.contentLength,
    required this.headerEnd,
  });
}

/// Finds the offset just past the first `\r\n\r\n` at or after [start].
/// Returns -1 when headers are incomplete.
@pragma('vm:unsafe:no-bounds-checks')
int findHeadersEnd(Uint8List buf, int start, int end) {
  var i = start;
  // Need at least 4 bytes for the terminator.
  while (i + 3 < end) {
    if (buf[i] == 13 /* \r */) {
      if (buf[i + 1] == 10 && buf[i + 2] == 13 && buf[i + 3] == 10) {
        return i + 4;
      }
      // Skip to end of line quickly.
      if (buf[i + 1] == 10) {
        i += 2;
        continue;
      }
    }
    i++;
  }
  return -1;
}

/// Parses a single request whose headers lie in [buf[start, headerEnd).
/// Throws [FormatException] on malformed input.
/// [base] is the absolute offset of buf[0] in the connection stream; slices
/// are relative to [buf] (caller must keep them consistent).
@pragma('vm:unsafe:no-bounds-checks')
ParsedRequest parseOne(Uint8List buf, int start, int headerEnd) {
  final end = headerEnd;
  var i = start;

  // --- request line: METHOD SP PATH SP VERSION CRLF ---
  while (i < end && buf[i] != 32) {
    i++;
  }
  if (i >= end) throw const FormatException('bad request line');
  final method = Slice(start, i - start);
  i++; // space

  final pathStart = i;
  while (i < end && buf[i] != 32) {
    i++;
  }
  if (i >= end) throw const FormatException('bad request line');
  final path = Slice(pathStart, i - pathStart);
  i++; // space

  final verStart = i;
  while (i < end && buf[i] != 13) {
    i++;
  }
  if (i + 1 >= end || buf[i] != 13 || buf[i + 1] != 10) {
    throw const FormatException('bad request line termination');
  }
  final version = Slice(verStart, i - verStart);
  i += 2;

  // Detect HTTP/1.0 vs 1.1 for default keep-alive.
  // version is like "HTTP/1.1" (8 chars). Check last 3 bytes.
  var isHttp11 = true;
  if (version.len >= 8) {
    final v = verStart;
    // "HTTP/1.0" -> keep-alive off by default; "HTTP/1.1" -> on.
    isHttp11 = !(buf[v + 5] == 0x31 &&
        buf[v + 6] == 0x2E &&
        buf[v + 7] == 0x30);
  }

  bool? keepAliveOverride;
  var contentLength = 0;

  // --- headers: single pass, case-insensitive name match ---
  while (i < end) {
    // Empty line = end (should only happen at headerEnd, but be safe).
    if (buf[i] == 13) {
      break;
    }
    final lineStart = i;
    // Find ':' in this line.
    var colon = -1;
    var lineEnd = i;
    while (lineEnd < end && buf[lineEnd] != 13) {
      if (colon < 0 && buf[lineEnd] == 58) colon = lineEnd;
      lineEnd++;
    }
    if (colon > 0) {
      final nameLen = colon - lineStart;
      if (nameLen == 10 && _nameIs(buf, lineStart, 'connection')) {
        var v = colon + 1;
        while (v < lineEnd && (buf[v] == 32 || buf[v] == 9)) {
          v++;
        }
        // value len = lineEnd - v; check first char: 'c'/'C' => close,
        // 'k'/'K' => keep-alive.
        if (v < lineEnd) {
          final c = buf[v] | 0x20;
          if (c == 0x63 /*c*/) {
            // "close" (5). Verify to avoid matching e.g. "chunked".
            if (lineEnd - v == 5) {
              keepAliveOverride = false;
            } else {
              // Any other connection token containing "close"?
              // Scan for token boundary; simplest: if starts with close -> close.
              keepAliveOverride = false;
            }
          } else if (c == 0x6B /*k*/) {
            keepAliveOverride = true;
          }
        }
      } else if (nameLen == 14 && _nameIs(buf, lineStart, 'content-length')) {
        var v = colon + 1;
        while (v < lineEnd && (buf[v] == 32 || buf[v] == 9)) {
          v++;
        }
        var n = 0;
        while (v < lineEnd) {
          final d = buf[v] - 48;
          if (d < 0 || d > 9) break;
          n = n * 10 + d;
          v++;
        }
        contentLength = n;
      }
    }
    i = lineEnd + 2; // skip CRLF
  }

  final keepAlive = keepAliveOverride ?? isHttp11;
  return ParsedRequest(
    method: method,
    path: path,
    version: version,
    keepAlive: keepAlive,
    contentLength: contentLength,
    headerEnd: headerEnd,
  );
}

/// Case-insensitive ASCII compare of buf[pos, pos+name.length) with [name].
@pragma('vm:always-consider-inlining')
bool _nameIs(Uint8List buf, int pos, String name) {
  final codes = name.codeUnits;
  for (var j = 0; j < codes.length; j++) {
    if ((buf[pos + j] | 0x20) != codes[j]) return false;
  }
  return true;
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
