import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/mail/import/eml_parser.dart';
import 'package:solwatt/mail/import/mail_import_file_reader.dart';
import 'package:solwatt/mail/import/mail_import_models.dart';
import 'package:solwatt/mail/import/mbox_parser.dart';

/// Parses one file's bytes. Dispatch is by extension (`.eml` / `.mbox`);
/// unknown extensions fall back to content sniffing (an mbox starts with a
/// `From ` envelope delimiter, an EML with headers).
List<ParsedMailMessage> parseMailBytes(
  Uint8List bytes, {
  required String fileName,
  required String sourceLabel,
}) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.mbox')) {
    return MboxParser.parseBytes(bytes, sourceLabel: sourceLabel);
  }
  if (lower.endsWith('.eml')) {
    return [EmlParser.parseBytes(bytes, sourceLabel: sourceLabel)];
  }
  final text = String.fromCharCodes(bytes.take(1024));
  final looksLikeMbox = RegExp(
    r'^From (-\S*|\S+@\S+)( .*)?$',
    multiLine: true,
  ).hasMatch(text);
  return looksLikeMbox
      ? MboxParser.parseBytes(bytes, sourceLabel: sourceLabel)
      : [EmlParser.parseBytes(bytes, sourceLabel: sourceLabel)];
}

/// One picked file to parse off the main isolate. Desktop picks carry a
/// [path] so the isolate reads the file itself; web picks (no filesystem)
/// pass the already-read [bytes] instead.
class ImportParseInput {
  const ImportParseInput({this.path, this.bytes, required this.name});

  final String? path;
  final Uint8List? bytes;
  final String name;
}

/// Per-file parse result. [error] is the message of the first failure, so
/// non-sendable exception objects never cross the isolate boundary.
class ImportParseOutput {
  const ImportParseOutput({
    required this.name,
    required this.messages,
    this.error,
  });

  final String name;
  final List<ParsedMailMessage> messages;
  final String? error;
}

/// `compute()` callback: reads each input (from disk when a path is present)
/// and parses it, so huge archives never load or decode on the main isolate.
/// Failures are collected per file instead of being rethrown, because
/// exception objects (e.g. [MailImportException.cause]) may not be sendable.
List<ImportParseOutput> parseImportFiles(List<ImportParseInput> inputs) {
  final outputs = <ImportParseOutput>[];
  for (final input in inputs) {
    try {
      final Uint8List bytes;
      if (input.path != null) {
        bytes = readImportFileSync(input.path!);
      } else if (input.bytes != null) {
        bytes = input.bytes!;
      } else {
        throw const MailImportException(
          'Could not read the selected file: no path or bytes.',
        );
      }
      outputs.add(
        ImportParseOutput(
          name: input.name,
          messages: parseMailBytes(
            bytes,
            fileName: input.name,
            sourceLabel: input.name,
          ),
        ),
      );
    } catch (error) {
      outputs.add(
        ImportParseOutput(
          name: input.name,
          messages: const [],
          error: error is MailImportException
              ? error.message
              : error.toString(),
        ),
      );
    }
  }
  return outputs;
}

/// Client-side mail import logic layer: parses selected `.eml` files and
/// `.mbox` archives into ElecPostal import items, uploads decoded attachments
/// to workspace Drive, and POSTs the batches to `POST /postal/import`.
///
/// The server accepts at most 500 items per request, so larger imports are
/// chunked automatically; [MailImportProgress] is reported after each chunk.
/// Dedupe is delegated to the server (`message_id` per mailbox), so re-running
/// an import after a partial failure skips what already landed.
///
/// Parsing is pure Dart ([parseBytes]); only reading files by path needs a
/// platform implementation ([readImportFile]) — web callers pass picked file
/// bytes straight to [parseBytes].
class MailImportService {
  MailImportService({
    WattEngineClient? client,
    Future<MailImportResult> Function(
      List<Map<String, dynamic>> items,
      bool dedupe,
    )?
    poster,
    Future<String> Function(ImportAttachment attachment, String workspaceId)?
    attachmentUploader,
  }) : _poster =
           poster ??
           (client == null
               ? throw ArgumentError(
                   'A WattEngineClient or poster callback is required.',
                 )
               : (items, dedupe) =>
                     client.importEmails(items: items, dedupe: dedupe)),
       _uploader =
           attachmentUploader ??
           (client == null
               ? null
               : (attachment, workspaceId) async =>
                     (await client.uploadCloudFile(
                       bytes: attachment.bytes,
                       fileName: attachment.fileName,
                       workspaceId: workspaceId,
                       contentType: attachment.contentType,
                     )).id);

