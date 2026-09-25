import 'dart:convert';
import 'dart:typed_data';

import 'package:solwatt/mail/import/eml_parser.dart';
import 'package:solwatt/mail/import/mail_import_models.dart';

/// Splits an RFC 4155 mbox file into its member messages and parses each one
/// with [EmlParser].
///
/// The message delimiter is a line starting with `From ` followed by an
/// envelope sender (an email address, or `-` as written by Gmail and
/// Thunderbird) — the RFC 4155 form. This deliberately rejects `From ` lines
/// without an email-like sender so prose that happens to start with
/// "From word ..." is not mistaken for a boundary. mboxrd `>From ` escaping is
/// undone per message.
class MboxParser {
  MboxParser._();

  /// RFC 4155 delimiter: `From` + sender (email-ish or `-…`) + optional
  /// remainder (usually the date).
  static final RegExp _boundary = RegExp(
    r'^From (-\S*|\S+@\S+)( .*)?$',
    multiLine: true,
  );

  /// Parses raw [bytes] of an mbox file. Each member message is labelled
  /// `sourceLabel#N` (1-based) so results and errors can name the exact
  /// message. A file with no boundaries is treated as a single EML message.
  static List<ParsedMailMessage> parseBytes(
    Uint8List bytes, {
    required String sourceLabel,
  }) {
    return parse(latin1.decode(bytes), sourceLabel: sourceLabel);
  }

  static List<ParsedMailMessage> parse(
    String source, {
    required String sourceLabel,
  }) {
    if (source.trim().isEmpty) return const [];
    final boundaries = <int>[];
    for (final match in _boundary.allMatches(source)) {
      boundaries.add(match.start);
    }
    if (boundaries.isEmpty) {
      return [EmlParser.parse(source, sourceLabel: sourceLabel)];
    }

    final messages = <ParsedMailMessage>[];
    for (var i = 0; i < boundaries.length; i++) {
      final start = boundaries[i];
      final end = i + 1 < boundaries.length ? boundaries[i + 1] : source.length;
      var chunk = source.substring(start, end);
      // The From_ delimiter line belongs to the envelope, not the message.
      final newline = chunk.indexOf('\n');
      chunk = newline == -1 ? '' : chunk.substring(newline + 1);
      // mboxrd: unescape ">From " content lines back to "From ".
      chunk = chunk.replaceAll(RegExp(r'^>From ', multiLine: true), 'From ');
      if (chunk.trim().isEmpty) continue;
      messages.add(
        EmlParser.parse(chunk, sourceLabel: '$sourceLabel#${i + 1}'),
      );
    }
    return messages;
  }
}
