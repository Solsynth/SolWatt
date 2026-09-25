import 'dart:typed_data';

import 'package:solwatt/network.dart';

/// One recipient of an imported message, matching the ElecPostal
/// `RecipientInput` JSON shape.
class ImportRecipient {
  const ImportRecipient({required this.address, this.name, this.kind = 'to'});

  final String address;
  final String? name;

  /// `to` or `cc` (the backend import endpoint has no `bcc` field).
  final String kind;

  Map<String, dynamic> toJson() => {
    'address': address,
    if (name != null && name!.isNotEmpty) 'name': name,
    'kind': kind,
  };
}

/// One attachment decoded from an EML/MBOX message, before it is uploaded to
/// workspace Drive. [contentId] is the RFC 2392 Content-ID for inline parts.
class ImportAttachment {
  const ImportAttachment({
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

/// A single message parsed from an `.eml` file or one message of an `.mbox`
/// file. Field names mirror the ElecPostal import item contract so the
/// service can serialize directly.
class ParsedMailMessage {
  const ParsedMailMessage({
    this.messageId,
    required this.fromAddress,
    this.fromName,
    this.subject = '',
    required this.body,
    this.contentType = 'text/plain',
    this.to = const [],
    this.cc = const [],
    this.sentAt,
    this.attachments = const [],
    required this.sourceLabel,
  });

  /// RFC 5322 Message-ID without the surrounding angle brackets; null when the
  /// message had none. This is the backend's per-mailbox dedupe key.
  final String? messageId;
  final String fromAddress;
  final String? fromName;
  final String subject;

  /// Decoded message text — the text/plain body, or the text/html body when
  /// the message carried no plain-text part.
  final String body;

  /// `text/plain` or `text/html`.
  final String contentType;
  final List<ImportRecipient> to;
  final List<ImportRecipient> cc;
  final DateTime? sentAt;
  final List<ImportAttachment> attachments;

  /// Origin of the message (file path, or `file.mbox#3` for mbox members);
  /// surfaced in results and errors so the UI can point at the failing item.
  final String sourceLabel;
}

/// Thrown for whole-import failures (invalid arguments, attachment upload
/// failure, a rejected request). When some chunks already succeeded, [partial]
/// carries their aggregate so the UI can show progress lost to the failure.
class MailImportException implements Exception {
  const MailImportException(this.message, {this.partial, this.cause});

  final String message;
  final MailImportResult? partial;
  final Object? cause;

  @override
  String toString() => message;
}

/// Cumulative progress reported after each request chunk completes.
class MailImportProgress {
  const MailImportProgress({
    required this.processed,
    required this.total,
    required this.imported,
    required this.duplicates,
    required this.failed,
  });

  final int processed;
  final int total;
  final int imported;
  final int duplicates;
  final int failed;
}