  /// Posts one ≤500-item batch; injectable for tests.
  final Future<MailImportResult> Function(
    List<Map<String, dynamic>> items,
    bool dedupe,
  )
  _poster;

  /// Uploads one decoded attachment to workspace Drive, returning the file
  /// ID; null when no client or uploader was provided, in which case imports
  /// with attachments fail with a clear message.
  final Future<String> Function(
    ImportAttachment attachment,
    String workspaceId,
  )?
  _uploader;

  /// ElecPostal's per-request item cap.
  static const maxBatchSize = 500;

  // --- parsing ----------------------------------------------------------------

  /// Reads each path and parses `.eml` and `.mbox` files into messages.
  /// Mbox members are labelled `path#N`; failures surface per file via
  /// [MailImportException] and name the offending file.
  Future<List<ParsedMailMessage>> parseFiles(List<String> paths) async {
    final messages = <ParsedMailMessage>[];
    for (final path in paths) {
      final bytes = await readImportFile(path);
      final name = path.split(RegExp(r'[/\\]')).last;
      messages.addAll(parseBytes(bytes, fileName: name, sourceLabel: path));
    }
    return messages;
  }

  /// Parses one file's bytes. Dispatch is by extension (`.eml` / `.mbox`);
  /// unknown extensions fall back to content sniffing (an mbox starts with a
  /// `From ` envelope delimiter, an EML with headers).
  List<ParsedMailMessage> parseBytes(
    Uint8List bytes, {
    required String fileName,
    required String sourceLabel,
  }) => parseMailBytes(bytes, fileName: fileName, sourceLabel: sourceLabel);

  // --- import -----------------------------------------------------------------

