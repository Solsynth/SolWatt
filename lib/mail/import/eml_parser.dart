import 'dart:convert';
import 'dart:typed_data';

import 'mail_import_models.dart';

/// Parses a single RFC 5322 message (an `.eml` file) into the fields the
/// ElecPostal import endpoint accepts.
///
/// Handles folded headers, RFC 2047 encoded words, base64 and
/// quoted-printable transfer encodings, nested multipart MIME trees, and the
/// common legacy charsets (UTF-8, ASCII, ISO-8859-1, Windows-1252; anything
/// else degrades to a lossy UTF-8 decode rather than failing the import).
///
/// The parser is intentionally permissive: messages that miss headers or
/// carry malformed MIME still yield a message with whatever was recoverable
/// (empty subject, null date, missing message-id), so a single broken file
/// never blocks a whole import batch.
class EmlParser {
  EmlParser._();

  /// Parses raw [bytes] of a single message.
  ///
  /// [sourceLabel] names the origin (file path, or `file.mbox#N` for an mbox
  /// member) and is attached to the result for error reporting.
  static ParsedMailMessage parseBytes(
    Uint8List bytes, {
    required String sourceLabel,
  }) {
    // Latin-1 decoding maps every byte to one code unit, so 8-bit parts can be
    // re-decoded byte-exactly per their declared charset later.
    return parse(latin1.decode(bytes), sourceLabel: sourceLabel);
  }

  static ParsedMailMessage parse(String source, {required String sourceLabel}) {
    final sep = _splitHeadersBody(source);
    final headerBlock = source.substring(0, sep.$1);
    final bodyBlock = sep.$2 >= source.length ? '' : source.substring(sep.$2);
    final headers = _parseHeaders(headerBlock);

    final collector = _Collector();
    _walkPart(_MimePart(_headerSingles(headers), bodyBlock), collector);

    final from = _firstAddress(
      _decodeEncodedWords(_headerValue(headers, 'from')),
    );
    final to = _parseAddressList(
      _decodeEncodedWords(_headerValue(headers, 'to')),
    );
    final cc = _parseAddressList(
      _decodeEncodedWords(_headerValue(headers, 'cc')),
    );
    final messageId = _stripAngles(_headerValue(headers, 'message-id'));
    final sentAt = parseMailDate(_headerValue(headers, 'date'));

    String body;
    String contentType;
    if (collector.textBodies.isNotEmpty) {
      body = collector.textBodies.join('\n');
      contentType = 'text/plain';
    } else if (collector.htmlBodies.isNotEmpty) {
      body = collector.htmlBodies.join('\n');
      contentType = 'text/html';
    } else {
      body = '';
      contentType = 'text/plain';
    }

    return ParsedMailMessage(
      messageId: messageId.isEmpty ? null : messageId,
      fromAddress: from?.address ?? '',
      fromName: from?.name,
      subject: _decodeEncodedWords(_headerValue(headers, 'subject')),
      body: body,
      contentType: contentType,
      to: to,
      cc: cc,
      sentAt: sentAt,
      attachments: [
        for (final attachment in collector.attachments)
          ImportAttachment(
            fileName: attachment.fileName,
            contentType: attachment.contentType,
            bytes: attachment.bytes,
            contentId: attachment.contentId,
          ),
      ],
      sourceLabel: sourceLabel,
    );
  }

  // --- headers --------------------------------------------------------------

  static String _headerValue(Map<String, List<String>> headers, String name) =>
      headers[name]?.first ?? '';

  /// Collapses multi-value headers to their first value for MIME part use.
  static Map<String, String> _headerSingles(
    Map<String, List<String>> headers,
  ) => {for (final entry in headers.entries) entry.key: entry.value.first};

  /// Splits a message into (headers block, body start offset). The body starts
  /// after the first blank line; a message with no blank line has no body.
  static (int, int) _splitHeadersBody(String source) {
    final crlf = source.indexOf('\r\n\r\n');
    if (crlf != -1) return (crlf, crlf + 4);
    final lf = source.indexOf('\n\n');
    if (lf != -1) return (lf, lf + 2);
    return (source.length, source.length);
  }

