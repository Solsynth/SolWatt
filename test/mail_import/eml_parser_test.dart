import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:solwatt/mail/import/eml_parser.dart';
import 'package:solwatt/mail/import/mail_import_models.dart';

void main() {
  ParsedMailMessage parse(String eml, {String label = 'sample.eml'}) =>
      EmlParser.parse(eml, sourceLabel: label);

  group('EmlParser', () {
    test('parses a plain text message with full headers', () {
      final message = parse('''From: "Doe, John" <john@example.com>
To: alice@example.com, "Bob Builder" <bob@example.net>
Cc: carol@example.org
Subject: Hello world
Date: Tue, 06 Jan 2015 08:13:34 +0000
Message-ID: <abc123@example.com>

This is the body.
''');
      expect(message.fromAddress, 'john@example.com');
      expect(message.fromName, 'Doe, John');
      expect(message.to.map((r) => r.address).toList(), [
        'alice@example.com',
        'bob@example.net',
      ]);
      expect(message.to[1].name, 'Bob Builder');
      expect(message.cc.map((r) => r.address).toList(), ['carol@example.org']);
      expect(message.subject, 'Hello world');
      expect(message.body.trim(), 'This is the body.');
      expect(message.contentType, 'text/plain');
      expect(message.messageId, 'abc123@example.com');
      expect(message.sentAt, DateTime.utc(2015, 1, 6, 8, 13, 34));
      expect(message.attachments, isEmpty);
    });

    test('parses the In-Reply-To and References reply chain', () {
      final message = parse('''From: bob@example.net
To: alice@example.com
Subject: Re: Hello world
Message-ID: <reply@example.com>
In-Reply-To: <abc123@example.com>
References: <root@example.com>
	<abc123@example.com>

Body.
''');
      expect(message.messageId, 'reply@example.com');
      expect(message.inReplyTo, ['abc123@example.com']);
      // Continuation lines unfold; ids come back without angle brackets.
      expect(message.references, ['root@example.com', 'abc123@example.com']);
    });

    test('decodes RFC 2047 encoded words in subject and display names', () {
      final message = parse('''From: =?UTF-8?B?5L2g5aW9?= <zhang@example.com>
Subject: =?UTF-8?B?5L2g5aW9?= =?UTF-8?B?ISDkuJbnlYw=?=
Message-ID: <x@example.com>

Body.
''');
      expect(message.fromName, '你好');
      expect(message.subject, '你好! 世界');
      expect(message.fromAddress, 'zhang@example.com');
    });

    test('decodes Q-encoded words with latin-1 charset', () {
      final message = parse('''From: a@example.com
Subject: =?iso-8859-1?Q?Caf=E9_au_lait?=
Message-ID: <x@example.com>

Body.
''');
      expect(message.subject, 'Café au lait');
    });

    test('decodes a quoted-printable latin-1 body with soft line breaks', () {
      final message = parse('''From: a@example.com
Content-Type: text/plain; charset=iso-8859-1
Content-Transfer-Encoding: quoted-printable
Message-ID: <x@example.com>

Caf=E9 au lait, c'est =
la vie.
''');
      expect(message.body, "Café au lait, c'est la vie.\n");
    });

    test('decodes a base64 body', () {
      final body = 'Hello base64 body';
      final encoded = base64.encode(utf8.encode(body));
      final message = parse('''From: a@example.com
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: base64
Message-ID: <x@example.com>

$encoded
''');
      expect(message.body.trim(), body);
    });

    test('prefers the text/plain part of multipart/alternative', () {
      final message = parse('''From: a@example.com
Content-Type: multipart/alternative; boundary="b1"
Message-ID: <x@example.com>

--b1
Content-Type: text/plain; charset=utf-8

Plain version.

--b1
Content-Type: text/html; charset=utf-8

<p>HTML version.</p>

--b1--
''');
      expect(message.body.trim(), 'Plain version.');
      expect(message.contentType, 'text/plain');
    });

    test('falls back to the html body when there is no plain part', () {
      final message = parse('''From: a@example.com
Content-Type: text/html; charset=utf-8
Message-ID: <x@example.com>

<h1>HTML only</h1>
''');
      expect(message.body, '<h1>HTML only</h1>\n');
      expect(message.contentType, 'text/html');
    });

    test('extracts base64 attachments with disposition filename', () {
      final pdf = base64.encode(List.generate(8, (i) => i));
      final message = parse('''From: a@example.com
Content-Type: multipart/mixed; boundary="mix"
Message-ID: <x@example.com>

--mix
Content-Type: text/plain; charset=utf-8

See the report.

--mix
Content-Type: application/pdf
Content-Disposition: attachment; filename="report.pdf"
Content-Transfer-Encoding: base64

$pdf

--mix--
''');
      expect(message.attachments, hasLength(1));
      final attachment = message.attachments.single;
      expect(attachment.fileName, 'report.pdf');
      expect(attachment.contentType, 'application/pdf');
      expect(attachment.bytes, List.generate(8, (i) => i));
    });

    test('names a part from its filename when it declares no type', () {
      final jpeg = base64.encode(List.generate(8, (i) => i));
      final message = parse('''From: a@example.com
Content-Type: multipart/mixed; boundary="mix"
Message-ID: <x@example.com>

--mix
Content-Type: text/plain; charset=utf-8

See attached.

--mix
Content-Disposition: attachment; filename="shot.JPG"
Content-Transfer-Encoding: base64

$jpeg

--mix--
''');
      expect(message.attachments, hasLength(1));
      final attachment = message.attachments.single;
      expect(attachment.fileName, 'shot.JPG');
      expect(attachment.contentType, 'image/jpeg');
    });

    test('extracts named parts and content-id for inline images', () {
      final png = base64.encode([1, 2, 3, 4]);
      final message = parse('''From: a@example.com
Content-Type: multipart/related; boundary="rel"
Message-ID: <x@example.com>

--rel
Content-Type: text/html; charset=utf-8

<img src="cid:logo1">

--rel
Content-Type: image/png; name="logo.png"
Content-Disposition: inline
Content-ID: <logo1@example.com>
Content-Transfer-Encoding: base64

$png

--rel--
''');
      expect(message.contentType, 'text/html');
      final attachment = message.attachments.single;
      expect(attachment.fileName, 'logo.png');
      expect(attachment.contentType, 'image/png');
      expect(attachment.contentId, 'logo1@example.com');
      expect(attachment.bytes, [1, 2, 3, 4]);
    });

    test('handles folded headers and CRLF line endings', () {
      final message = EmlParser.parseBytes(
        utf8.encode(
          'From: a@example.com\r\nSubject: folded\r\n subject\r\nMessage-ID: <x@example.com>\r\n\r\nBody.\r\n',
        ),
        sourceLabel: 'crlf.eml',
      );
      expect(message.subject, 'folded subject');
      expect(message.body, 'Body.\r\n');
    });

    test('tolerates missing message-id and date', () {
      final message = parse('''From: a@example.com
Subject: No id

Body.
''');
      expect(message.messageId, isNull);
      expect(message.sentAt, isNull);
      expect(message.fromAddress, 'a@example.com');
    });

    test('parses obsolete date formats with named zones', () {
      expect(
        EmlParser.parseMailDate('Tue, 6 Jan 15 08:13:34 EST'),
        DateTime.utc(2015, 1, 6, 13, 13, 34),
      );
      expect(
        EmlParser.parseMailDate('Wed, 02 Jul 2026 23:59:59 -0330'),
        DateTime.utc(2026, 7, 3, 3, 29, 59),
      );
      expect(EmlParser.parseMailDate('not a date'), isNull);
    });

    test('skips group labels and drops address-less chunks', () {
      final message = parse('''From: a@example.com
To: Undisclosed recipients:, "Weird, Name" <w@example.com>
Message-ID: <x@example.com>

Body.
''');
      expect(message.to, hasLength(1));
      expect(message.to.single.address, 'w@example.com');
      expect(message.to.single.name, 'Weird, Name');
    });
  });
}
