/// Platform pieces of the message reading pane's document.
///
/// Native platforms hand the markup to the web view inline and serve the app
/// font through a custom scheme; the browser loads the same markup from a
/// same-origin `blob:` URL and takes its font from Google Fonts. The two
/// variants are exported here so the reading pane reads as one code path.
library;

export 'email_body_platform.native.dart'
    if (dart.library.html) 'email_body_platform.web.dart';
