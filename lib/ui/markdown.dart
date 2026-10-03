import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// SolWatt's Markdown renderer.
///
/// Ported from Solian's `shared/widgets/content/markdown.dart`: soft line
/// breaks, tight block spacing and themed code/rule chrome, so authored bodies
/// read the same in both apps. Solian's app-bound syntaxes (mention chips,
/// stickers, LaTeX) are left out — task content here is plain prose — and links
/// open in the external browser.
class MarkdownTextContent extends StatelessWidget {
  const MarkdownTextContent({
    super.key,
    required this.content,
    this.selectable = true,
    this.textStyle,
  });

  final String content;
  final bool selectable;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = MarkdownStyleSheet.fromTheme(theme);
    final hairline = 1 / MediaQuery.devicePixelRatioOf(context);

    return MarkdownBody(
      data: content,
      selectable: selectable,
      softLineBreak: true,
      styleSheet: base.copyWith(
        a: base.a?.copyWith(color: scheme.primary),
        p: textStyle ?? base.p,
        pPadding: EdgeInsets.zero,
        h1Padding: EdgeInsets.zero,
        h2Padding: EdgeInsets.zero,
        h3Padding: EdgeInsets.zero,
        h4Padding: EdgeInsets.zero,
        h5Padding: EdgeInsets.zero,
        h6Padding: EdgeInsets.zero,
        blockSpacing: 6,
        code: base.code?.copyWith(fontFamily: 'monospace'),
        codeblockDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        codeblockPadding: const EdgeInsets.all(8),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: scheme.outline, width: hairline),
          ),
        ),
      ),
      onTapLink: (text, href, title) => _openLink(href, text),
      imageBuilder: (uri, title, alt) => _buildImage(context, uri, alt),
      checkboxBuilder: (checked) => Icon(
        checked ? Icons.check_box : Icons.check_box_outline_blank,
        size: 20,
        color: checked ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
  }

  /// Opens valid links externally and reports the ones that are not. A copy
  /// action would need the Material fork's `SnackBarAction`; the overlay here
  /// is Flutter Material, so the raw target is only named, not copied.
  Future<void> _openLink(String? href, String text) async {
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null || !uri.hasScheme) {
      showSnackBar('brokenLink'.tr(args: [href ?? text]));
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildImage(BuildContext context, Uri uri, String? alt) {
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return _MarkdownImageFallback(alt: alt ?? 'Image unavailable');
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: Image.network(
          uri.toString(),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              _MarkdownImageFallback(alt: alt ?? 'Image unavailable'),
        ),
      ),
    );
  }
}

class _MarkdownImageFallback extends StatelessWidget {
  const _MarkdownImageFallback({required this.alt});

  final String alt;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.broken_image_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 6),
      Text(alt),
    ],
  );
}
