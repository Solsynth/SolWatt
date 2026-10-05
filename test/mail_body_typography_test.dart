import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:solwatt/mail/mail_screen.dart';
import 'package:solwatt/theme.dart';

String cssHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

void main() {
  group('isUnstyledEmailHtml', () {
    test('accepts bare markup without styling', () {
      expect(
        isUnstyledEmailHtml(
          '<html><body><p>Hello <b>there</b></p></body></html>',
        ),
        isTrue,
      );
    });

    test('rejects embedded style elements', () {
      expect(
        isUnstyledEmailHtml('<style>p { color: red }</style><p>hi</p>'),
        isFalse,
      );
      expect(
        isUnstyledEmailHtml('<STYLE>p { color: red }</STYLE><p>hi</p>'),
        isFalse,
      );
    });

    test('accepts inline styles — element tweaks keep their specificity', () {
      // Tracking pixels and one-off inline styles are ubiquitous in
      // otherwise-plain email; element-selector defaults cannot override
      // them, so they must not disqualify the message.
      expect(
        isUnstyledEmailHtml(
          '<p>hi</p><img src="t.png" style="display: none; width: 1px; height: 1px;">',
        ),
        isTrue,
      );
      expect(
        isUnstyledEmailHtml('<p style="color:red">hi</p>'),
        isTrue,
      );
    });

    test('rejects linked stylesheets', () {
      expect(
        isUnstyledEmailHtml(
          '<link rel="stylesheet" href="https://cdn.test/a.css"><p>hi</p>',
        ),
        isFalse,
      );
      expect(
        isUnstyledEmailHtml("<link rel='stylesheet' href='a.css'>"),
        isFalse,
      );
    });

    test('accepts styling-free fragments', () {
      expect(isUnstyledEmailHtml('<p>a</p><a href="https://x.test">b</a>'),
          isTrue);
    });
  });

  group('injectEmailTypography', () {
    const css = 'body { color: #111111 }';

    test('inserts into an existing head', () {
      final result = injectEmailTypography(
        '<html><head><title>t</title></head><body><p>x</p></body></html>',
        css,
      );
      expect(result, contains('<head><title>t</title><style>$css</style></head>'));
    });

    test('adds a head to a bare html document', () {
      final result = injectEmailTypography(
        '<html><body><p>x</p></body></html>',
        css,
      );
      expect(
        result,
        '<html><head><style>$css</style></head><body><p>x</p></body></html>',
      );
    });

    test('prepends to a bare fragment', () {
      final result = injectEmailTypography('<p>x</p>', css);
      expect(result, '<style>$css</style><p>x</p>');
    });

    test('keeps a doctype in place', () {
      final result = injectEmailTypography(
        '<!DOCTYPE html><html><body>x</body></html>',
        css,
      );
      expect(result, startsWith('<!DOCTYPE html><html><head><style>$css</style></head><body>x</body></html>'));
    });
  });

  group('withEmailTypography', () {
    const css = 'body { color: #111111 }';

    test('injects defaults into unstyled messages', () {
      final result = withEmailTypography('<p>hello</p>', css);
      expect(result, contains('<style>$css</style>'));
    });

    test('leaves styled messages untouched', () {
      const styled =
          '<style>p { color: red }</style><div><p>hi</p></div>';
      expect(withEmailTypography(styled, css), styled);
    });
  });

  group('emailTypographyCss', () {
    test('uses the app font and serves it from the appfont scheme', () {
      final css = emailTypographyCss(ThemeData(brightness: Brightness.light));
      expect(css, contains("font-family: 'Nunito'"));
      expect(css, contains("url('appfont://nunito-regular')"));
      expect(css, contains("url('appfont://nunito-bold')"));
      expect(css, contains("url('appfont://nunito-italic')"));
    });

    test('derives body color and background from the theme', () {
      final theme = ThemeData(brightness: Brightness.light);
      final css = emailTypographyCss(theme);
      expect(css, contains('color: ${cssHex(theme.colorScheme.onSurface)};'));
      expect(css, contains('background: transparent;'));
      expect(css, contains('color: ${cssHex(theme.colorScheme.primary)};'));
    });

    test('switches colors and color-scheme with dark mode', () {
      final dark = ThemeData(brightness: Brightness.dark);
      final darkCss = emailTypographyCss(dark);
      expect(darkCss, contains('color-scheme: dark'));
      expect(
        darkCss,
        contains('color: ${cssHex(dark.colorScheme.onSurface)};'),
      );
      expect(darkCss, isNot(contains('color-scheme: light')));
    });

    test('carries the theme heading weights', () {
      final theme = ThemeData(brightness: Brightness.light);
      final css = emailTypographyCss(theme);
      final h1 = theme.textTheme.headlineMedium!;
      expect(
        css,
        contains('font-weight: ${h1.fontWeight?.value ?? 700};'),
      );
    });

    test('mirrors the app theme in both brightnesses', () {
      final appLight = createSolWattTheme(Brightness.light);
      final appDark = createSolWattTheme(Brightness.dark);
      final light = emailTypographyCss(appLight);
      final dark = emailTypographyCss(appDark);
      expect(light, contains("font-family: 'Nunito'"));
      expect(light, contains('color-scheme: light'));
      expect(
        light,
        contains('color: ${cssHex(appLight.colorScheme.onSurface)};'),
      );
      expect(dark, contains('color-scheme: dark'));
      expect(
        dark,
        contains('color: ${cssHex(appDark.colorScheme.onSurface)};'),
      );
      expect(light, isNot(equals(dark)));
    });
  });

  group('emailOverflowCss', () {
    test('clips the document as the backstop', () {
      expect(
        emailOverflowCss(),
        contains('html, body { max-width: 100% !important; overflow-x: hidden !important; }'),
      );
    });

    test('scales oversized media and tables down', () {
      final css = emailOverflowCss();
      expect(
        css,
        contains(
          'img, video { max-width: 100% !important; height: auto !important; }',
        ),
      );
      expect(css, contains('table { max-width: 100% !important; }'));
    });

    test('gives long text and code somewhere to wrap', () {
      final css = emailOverflowCss();
      expect(css, contains('body { overflow-wrap: anywhere !important; }'));
      expect(css, contains('white-space: pre-wrap'));
    });
  });

  group('readerEmailDocument', () {
    final theme = createSolWattTheme(Brightness.light);

    test('declares the pane width as the viewport', () {
      final document = readerEmailDocument('<p>hello</p>', theme);
      expect(
        document,
        contains(
          '<meta name="viewport" content="width=device-width, initial-scale=1">',
        ),
      );
    });

    test('guards a styled message, which opts out of the typography', () {
      // A marketing layout of its own — a fixed-width table is exactly the
      // message the guard exists for, and it never gets the typography CSS.
      const styled =
          '<style>table { width: 700px }</style>'
          '<table><tr><td>wide</td></tr></table>';
      final document = readerEmailDocument(styled, theme);
      expect(document, contains('<style>${emailOverflowCss()}</style>'));
      expect(document, isNot(contains("font-family: 'Nunito'")));
    });

    test('guards an unstyled message alongside its typography', () {
      final document = readerEmailDocument('<p>hello</p>', theme);
      expect(document, contains('<style>${emailOverflowCss()}</style>'));
      expect(document, contains('<style>${emailTypographyCss(theme)}</style>'));
    });

    test('carries the guard and the viewport once each, inside the head', () {
      final document = readerEmailDocument(
        '<html><head><title>t</title></head><body><p>x</p></body></html>',
        theme,
      );
      expect('overflow-x: hidden'.allMatches(document).length, 1);
      expect('name="viewport"'.allMatches(document).length, 1);
      expect(document, contains('</style></head>'));
    });
  });
}