  /// Imports parsed [messages] into [mailboxId]'s INBOX.
  ///
  /// - [dedupe] (default true) asks the server to skip `message_id`s already
  ///   present in the mailbox (also across re-runs).
  /// - [uploadAttachments] uploads each decoded attachment to workspace Drive
  ///   (requires [workspaceId]) and references it in the import; without a
  ///   workspace the request fails rather than silently dropping attachments.
  /// - [onProgress] is called after each request chunk with cumulative counts.
  ///
  /// Throws [MailImportException] for invalid arguments, attachment upload
  /// failures, or a rejected request; [MailImportException.partial] carries
  /// any chunks that already succeeded.
  Future<MailImportResult> import({
    required List<ParsedMailMessage> messages,
    required String mailboxId,
    String? workspaceId,
    bool dedupe = true,
    bool uploadAttachments = true,
    void Function(MailImportProgress progress)? onProgress,
  }) async {
    if (messages.isEmpty) {
      throw const MailImportException('No messages to import.');
    }
    final mailbox = mailboxId.trim();
    if (mailbox.isEmpty) {
      throw const MailImportException('A target mailbox is required.');
    }
    final needsWorkspace =
        uploadAttachments && messages.any((m) => m.attachments.isNotEmpty);
    if (needsWorkspace && (workspaceId == null || workspaceId.trim().isEmpty)) {
      throw const MailImportException(
        'Workspace Drive is required to upload message attachments. '
        'Pass the workspace or disable attachment upload.',
      );
    }

    final result = MailImportResult();
    final total = messages.length;
    for (var start = 0; start < total; start += maxBatchSize) {
      final end = min(start + maxBatchSize, total);
      final chunk = messages.sublist(start, end);

      final payload = <Map<String, dynamic>>[];
      for (final message in chunk) {
        final attachmentIds = <String>[];
        if (uploadAttachments && message.attachments.isNotEmpty) {
          final uploader = _uploader;
          if (uploader == null) {
            throw const MailImportException(
              'Attachment upload is unavailable; a WattEngineClient or '
              'attachment uploader is required to import messages with '
              'attachments.',
            );
          }
          for (final attachment in message.attachments) {
            try {
              attachmentIds.add(
                await uploader(attachment, workspaceId!.trim()),
              );
            } on DioException catch (error) {
              throw MailImportException(
                'Failed to upload attachment "${attachment.fileName}" of '
                '${message.sourceLabel}: ${wattApiErrorMessage(error)}',
                partial: _snapshot(result),
              );
            } catch (error) {
              throw MailImportException(
                'Failed to upload attachment "${attachment.fileName}" of '
                '${message.sourceLabel}: $error',
                partial: _snapshot(result),
                cause: error,
              );
            }
          }
        }
        payload.add(_itemToJson(message, mailbox, attachmentIds));
      }

      final MailImportResult chunkResult;
      try {
        chunkResult = await _poster(payload, dedupe);
      } on DioException catch (error) {
        throw MailImportException(
          'Import request failed (${start + 1}–$end of $total): '
          '${wattApiErrorMessage(error)}',
          partial: _snapshot(result),
          cause: error,
        );
      }

      for (final item in chunkResult.items) {
        final globalIndex = start + item.index;
        final source = globalIndex < total
            ? messages[globalIndex].sourceLabel
            : null;
        result.items.add(item.withPosition(globalIndex, source));
      }
      result.imported += chunkResult.imported;
      result.duplicates += chunkResult.duplicates;
      result.failed += chunkResult.failed;
      onProgress?.call(
        MailImportProgress(
          processed: end,
          total: total,
          imported: result.imported,
          duplicates: result.duplicates,
          failed: result.failed,
        ),
      );
    }
    return result;
  }

  /// Convenience: parse [paths] then import them. Throws before any upload if
  /// a file cannot be read or parsed.
  Future<MailImportResult> importFiles({
    required List<String> paths,
    required String mailboxId,
    String? workspaceId,
    bool dedupe = true,
    bool uploadAttachments = true,
    void Function(MailImportProgress progress)? onProgress,
  }) async {
    final messages = await parseFiles(paths);
    return import(
      messages: messages,
      mailboxId: mailboxId,
      workspaceId: workspaceId,
      dedupe: dedupe,
      uploadAttachments: uploadAttachments,
      onProgress: onProgress,
    );
  }

  /// Serializes one parsed message into the ElecPostal import item shape
  /// (exercised by the service tests).
  Map<String, dynamic> itemToJson(
    ParsedMailMessage message,
    String mailboxId,
    List<String> attachmentIds,
  ) => _itemToJson(message, mailboxId, attachmentIds);

  static Map<String, dynamic> _itemToJson(
    ParsedMailMessage message,
    String mailboxId,
    List<String> attachmentIds,
  ) {
    return {
      'mailbox_id': mailboxId,
      if (message.messageId != null && message.messageId!.isNotEmpty)
        'message_id': message.messageId,
      if (message.inReplyTo.isNotEmpty) 'in_reply_to': message.inReplyTo,
      if (message.references.isNotEmpty) 'references': message.references,
      'from_address': message.fromAddress,
      if (message.fromName != null && message.fromName!.isNotEmpty)
        'from_name': message.fromName,
      'subject': message.subject,
      'body': message.body,
      'content_type': message.contentType,
      'to': message.to.map((r) => r.toJson()).toList(),
      'cc': message.cc.map((r) => r.toJson()).toList(),
      if (message.sentAt != null)
        'sent_at': message.sentAt!.toUtc().toIso8601String(),
      'attachment_ids': attachmentIds,
    };
  }

  static MailImportResult _snapshot(MailImportResult result) =>
      MailImportResult(
        imported: result.imported,
        duplicates: result.duplicates,
        failed: result.failed,
        items: [...result.items],
      );
}
