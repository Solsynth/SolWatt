import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

  group('emailPlainTextRuns', () {
    /// The invariant every run list upholds: the runs are the message, in
    /// order, with nothing added or lost.
    String joined(List<EmailTextRun> runs) =>
        runs.map((run) => run.text).join();

    test('splits copy around http and https links', () {
      const body = 'Read https://example.com/docs and http://a.test next';
      final runs = emailPlainTextRuns(body);
      expect(runs, [
        const EmailTextRun.text('Read '),
        EmailTextRun.link(
          text: 'https://example.com/docs',
          uri: Uri.parse('https://example.com/docs'),
        ),
        const EmailTextRun.text(' and '),
        EmailTextRun.link(
          text: 'http://a.test',
          uri: Uri.parse('http://a.test'),
        ),
        const EmailTextRun.text(' next'),
      ]);
      expect(joined(runs), body);
    });

    test('keeps sentence punctuation out of the link', () {
      const body = 'See (https://example.com/a?b=1&c=2), then https://x.test/y.';
      expect(emailPlainTextRuns(body), [
        const EmailTextRun.text('See ('),
        EmailTextRun.link(
          text: 'https://example.com/a?b=1&c=2',
          uri: Uri.parse('https://example.com/a?b=1&c=2'),
        ),
        const EmailTextRun.text('), then '),
        EmailTextRun.link(
          text: 'https://x.test/y',
          uri: Uri.parse('https://x.test/y'),
        ),
        const EmailTextRun.text('.'),
      ]);
    });

    test('keeps brackets the URL itself opens', () {
      // A URL that opens its own pair keeps the closing bracket; the one the
      // sentence adds stays in the copy.
      const body = 'https://en.wikipedia.org/wiki/Foo_(bar)';
      expect(
        emailPlainTextRuns(body).single,
        EmailTextRun.link(text: body, uri: Uri.parse(body)),
      );
      expect(emailPlainTextRuns('https://example.com/a(b)c)'), [
        EmailTextRun.link(
          text: 'https://example.com/a(b)c',
          uri: Uri.parse('https://example.com/a(b)c'),
        ),
        const EmailTextRun.text(')'),
      ]);
    });

    test('gives a bare www host an https scheme', () {
      final runs = emailPlainTextRuns('www.solian.app/docs works');
      expect(runs.first, EmailTextRun.link(
        text: 'www.solian.app/docs',
        uri: Uri.parse('https://www.solian.app/docs'),
      ));
      expect(joined(runs), 'www.solian.app/docs works');
    });

    test('turns bare addresses into mailto links', () {
      const body = 'ping Someone@Example.COM or a@b.test.';
      expect(emailPlainTextRuns(body), [
        const EmailTextRun.text('ping '),
        EmailTextRun.link(
          text: 'Someone@Example.COM',
          uri: Uri.parse('mailto:Someone@Example.COM'),
        ),
        const EmailTextRun.text(' or '),
        EmailTextRun.link(
          text: 'a@b.test',
          uri: Uri.parse('mailto:a@b.test'),
        ),
        const EmailTextRun.text('.'),
      ]);
    });

    test('leaves filenames, versions and plain copy alone', () {
      for (final body in [
        'notes.md and v1.2.3 are not links',
        'no links at all here',
      ]) {
        expect(emailPlainTextRuns(body), [EmailTextRun.text(body)]);
      }
    });

    test('leaves a scheme with no host as copy', () {
      expect(emailPlainTextRuns('https:// then more'), [
        const EmailTextRun.text('https:// then more'),
      ]);
    });

    test('an address inside a URL does not split it', () {
      const body = 'https://example.com/@ops/profile';
      expect(emailPlainTextRuns(body).single, EmailTextRun.link(
        text: body,
        uri: Uri.parse(body),
      ));
    });
  });

  group('EmailPlainTextBody', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    /// The rendered text of the body, as the spans the pane builds.
    List<TextSpan> spansOf(WidgetTester tester) {
      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      return selectable.textSpan!.children!.cast<TextSpan>();
    }

    Future<List<Uri>> pumpBody(
      WidgetTester tester,
      String body, {
      TextStyle? style,
    }) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        host(
          EmailPlainTextBody(
            body: body,
            attachments: const [],
            workspaceId: null,
            style: style,
            onOpenLink: (uri) async => opened.add(uri),
          ),
        ),
      );
      return opened;
    }

    /// Taps inside the glyphs of the body's first run, which the tap tests make
    /// the link itself: a [SelectableText] spans the whole pane, so tapping its
    /// centre can land past the end of a short body.
    Future<void> tapLink(WidgetTester tester) => tester.tapAt(
      tester.getTopLeft(find.byType(SelectableText)) + const Offset(8, 8),
    );

    testWidgets('highlights links in the theme colour and makes them tappable', (
      tester,
    ) async {
      await pumpBody(
        tester,
        'Read https://example.com/docs',
        // The pane hands the body its own metrics; a link only recolours them.
        style: const TextStyle(fontSize: 19, height: 1.6),
      );

      final context = tester.element(find.byType(EmailPlainTextBody));
      final primary = Theme.of(context).colorScheme.primary;
      final spans = spansOf(tester);
      expect(spans.map((span) => span.text), [
        'Read ',
        'https://example.com/docs',
      ]);

      expect(spans.first.recognizer, isNull);
      expect(spans.first.style, isNull);

      final link = spans.last;
      expect(link.recognizer, isA<TapGestureRecognizer>());
      expect(link.style!.color, primary);
      expect(link.style!.decoration, TextDecoration.underline);
      expect(link.style!.fontSize, 19);
      expect(link.style!.height, 1.6);
    });

    testWidgets('a tapped link opens its URL', (tester) async {
      final opened = await pumpBody(tester, 'https://example.com/docs');

      await tapLink(tester);
      await tester.pump();
      expect(opened, [Uri.parse('https://example.com/docs')]);
    });

    testWidgets('a tapped address opens a mailto target', (tester) async {
      final opened = await pumpBody(tester, 'ops@example.com');

      await tapLink(tester);
      await tester.pump();
      expect(opened, [Uri.parse('mailto:ops@example.com')]);
    });

    testWidgets('copy without links stays one selectable run', (tester) async {
      await tester.pumpWidget(
        host(
          const EmailPlainTextBody(
            body: 'plain message, nothing to open',
            attachments: [],
            workspaceId: null,
          ),
        ),
      );

      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(selectable.textSpan, isNull);
      expect(selectable.data, 'plain message, nothing to open');
    });
  });
}
