import 'dart:js_interop';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:web/web.dart' as web;

/// The `@font-face` rules the reading pane's stylesheet opens with, taken from
/// Google Fonts over the app's own asset path.
///
/// A browser frame reads neither the app's asset bundle nor a custom scheme, so
/// the bundled faces are unreachable there and [family] is fetched from the
/// same source the family already comes from. A family Google Fonts does not
/// carry, or a reader that is offline, leaves the stylesheet's own fallback
/// stack in place.
String emailBodyFontFaces(String family) {
  final name = family.trim().replaceAll(' ', '+');
  // The trailing newline separates the rule from the stylesheet that follows.
  return "@import url('https://fonts.googleapis.com/css2"
      "?family=$name:ital,wght@0,400;0,700;1,400&display=swap');\n";
}

/// Extra `<head>` content the frame needs before the message's own markup.
///
/// The browser plugin cannot report a navigation back to the app — it does not
/// implement `shouldOverrideUrlLoading` — so the document opens every link in a
/// new tab itself, which is where a sender's link belongs. Without the base the
/// tap would replace the message with the linked page, scroll position and all.
String emailBodyDocumentHead() => '<base target="_blank">';

/// Browsers load the document from [emailBodyDocumentUrl]: a `data:` URL frame
/// has an opaque origin, so the plugin's injected scripts could neither read the
/// scroll position nor call into the document.
InAppWebViewInitialData? emailBodyInlineDocument(String html) => null;

/// The `blob:` URL of a frame holding [html].
///
/// The frame inherits this app's origin from the blob, which is what lets the
/// plugin reach into the document: `scrollHeight`, the scroll listener it
/// installs, and this app's own `window.scrollTo`. Callers own the URL and hand
/// it to [releaseEmailBodyDocumentUrl] when the message goes away.
String? emailBodyDocumentUrl(String html) {
  final blob = web.Blob(
    (<JSAny>[html.toJS]).toJS,
    // The charset is part of the type: a blob response carries no other hint,
    // and `text/html` without one decodes as windows-1252, mangling any message
    // that is not Latin-1.
    web.BlobPropertyBag(type: 'text/html;charset=utf-8'),
  );
  return web.URL.createObjectURL(blob);
}

/// Revokes a URL from [emailBodyDocumentUrl], freeing the document behind it.
void releaseEmailBodyDocumentUrl(String? url) {
  if (url != null) web.URL.revokeObjectURL(url);
}
