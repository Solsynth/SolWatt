import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:solwatt/network.dart';

/// The `@font-face` block the reading pane's stylesheet opens with: the Nunito
/// faces bundled with the app, served into the frame through the `appfont://`
/// scheme (see `_HtmlBodyViewerState._serveAppFont`).
///
/// Native frames read neither the app's assets nor its fonts, so the bytes are
/// bridged over a custom scheme rather than referenced by URL.
String emailBodyFontFaces(String family) =>
    '''
@font-face { font-family: '$family'; src: url('appfont://nunito-regular') format('truetype'); font-weight: 400; font-style: normal; }
@font-face { font-family: '$family'; src: url('appfont://nunito-bold') format('truetype'); font-weight: 700; font-style: normal; }
@font-face { font-family: '$family'; src: url('appfont://nunito-italic') format('truetype'); font-weight: 400; font-style: italic; }
''';

/// Extra `<head>` content the frame needs before the message's own markup.
///
/// Native frames get the API base from [emailBodyInlineDocument] and report a
/// tapped link back through `shouldOverrideUrlLoading`, so they need none.
String emailBodyDocumentHead() => '';

/// The message document as the frame loads it natively: markup handed over
/// inline, with the API base that relative URLs in a message resolve against.
///
/// The pane renders the server's HTML body directly; the `.eml` endpoint is
/// only for downloading a serialized message, never for the reading view.
InAppWebViewInitialData? emailBodyInlineDocument(String html) =>
    InAppWebViewInitialData(
      data: html,
      mimeType: 'text/html',
      encoding: 'utf-8',
      baseUrl: WebUri(kSolarNetworkApiBase),
    );

/// Native frames are loaded from [emailBodyInlineDocument]: no URL to hand out.
String? emailBodyDocumentUrl(String html) => null;

/// Nothing to release — an inline document lives in the widget's memory.
void releaseEmailBodyDocumentUrl(String? url) {}