  /// Parses the header block into lowercased name → values, unfolding folded
  /// (continuation) lines per RFC 5322: a line starting with space or tab
  /// continues the previous header.
  static Map<String, List<String>> _parseHeaders(String block) {
    final unfolded = <String>[];
    final buffer = StringBuffer();
    var inHeader = false;
    for (final raw in block.split('\n')) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (line.isEmpty) continue;
      if (line.startsWith(' ') || line.startsWith('\t')) {
        // Unfold a continuation line, preserving the separating space (the
        // display-friendly reading of FWS used by mainstream clients).
        buffer
          ..write(' ')
          ..write(line.trimLeft());
      } else {
        if (inHeader) unfolded.add(buffer.toString());
        buffer
          ..clear()
          ..write(line);
        inHeader = true;
      }
    }
    if (inHeader) unfolded.add(buffer.toString());

    final headers = <String, List<String>>{};
    for (final line in unfolded) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final name = line.substring(0, colon).trim().toLowerCase();
      final value = line.substring(colon + 1).trim();
      headers.putIfAbsent(name, () => []).add(value);
    }
    return headers;
  }

  // --- RFC 2047 encoded words ------------------------------------------------

  /// Decodes `=?charset?B?…?=` / `=?charset?Q?…?=` encoded words anywhere in
  /// [input]; unrecognized encodings are left as-is. Linear whitespace between
  /// adjacent encoded words is ignored per RFC 2047, but kept before plain
  /// text.
  static String _decodeEncodedWords(String input) {
    final re = RegExp(r'=\?([^?]+)\?([bBqQ])\?([^?]*?)\?=(?:\s*(?==\?))?');
    return input.replaceAllMapped(re, (match) {
      final charset = match.group(1) ?? '';
      final kind = (match.group(2) ?? '').toUpperCase();
      final payload = match.group(3) ?? '';
      late Uint8List bytes;
      if (kind == 'B') {
        try {
          bytes = base64.decode(payload.replaceAll(RegExp(r'\s'), ''));
        } on FormatException {
          return match.group(0)!;
        }
      } else {
        // Q-encoding is quoted-printable with '_' for space.
        bytes = _decodeQuotedPrintable(payload.replaceAll('_', ' '));
      }
      return _decodeCharset(bytes, charset);
    });
  }

  // --- transfer encodings ----------------------------------------------------

  /// Decodes a part body under its Content-Transfer-Encoding.
  static Uint8List _decodeTransfer(String body, String encoding) {
    switch (encoding) {
      case 'base64':
        final cleaned = body.replaceAll(RegExp(r'\s'), '');
        try {
          return base64.decode(cleaned);
        } on FormatException {
          return latin1.encode(body);
        }
      case 'quoted-printable':
        return _decodeQuotedPrintable(body);
      default:
        // 7bit, 8bit, binary, identity: bytes pass through. 8-bit content is
        // decoded per charset later.
        return latin1.encode(body);
    }
  }

  static Uint8List _decodeQuotedPrintable(String input) {
    final builder = BytesBuilder();
    final lines = input.split('\n');
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      final isLastLine = i == lines.length - 1;
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      final softBreak = line.endsWith('=');
      if (softBreak) line = line.substring(0, line.length - 1);
      for (var j = 0; j < line.length; j++) {
        final code = line.codeUnitAt(j);
        if (code == 0x3D /* = */ &&
            j + 2 < line.length &&
            _isHexDigit(line.codeUnitAt(j + 1)) &&
            _isHexDigit(line.codeUnitAt(j + 2))) {
          builder.addByte(int.parse(line.substring(j + 1, j + 3), radix: 16));
          j += 2;
        } else {
          builder.addByte(code);
        }
      }
      // Newlines only separate real lines; a trailing newline in the input is
      // the final empty segment and must not produce an extra byte (header
      // Q-encoding has no newline at all).
      if (!softBreak && !isLastLine) builder.addByte(0x0A);
    }
    return builder.takeBytes();
  }

  static bool _isHexDigit(int code) =>
      (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x46) ||
      (code >= 0x61 && code <= 0x66);

  // --- charsets --------------------------------------------------------------

  static const _cp1252Overrides = <int, int>{
    0x80: 0x20AC, // €
    0x82: 0x201A, // ‚
    0x83: 0x0192, // ƒ
    0x84: 0x201E, // „
    0x85: 0x2026, // …
    0x86: 0x2020, // †
    0x87: 0x2021, // ‡
    0x88: 0x02C6, // ˆ
    0x89: 0x2030, // ‰
    0x8A: 0x0160, // Š
    0x8B: 0x2039, // ‹
    0x8C: 0x0152, // Œ
    0x8E: 0x017D, // Ž
    0x91: 0x2018, // ‘
    0x92: 0x2019, // ’
    0x93: 0x201C, // “
    0x94: 0x201D, // ”
    0x95: 0x2022, // •
    0x96: 0x2013, // –
    0x97: 0x2014, // —
    0x98: 0x02DC, // ˜
    0x99: 0x2122, // ™
    0x9A: 0x0161, // š
    0x9B: 0x203A, // ›
    0x9C: 0x0153, // œ
    0x9E: 0x017E, // ž
    0x9F: 0x0178, // Ÿ
  };

  /// Decodes [bytes] under a MIME charset name. Unknown charsets (e.g. legacy
  /// GBK/Big5) fall back to a lossy UTF-8 decode instead of failing.
  static String _decodeCharset(Uint8List bytes, String charset) {
    final name = charset.trim().toLowerCase().replaceAll('_', '-');
    if (name.isEmpty ||
        name == 'us-ascii' ||
        name == 'ascii' ||
        name == 'iso-8859-1' ||
        name == 'iso-8859-15' ||
        name == 'latin1' ||
        name == 'latin-1') {
      return latin1.decode(bytes);
    }
    if (name == 'windows-1252' || name == 'cp1252') {
      return _decodeWindows1252(bytes);
    }
    if (name == 'utf-8' ||
        name == 'utf8' ||
        name == 'unicode-1-1-utf-8' ||
        name == 'utf-16') {
      return utf8.decode(bytes, allowMalformed: true);
    }
    final codec = Encoding.getByName(name);
    if (codec != null) {
      try {
        return codec.decode(bytes);
      } on FormatException {
        // fall through to the lossy decode
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _decodeWindows1252(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.writeCharCode(
        byte >= 0x80 && byte <= 0x9F ? (_cp1252Overrides[byte] ?? byte) : byte,
      );
    }
    return buffer.toString();
  }

  // --- MIME structure ---------------------------------------------------------

  static final _extensionByType = <String, String>{
    'text/plain': 'txt',
    'text/html': 'html',
    'text/calendar': 'ics',
    'application/pdf': 'pdf',
    'application/zip': 'zip',
    'application/json': 'json',
    'message/rfc822': 'eml',
    'image/png': 'png',
    'image/jpeg': 'jpg',
    'image/gif': 'gif',
    'image/webp': 'webp',
    'image/svg+xml': 'svg',
    'audio/mpeg': 'mp3',
    'video/mp4': 'mp4',
  };

  /// Walks the MIME tree of [part], collecting text bodies and attachments.
  static void _walkPart(_MimePart part, _Collector out) {
    final contentType = _parseParameters(
      part.headers['content-type'] ?? 'text/plain',
    );
    final dispositionRaw = part.headers['content-disposition'];
    final disposition = dispositionRaw == null
        ? null
        : _parseParameters(dispositionRaw);
    final transfer = (part.headers['content-transfer-encoding'] ?? '')
        .trim()
        .toLowerCase();
    final raw = _decodeTransfer(part.bodyText, transfer);

    if (contentType.type.startsWith('multipart/')) {
      final boundary = contentType.params['boundary'];
      if (boundary == null || boundary.isEmpty) return; // malformed part
      for (final sub in _splitMultipart(part.bodyText, boundary)) {
        _walkPart(sub, out);
      }
      return;
    }

    final filename =
        disposition?.params['filename'] ??
        contentType.params['filename'] ??
        contentType.params['name'];
    final isDispositioned =
        disposition != null &&
        (disposition.type == 'attachment' || disposition.type == 'inline');
    final isTextLeaf =
        contentType.type == 'text/plain' || contentType.type == 'text/html';

    if (filename != null && filename.isNotEmpty ||
        isDispositioned ||
        !isTextLeaf) {
      final name = (filename != null && filename.isNotEmpty)
          ? filename
          : 'attachment-${++out.anonymousCounter}.${_extensionByType[contentType.type] ?? 'bin'}';
      final contentId = _stripAngles(part.headers['content-id'] ?? '');
      out.attachments.add(
        _AttachmentCandidate(
          fileName: name,
          contentType: contentType.type,
          bytes: raw,
          contentId: contentId.isEmpty ? null : contentId,
        ),
      );
      return;
    }

    final charset = contentType.params['charset'] ?? '';
    final decoded = _decodeCharset(raw, charset);
    if (contentType.type == 'text/html') {
      out.htmlBodies.add(decoded);
    } else {
      out.textBodies.add(decoded);
    }
  }

  /// Splits a multipart body on its boundary lines, returning the sub-parts.
  static List<_MimePart> _splitMultipart(String body, String boundary) {
    final delimiter = RegExp(
      RegExp.escape('--$boundary') + r'(--)?[ \t]*(?:\r?\n|$)',
    );
    final matches = delimiter.allMatches(body).toList();
    final parts = <_MimePart>[];
    for (var i = 0; i + 1 < matches.length; i++) {
      if (matches[i].group(1) != null) break; // closing delimiter: done
      var chunk = body.substring(matches[i].end, matches[i + 1].start);
      if (chunk.startsWith('\r\n')) {
        chunk = chunk.substring(2);
      } else if (chunk.startsWith('\n')) {
        chunk = chunk.substring(1);
      }
      final sep = _splitHeadersBody(chunk);
      final headerBlock = chunk.substring(0, sep.$1);
      final partBody = sep.$2 >= chunk.length ? '' : chunk.substring(sep.$2);
      parts.add(
        _MimePart(_headerSingles(_parseHeaders(headerBlock)), partBody),
      );
    }
    return parts;
  }

  /// Parses `type/subtype; key=value; key="quoted value"` into a type and
  /// decoded parameters. Handles RFC 2231 `key*=charset'lang'value`.
  static _Parameters _parseParameters(String value) {
    final segments = _splitSemicolon(value);
    final type = segments.isEmpty
        ? 'text/plain'
        : segments.first.trim().toLowerCase();
    final params = <String, String>{};
    for (final segment in segments.skip(1)) {
      final eq = segment.indexOf('=');
      if (eq <= 0) continue;
      final rawKey = segment.substring(0, eq).trim().toLowerCase();
      var rawValue = segment.substring(eq + 1).trim();
      if (rawValue.startsWith('"') &&
          rawValue.endsWith('"') &&
          rawValue.length >= 2) {
        rawValue = rawValue.substring(1, rawValue.length - 1);
      }
      String key = rawKey;
      var value = _decodeEncodedWords(rawValue);
      if (rawKey.endsWith('*')) {
        // RFC 2231 extended value: charset'lang'percent-encoded
        key = rawKey.substring(0, rawKey.length - 1);
        final firstQuote = value.indexOf("'");
        final secondQuote = firstQuote == -1
            ? -1
            : value.indexOf("'", firstQuote + 1);
        if (firstQuote != -1 && secondQuote != -1) {
          value = value.substring(secondQuote + 1);
        }
        value = Uri.decodeComponent(value);
      }
      params[key] = value;
    }
    return _Parameters(type, params);
  }

  /// Splits a header value on semicolons, respecting quoted strings.
  static List<String> _splitSemicolon(String value) {
    final segments = <String>[];
    final buffer = StringBuffer();
    var inQuote = false;
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (char == '"') {
        inQuote = !inQuote;
        buffer.write(char);
      } else if (char == ';' && !inQuote) {
        segments.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    segments.add(buffer.toString());
    return segments;
  }

  // --- addresses and dates ----------------------------------------------------

  static ImportRecipient? _firstAddress(String value) {
    final list = _parseAddressList(value);
    return list.isEmpty ? null : list.first;
  }

  /// Parses an RFC 5322 address list (``"Doe, John" <john@example.com>``,
  /// `jane@example.net`) into recipients. Group labels and comments are
  /// skipped; addresses without an `@` are dropped.
  static List<ImportRecipient> _parseAddressList(String decodedValue) {
    final recipients = <ImportRecipient>[];
    for (final chunk in _splitAddressChunks(decodedValue)) {
      final trimmed = chunk.trim();
      if (trimmed.isEmpty) continue;
      final open = trimmed.lastIndexOf('<');
      final close = open == -1 ? -1 : trimmed.indexOf('>', open);
      String address;
      String? name;
      if (open != -1 && close > open) {
        address = trimmed.substring(open + 1, close).trim();
        name = _cleanDisplayName(trimmed.substring(0, open));
      } else {
        address = trimmed;
      }
      address = address.replaceAll(RegExp(r'[<>]'), '').trim();
      if (!address.contains('@')) continue;
      address = address.replaceAll(RegExp(r'\s+'), '');
      recipients.add(
        ImportRecipient(
          address: address,
          name: name == null || name.isEmpty ? null : name,
        ),
      );
    }
    return recipients;
  }

  /// Splits an address list on top-level commas/semicolons, honoring quoted
  /// display names, `<angle-addr>` groups, and `(comments)`.
  static List<String> _splitAddressChunks(String value) {
    final chunks = <String>[];
    final buffer = StringBuffer();
    var angleDepth = 0;
    var inQuote = false;
    var inComment = false;
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (inComment) {
        if (char == ')') inComment = false;
        continue;
      }
      if (inQuote) {
        buffer.write(char);
        if (char == '"') inQuote = false;
        continue;
      }
      if (char == '"') {
        inQuote = true;
        buffer.write(char);
      } else if (char == '(') {
        inComment = true;
      } else if (char == '<') {
        angleDepth++;
        buffer.write(char);
      } else if (char == '>') {
        if (angleDepth > 0) angleDepth--;
        buffer.write(char);
      } else if (char == ',' || char == ';') {
        if (angleDepth == 0) {
          chunks.add(buffer.toString());
          buffer.clear();
        } else {
          buffer.write(char);
        }
      } else {
        buffer.write(char);
      }
    }
    if (buffer.isNotEmpty) chunks.add(buffer.toString());
    return chunks;
  }

  static String _cleanDisplayName(String raw) {
    final withoutQuotes = raw.replaceAll('"', '');
    final withoutComments = withoutQuotes.replaceAll(RegExp(r'\([^)]*\)'), '');
    return withoutComments.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _stripAngles(String value) {
    var v = value.trim();
    if (v.startsWith('<') && v.endsWith('>') && v.length >= 2) {
      v = v.substring(1, v.length - 1);
    }
    return v.trim();
  }

  static const _months = <String, int>{
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  /// Named RFC 5322 zones as hour offsets (numeric zones are handled
  /// separately).
  static const _zones = <String, int>{
    'GMT': 0,
    'UT': 0,
    'UTC': 0,
    'Z': 0,
    'EST': -5,
    'EDT': -4,
    'CST': -6,
    'CDT': -5,
    'MST': -7,
    'MDT': -6,
    'PST': -8,
    'PDT': -7,
  };

  /// Parses an RFC 5322 date (`Tue, 06 Jan 2015 08:13:34 +0000`, obsolete
  /// two-digit years, named zones) or an ISO 8601 timestamp. Returns null for
  /// anything unrecognized.
  static DateTime? parseMailDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso.toUtc();
    final match = RegExp(
      r'(?:[A-Za-z]{3},?\s+)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{2,4})\s+'
      r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Za-z]{1,5})?',
    ).firstMatch(value);
    if (match == null) return null;
    final day = int.parse(match.group(1)!);
    final month = _months[match.group(2)!.toLowerCase()];
    if (month == null) return null;
    var year = int.parse(match.group(3)!);
    if (year < 100) year += year >= 50 ? 1900 : 2000; // RFC 5322 pivot
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = match.group(6) == null ? 0 : int.parse(match.group(6)!);
    var offsetMinutes = 0;
    final zone = match.group(7);
    if (zone != null && zone.isNotEmpty) {
      final zoneUpper = zone.toUpperCase();
      if (RegExp(r'[+-]\d{4}').hasMatch(zoneUpper)) {
        final sign = zoneUpper.startsWith('-') ? -1 : 1;
        offsetMinutes =
            sign *
            (int.parse(zoneUpper.substring(1, 3)) * 60 +
                int.parse(zoneUpper.substring(3, 5)));
      } else {
        offsetMinutes = (_zones[zoneUpper] ?? 0) * 60;
      }
    }
    return DateTime.utc(
      year,
      month,
      day,
      hour,
      minute,
      second,
    ).subtract(Duration(minutes: offsetMinutes));
  }
}

class _MimePart {
  _MimePart(this.headers, this.bodyText);

  final Map<String, String> headers;
  final String bodyText;
}

class _Parameters {
  _Parameters(this.type, this.params);

  final String type;
  final Map<String, String> params;
}

class _AttachmentCandidate {
  _AttachmentCandidate({
    required this.fileName,
    required this.contentType,
    required this.bytes,
    this.contentId,
  });

  final String fileName;
  final String contentType;
  final Uint8List bytes;
  final String? contentId;
}

class _Collector {
  final List<String> textBodies = [];
  final List<String> htmlBodies = [];
  final List<_AttachmentCandidate> attachments = [];
  int anonymousCounter = 0;
}
