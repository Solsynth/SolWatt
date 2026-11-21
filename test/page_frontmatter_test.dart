import 'package:flutter_test/flutter_test.dart';

import 'package:solwatt/ideask/page_markdown.dart';

void main() {
  group('splitPageFrontmatter', () {
    test('separates a leading YAML block from the body', () {
      const source =
          '---\ntitle: Runbook\ntags: [ops, deploy]\n---\n# Deploy\n\nShip it.';

      final split = splitPageFrontmatter(source);

      expect(
        split.frontmatter,
        '---\ntitle: Runbook\ntags: [ops, deploy]\n---\n',
      );
      expect(split.body, '# Deploy\n\nShip it.');
      expect(split.hasFrontmatter, isTrue);
      expect(composePageMarkdown(split), source);
    });

    test('keeps a document without frontmatter whole', () {
      const source = '# Deploy\n\nShip it.';

      final split = splitPageFrontmatter(source);

      expect(split.frontmatter, isEmpty);
      expect(split.body, source);
      expect(split.hasFrontmatter, isFalse);
    });

    test('accepts a closing delimiter with CRLF', () {
      const source = '---\r\ntitle: Runbook\r\n---\r\nBody';

      final split = splitPageFrontmatter(source);

      expect(split.frontmatter, '---\r\ntitle: Runbook\r\n---\r\n');
      expect(split.body, 'Body');
      expect(composePageMarkdown(split), source);
    });

    test('does not treat the YAML end marker as the closing delimiter', () {
      const source = '---\ntitle: Runbook\n...\nBody';

      final split = splitPageFrontmatter(source);

      expect(split.frontmatter, isEmpty);
      expect(split.body, source);
    });

    test('allows an empty block', () {
      const source = '---\n---\nBody';

      final split = splitPageFrontmatter(source);

      expect(split.frontmatter, '---\n---\n');
      expect(split.body, 'Body');
    });

    test('ignores an unclosed opening fence', () {
      const source = '---\ntitle: Runbook\n\nBody';

      final split = splitPageFrontmatter(source);

      expect(split.frontmatter, isEmpty);
      expect(split.body, source);
    });

    test('ignores a fence that is not on the first line', () {
      const source = '\n---\ntitle: Runbook\n---\nBody';

      final split = splitPageFrontmatter(source);

      expect(split.frontmatter, isEmpty);
      expect(split.body, source);
    });

    test('adds the newline a closing delimiter may lack when composing', () {
      const frontmatter = '---\ntitle: Runbook\n---';

      expect(
        composePageMarkdown(
          const PageMarkdown(frontmatter: frontmatter, body: 'Body'),
        ),
        '$frontmatter\nBody',
      );
    });
  });
}
