/// A page's Markdown is stored with the YAML frontmatter block that leads it.
///
/// The block is metadata, not prose: rendering it would turn the `---`
/// delimiters into rules and setext headings, and loading it into the block
/// editor would rewrite the YAML as Markdown on the next save. So the editor
/// and the renderers only ever see [PageMarkdown.body], while the raw block is
/// kept aside and re-attached when the page is saved.
library;

/// One page document split into its raw frontmatter block and its prose.
class PageMarkdown {
  const PageMarkdown({required this.frontmatter, required this.body});

  /// The leading `---` … `---` block, delimiters included. Empty when the
  /// document has no frontmatter.
  final String frontmatter;

  /// Everything after the block; the whole document when there is no
  /// frontmatter.
  final String body;

  bool get hasFrontmatter => frontmatter.isNotEmpty;
}

/// Splits [markdown] at the frontmatter block, preserving both halves byte for
/// byte.
///
/// The rule mirrors LightBeam's parser: the document must start with `---` on
/// its own first line, and the block ends at the next line that is exactly
/// `---` (a trailing `\r` is allowed). Anything else is ordinary Markdown.
PageMarkdown splitPageFrontmatter(String markdown) {
  final firstBreak = markdown.indexOf('\n');
  if (firstBreak == -1) return PageMarkdown(frontmatter: '', body: markdown);

  final openingLine = markdown.substring(0, firstBreak);
  if (openingLine != '---' && openingLine != '---\r') {
    return PageMarkdown(frontmatter: '', body: markdown);
  }

  var cursor = firstBreak + 1;
  while (cursor <= markdown.length) {
    final nextBreak = markdown.indexOf('\n', cursor);
    final lineEnd = nextBreak == -1 ? markdown.length : nextBreak;
    var line = markdown.substring(cursor, lineEnd);
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    if (line == '---') {
      final blockEnd = nextBreak == -1 ? markdown.length : nextBreak + 1;
      return PageMarkdown(
        frontmatter: markdown.substring(0, blockEnd),
        body: markdown.substring(blockEnd),
      );
    }
    if (nextBreak == -1) break;
    cursor = nextBreak + 1;
  }
  return PageMarkdown(frontmatter: '', body: markdown);
}

/// Joins the two halves back together, adding the newline the closing
/// delimiter line may lack.
String composePageMarkdown(PageMarkdown markdown) {
  if (!markdown.hasFrontmatter) return markdown.body;
  if (markdown.body.isEmpty) return markdown.frontmatter;
  final separator = markdown.frontmatter.endsWith('\n') ? '' : '\n';
  return '${markdown.frontmatter}$separator${markdown.body}';
}
