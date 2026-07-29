import 'package:solar_network_foundation/solar_network_foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// SolWatt's Markdown adapter.
///
/// The foundation package supplies the renderer; SolWatt only decides how
/// external links are opened.
class MarkdownTextContent extends SolarMarkdownContent {
  const MarkdownTextContent({
    super.key,
    required super.content,
    super.selectable = true,
    super.textStyle,
  }) : super(onLinkTap: _openExternalLink);

  static Future<void> _openExternalLink(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
