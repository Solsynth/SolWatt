import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solwatt/mail/import/mail_import_models.dart';
import 'package:solwatt/mail/import/mail_import_service.dart';
import 'package:solwatt/network.dart';

ParsedMailMessage _message(
  int i, {
  List<ImportAttachment> attachments = const [],
  String? messageId,
  List<String> inReplyTo = const [],
  List<String> references = const [],
}) => ParsedMailMessage(
  messageId: messageId ?? 'id-$i@example.com',
  inReplyTo: inReplyTo,
  references: references,
  fromAddress: 'sender-$i@example.net',
  fromName: 'Sender $i',
  subject: 'Subject $i',
  body: 'Body $i',
  to: const [ImportRecipient(address: 'a@example.com')],
  cc: const [ImportRecipient(address: 'c@example.com', kind: 'cc')],
  sentAt: DateTime.utc(2026, 1, 1, 0, 0, i),
  attachments: attachments,
  sourceLabel: 'backup.mbox#$i',
);

void main() {
  group('MailImportService', () {
    test('serializes a message into the backend item shape', () {
      final service = MailImportService(
        poster: (_, _) async => MailImportResult(),
      );
      final json = service.itemToJson(
        _message(
          1,
          inReplyTo: const ['id-0@example.com'],
          references: const ['id-0@example.com'],
        ),
        'mb-1',
        ['file-1', 'file-2'],
      );
      expect(json['mailbox_id'], 'mb-1');
      expect(json['message_id'], 'id-1@example.com');
      expect(json['in_reply_to'], ['id-0@example.com']);
      expect(json['references'], ['id-0@example.com']);
      expect(json['from_address'], 'sender-1@example.net');
      expect(json['from_name'], 'Sender 1');
      expect(json['subject'], 'Subject 1');
      expect(json['body'], 'Body 1');
      expect(json['content_type'], 'text/plain');
      expect(json['to'], [
        {'address': 'a@example.com', 'kind': 'to'},
      ]);
      expect(json['cc'], [
        {'address': 'c@example.com', 'kind': 'cc'},
      ]);
      expect(json['sent_at'], '2026-01-01T00:00:01.000Z');
      expect(json['attachment_ids'], ['file-1', 'file-2']);
    });

    test('omits optional fields when absent', () {
      final service = MailImportService(
        poster: (_, _) async => MailImportResult(),
      );
      final json = service.itemToJson(
        ParsedMailMessage(
          fromAddress: 'sender@example.net',
          subject: 'No extras',
          body: 'Body',
          to: const [],
          cc: const [],
          sourceLabel: 'plain.eml',
        ),
        'mb-1',
        const [],
      );
      expect(json.containsKey('message_id'), isFalse);
      expect(json.containsKey('in_reply_to'), isFalse);
      expect(json.containsKey('references'), isFalse);
      expect(json.containsKey('from_name'), isFalse);
      expect(json.containsKey('sent_at'), isFalse);
      expect(json['to'], isEmpty);
      expect(json['cc'], isEmpty);
    });

    test('dispatches .eml, .mbox, and unknown extensions by content', () {
      final service = MailImportService(
        poster: (_, _) async => MailImportResult(),
      );
      final eml = utf8.encode('''From: a@example.com
Subject: Single
Message-ID: <s@example.com>

Body.
''');
      final mbox = utf8.encode('''From a@example.com Tue Jan  6 08:13:34 2015
From: a@example.com
Subject: One
Message-ID: <o@example.com>

One.

From b@example.com Wed Jan  7 09:00:00 2015
From: b@example.com
Subject: Two
Message-ID: <t@example.com>

Two.
''');

      expect(
        service.parseBytes(eml, fileName: 'a.eml', sourceLabel: 'a.eml'),
        hasLength(1),
      );
      expect(
        service.parseBytes(mbox, fileName: 'b.mbox', sourceLabel: 'b.mbox'),
        hasLength(2),
      );
      // Unknown extension but mbox-shaped → mbox.
      expect(
        service.parseBytes(mbox, fileName: 'backup.bak', sourceLabel: 'b'),
        hasLength(2),
      );
      // Unknown extension but EML-shaped → single EML.
      expect(
        service.parseBytes(eml, fileName: 'note.msg', sourceLabel: 'n'),
        hasLength(1),
      );
    });

    test('chunks large imports into ≤500-item requests', () async {
      final batches = <List<Map<String, dynamic>>>[];
      final dedupes = <bool>[];
      final service = MailImportService(
        poster: (items, dedupe) async {
          batches.add(items);
          dedupes.add(dedupe);
          return MailImportResult(
            imported: items.length,
            items: [
              for (var i = 0; i < items.length; i++)
                MailImportItemResult(index: i, status: 'imported'),
            ],
          );
        },
      );
      final messages = [for (var i = 0; i < 520; i++) _message(i)];
      final result = await service.import(
        messages: messages,
        mailboxId: 'mb-1',
      );

      expect(batches, hasLength(2));
      expect(batches[0], hasLength(500));
      expect(batches[1], hasLength(20));
      expect(dedupes, [true, true]);
      expect(result.imported, 520);
      expect(result.duplicates, 0);
      expect(result.failed, 0);
      // Backend indexes are per request; service offsets to global positions.
      expect(result.items.first.index, 0);
      expect(result.items.last.index, 519);
      expect(result.items.last.source, 'backup.mbox#519');
      expect(result.items[499].source, 'backup.mbox#499');
      expect(result.items[500].index, 500);
    });

    test('passes dedupe=false through', () async {
      final dedupes = <bool>[];
      final service = MailImportService(
        poster: (items, dedupe) async {
          dedupes.add(dedupe);
          return MailImportResult();
        },
      );
      await service.import(
        messages: [_message(0)],
        mailboxId: 'mb-1',
        dedupe: false,
      );
      expect(dedupes, [false]);
    });

    test('uploads attachments and references the returned file ids', () async {
      final uploaded = <String>[];
      final batches = <List<Map<String, dynamic>>>[];
      final service = MailImportService(
        poster: (items, dedupe) async {
          batches.add(items);
          return MailImportResult(
            imported: items.length,
            items: [
              for (var i = 0; i < items.length; i++)
                MailImportItemResult(index: i, status: 'imported'),
            ],
          );
        },
        attachmentUploader: (attachment, workspaceId) async {
          uploaded.add('$workspaceId/${attachment.fileName}');
          return 'file-${uploaded.length}';
        },
      );
      final messages = [
        _message(0),
        _message(
          1,
          attachments: [
            ImportAttachment(
              fileName: 'report.pdf',
              contentType: 'application/pdf',
              bytes: Uint8List.fromList([1, 2, 3]),
            ),
            ImportAttachment(
              fileName: 'logo.png',
              contentType: 'image/png',
              bytes: Uint8List.fromList([4]),
            ),
          ],
        ),
      ];
      await service.import(
        messages: messages,
        mailboxId: 'mb-1',
        workspaceId: 'ws-9',
      );

      expect(uploaded, ['ws-9/report.pdf', 'ws-9/logo.png']);
      expect(batches.single[0]['attachment_ids'], isEmpty);
      expect(batches.single[1]['attachment_ids'], ['file-1', 'file-2']);
    });

    test('requires a workspace when attachments must be uploaded', () async {
      final service = MailImportService(
        poster: (_, _) async => MailImportResult(),
      );
      final messages = [
        _message(
          0,
          attachments: [
            ImportAttachment(
              fileName: 'a.bin',
              contentType: 'application/octet-stream',
              bytes: Uint8List.fromList([1]),
            ),
          ],
        ),
      ];
      await expectLater(
        service.import(messages: messages, mailboxId: 'mb-1'),
        throwsA(
          isA<MailImportException>().having(
            (e) => e.message,
            'message',
            contains('Workspace Drive'),
          ),
        ),
      );
    });

    test('rejects an empty import', () async {
      final service = MailImportService(
        poster: (_, _) async => MailImportResult(),
      );
      await expectLater(
        service.import(messages: const [], mailboxId: 'mb-1'),
        throwsA(
          isA<MailImportException>().having(
            (e) => e.message,
            'message',
            'No messages to import.',
          ),
        ),
      );
    });

    test(
      'wraps a rejected request and carries prior partial results',
      () async {
        var calls = 0;
        final service = MailImportService(
          poster: (items, dedupe) async {
            calls++;
            if (calls == 2) {
              throw DioException(
                requestOptions: RequestOptions(path: '/postal/import'),
              );
            }
            return MailImportResult(
              imported: items.length,
              items: [
                for (var i = 0; i < items.length; i++)
                  MailImportItemResult(index: i, status: 'imported'),
              ],
            );
          },
        );
        final messages = [for (var i = 0; i < 510; i++) _message(i)];
        try {
          await service.import(messages: messages, mailboxId: 'mb-1');
          fail('expected MailImportException');
        } on MailImportException catch (error) {
          expect(error.message, contains('Import request failed'));
          expect(error.partial, isNotNull);
          expect(error.partial!.imported, 500);
        }
      },
    );

    test('reports cumulative progress after each chunk', () async {
      final progress = <MailImportProgress>[];
      final service = MailImportService(
        poster: (items, dedupe) async => MailImportResult(
          imported: items.length,
          items: [
            for (var i = 0; i < items.length; i++)
              MailImportItemResult(index: i, status: 'imported'),
          ],
        ),
      );
      await service.import(
        messages: [for (var i = 0; i < 520; i++) _message(i)],
        mailboxId: 'mb-1',
        onProgress: progress.add,
      );
      expect(progress, hasLength(2));
      expect(progress[0].processed, 500);
      expect(progress[0].total, 520);
      expect(progress[0].imported, 500);
      expect(progress[1].processed, 520);
      expect(progress[1].imported, 520);
    });

    test('parses and maps duplicate results with sources', () async {
      final service = MailImportService(
        poster: (items, dedupe) async => MailImportResult(
          duplicates: 1,
          items: const [MailImportItemResult(index: 0, status: 'duplicate')],
        ),
      );
      final result = await service.import(
        messages: [_message(3)],
        mailboxId: 'mb-1',
      );
      expect(result.imported, 0);
      expect(result.duplicates, 1);
      expect(result.items.single.status, 'duplicate');
      expect(result.items.single.source, 'backup.mbox#3');
      expect(result.items.single.emailId, isNull);
    });
  });

  group('parseImportFiles (background isolate entry point)', () {
    test('reads mbox files by path and reports per-file errors', () {
      final dir = Directory.systemTemp.createTempSync('solwatt-import-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final mbox = File('${dir.path}/archive.mbox')
        ..writeAsStringSync(
          'From alice@example.com Sat Sep 25 10:00:00 2026\n'
          'Subject: one\n\nbody one\n'
          'From bob@example.com Sat Sep 25 11:00:00 2026\n'
          'Subject: two\n\nbody two\n',
        );
      final broken = File('${dir.path}/broken.eml')
        ..writeAsStringSync('not an email at all');

      final outputs = parseImportFiles([
        ImportParseInput(path: mbox.path, name: 'archive.mbox'),
        ImportParseInput(path: '${dir.path}/missing.mbox', name: 'missing.mbox'),
        ImportParseInput(path: broken.path, name: 'broken.eml'),
        const ImportParseInput(name: 'bytes.eml', bytes: null),
      ]);

      expect(outputs[0].error, isNull);
      expect(outputs[0].messages, hasLength(2));
      expect(outputs[0].messages.first.subject, 'one');
      expect(outputs[0].messages.last.sourceLabel, 'archive.mbox#2');

      // Missing file and no-path/no-bytes inputs surface as messages.
      expect(outputs[1].messages, isEmpty);
      expect(outputs[1].error, isNotNull);
      expect(outputs[3].messages, isEmpty);
      expect(outputs[3].error, isNotNull);
    });
  });
}
