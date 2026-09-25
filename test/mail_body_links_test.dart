import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:solwatt/mail/mail_screen.dart';

NavigationAction _action({
  required NavigationType? type,
  bool mainFrame = true,
  String url = 'https://example.com/article',
}) => NavigationAction(
  isForMainFrame: mainFrame,
  request: URLRequest(url: WebUri(url)),
  navigationType: type,
);

void main() {
  group('shouldOpenEmailLinkExternally', () {
    test('user-activated http link leaves the app', () {
      expect(
        shouldOpenEmailLinkExternally(
          _action(type: NavigationType.LINK_ACTIVATED),
        ),
        isTrue,
      );
    });

    test('mailto link leaves the app', () {
      expect(
        shouldOpenEmailLinkExternally(
          _action(
            type: NavigationType.LINK_ACTIVATED,
            url: 'mailto:someone@example.com',
          ),
        ),
        isTrue,
      );
    });

    test('initial document load stays in the pane', () {
      // The webview loads the message HTML with the API host as its base URL,
      // so the document navigation arrives as an http main-frame request.
      // Cancelling it left every message blank.
      expect(
        shouldOpenEmailLinkExternally(
          _action(type: NavigationType.OTHER, url: 'https://api.solian.app/'),
        ),
        isFalse,
      );
    });

    test('reload and back/forward stay in the pane', () {
      expect(
        shouldOpenEmailLinkExternally(
          _action(type: NavigationType.RELOAD),
        ),
        isFalse,
      );
      expect(
        shouldOpenEmailLinkExternally(
          _action(type: NavigationType.BACK_FORWARD),
        ),
        isFalse,
      );
    });

    test('missing navigation type stays in the pane', () {
      expect(
        shouldOpenEmailLinkExternally(_action(type: null)),
        isFalse,
      );
    });

    test('subframe link does not hijack the app', () {
      expect(
        shouldOpenEmailLinkExternally(
          _action(type: NavigationType.LINK_ACTIVATED, mainFrame: false),
        ),
        isFalse,
      );
    });

    test('non-web schemes are not launched', () {
      expect(
        shouldOpenEmailLinkExternally(
          _action(type: NavigationType.LINK_ACTIVATED, url: 'about:blank'),
        ),
        isFalse,
      );
    });
  });
}
