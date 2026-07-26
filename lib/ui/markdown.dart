import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:url_launcher/url_launcher.dart';

/// Island-inspired Markdown renderer for user-authored task content.
///
/// This keeps the portable presentation pieces from Island's renderer while
/// leaving out Island-specific mentions, stickers, and private URL handling.
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
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final config = isDark
        ? MarkdownConfig.darkConfig
        : MarkdownConfig.defaultConfig;

    return MarkdownBlock(
      data: content,
      selectable: selectable,
      config: config.copy(
        configs: [
          PConfig(textStyle: textStyle ?? theme.textTheme.bodyMedium!),
          PreConfig(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          TableConfig(
            wrapper: (child) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: child,
            ),
          ),
          LinkConfig(
            style: TextStyle(color: scheme.primary),
            onTap: (href) async {
              final uri = Uri.tryParse(href);
              if (uri == null) return;
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
          // Handles both ![alt](url) and GitHub's raw <img src="url"> tags.
          // The package's default image node assumes width/height are numeric;
          // GitHub content can use values such as "100%".
          ImgConfig(
            builder: (url, attributes) {
              final width = double.tryParse(attributes['width'] ?? '');
              final height = double.tryParse(attributes['height'] ?? '');
              final isNetworkImage =
                  url.startsWith('https://') || url.startsWith('http://');
              if (!isNetworkImage) {
                return _MarkdownImageFallback(
                  alt: attributes['alt'] ?? 'Image unavailable',
                );
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: Image.network(
                    url,
                    width: width,
                    height: height,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => _MarkdownImageFallback(
                      alt: attributes['alt'] ?? 'Image unavailable',
                    ),
                  ),
                ),
              );
            },
          ),
          // markdown_widget's default checklist uses a negative top padding
          // for text shorter than 24px, which Flutter rejects at layout time.
          CheckBoxConfig(
            builder: (checked) => Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: checked ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
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
