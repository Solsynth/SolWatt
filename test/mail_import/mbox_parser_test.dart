import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:solwatt/mail/import/mbox_parser.dart';

void main() {
  group('MboxParser', () {
    test('splits multiple messages and labels them by index', () {
      final source = '''From alice@example.com Tue Jan  6 08:13:34 2015
From: alice@example.com
To: bob@example.com
Subject: First
Message-ID: <one@example.com>

First body.

From bob@example.com Wed Jan  7 09:00:00 2015
From: bob@example.com
To: alice@example.com
Subject: Second
Message-ID: <two@example.com>

Second body.
''';
      final messages = MboxParser.parse(source, sourceLabel: 'backup.mbox');
      expect(messages, hasLength(2));
      expect(messages[0].subject, 'First');
      expect(messages[0].body.trim(), 'First body.');
      expect(messages[0].sourceLabel, 'backup.mbox#1');
      expect(messages[1].subject, 'Second');
      expect(messages[1].body.trim(), 'Second body.');
      expect(messages[1].sourceLabel, 'backup.mbox#2');
    });

    test('handles Gmail-style From - delimiters', () {
      final source = '''From - Tue May 05 14:35:00 2015
From: a@example.com
Subject: Gmail one
Message-ID: <g1@example.com>

Body one.

From - Wed May 06 10:00:00 2015
From: b@example.com
Subject: Gmail two
Message-ID: <g2@example.com>

Body two.
''';
      final messages = MboxParser.parse(source, sourceLabel: 'gmail.mbox');
      expect(messages, hasLength(2));
      expect(messages[0].subject, 'Gmail one');
      expect(messages[1].subject, 'Gmail two');
    });

    test('unescapes mboxrd >From content lines', () {
      final source = '''From a@example.com Tue Jan  6 08:13:34 2015
From: a@example.com
Subject: Escaped
Message-ID: <esc@example.com>

>From the desk of the sender, a quote.

From b@example.com Wed Jan  7 09:00:00 2015
From: b@example.com
Subject: Second
Message-ID: <two@example.com>

Second body.
''';
      final messages = MboxParser.parse(source, sourceLabel: 'rd.mbox');
      expect(messages, hasLength(2));
      expect(messages[0].body.trim(), 'From the desk of the sender, a quote.');
    });

    test('does not split on prose lines starting with From', () {
      final source = '''From a@example.com Tue Jan  6 08:13:34 2015
From: a@example.com
Subject: Prose
Message-ID: <p@example.com>

From my desk to yours, keep reading.
From time to time this happens.
''';
      final messages = MboxParser.parse(source, sourceLabel: 'prose.mbox');
      expect(messages, hasLength(1));
      expect(messages.single.body, contains('From my desk to yours'));
      expect(messages.single.body, contains('From time to time'));
    });

    test('falls back to a single EML when there are no boundaries', () {
      final eml = '''From: a@example.com
Subject: Not mbox
Message-ID: <n@example.com>

Body.
''';
      final messages = MboxParser.parse(eml, sourceLabel: 'loose.mbox');
      expect(messages, hasLength(1));
      expect(messages.single.subject, 'Not mbox');
    });

    test('parses attachments inside mbox members', () {
      final png = base64.encode([9, 8, 7]);
      final source =
          '''From a@example.com Tue Jan  6 08:13:34 2015
From: a@example.com
Content-Type: multipart/mixed; boundary="mx"
Subject: With file
Message-ID: <att@example.com>

--mx
Content-Type: text/plain

Text.

--mx
Content-Type: image/png
Content-Disposition: attachment; filename="dot.png"
Content-Transfer-Encoding: base64

$png

--mx--
''';
      final messages = MboxParser.parse(source, sourceLabel: 'att.mbox');
      expect(messages, hasLength(1));
      final attachment = messages.single.attachments.single;
      expect(attachment.fileName, 'dot.png');
      expect(attachment.contentType, 'image/png');
      expect(attachment.bytes, [9, 8, 7]);
    });

    test('parses raw bytes', () {
      final source = '''From a@example.com Tue Jan  6 08:13:34 2015
From: a@example.com
Subject: Bytes
Message-ID: <b@example.com>

Body.
''';
      final messages = MboxParser.parseBytes(
        utf8.encode(source),
        sourceLabel: 'bytes.mbox',
      );
      expect(messages.single.subject, 'Bytes');
    });

    test('treats an empty or blank file as a single empty message', () {
      final messages = MboxParser.parse('\n\n', sourceLabel: 'blank.mbox');
      expect(messages, isEmpty);
    });
  });
}
