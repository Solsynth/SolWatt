import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:solwatt/mail/email_contrast.dart';
import 'package:solwatt/mail/mail_screen.dart';
import 'package:solwatt/theme.dart';

/// The pane tone the reading view paints behind a transparent message body
/// (SolWatt's dark `surfaceContainerLow`).
const _pane = Color(0xFF221A14);

/// White, for the light-mode halves of the same cases.
const _paper = Color(0xFFFFFFFF);

/// The card header colour measured off the reported message: plain `#333`,
/// which is all but invisible on a dark pane.
const _invisibleOnDark = Color(0xFF333333);

void main() {
  group('emailContrastRatio', () {
    test('matches the WCAG anchors', () {
      expect(
        emailContrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.01),
      );
      expect(emailContrastRatio(_invisibleOnDark, _pane), lessThan(1.5));
    });
  });

  group('parseCssColor', () {
    test('reads hex in every length', () {
      expect(parseCssColor('#333'), const Color(0xFF333333));
      expect(parseCssColor(' #333333 '), const Color(0xFF333333));
      expect(parseCssColor('#3338'), const Color(0x88333333));
      expect(parseCssColor('#33333380'), const Color(0x80333333));
      // One digit per channel is not a CSS colour.
      expect(parseCssColor('#3'), isNull);
    });

    test('reads the rgb family, percentages included', () {
      expect(parseCssColor('rgb(51, 51, 51)'), const Color(0xFF333333));
      expect(parseCssColor('RGB(51 51 51)'), const Color(0xFF333333));
      expect(parseCssColor('rgba(51,51,51,0.5)'), const Color(0x80333333));
      expect(parseCssColor('rgb(20%, 20%, 20%)'), const Color(0xFF333333));
    });

    test('reads the keywords messages actually use', () {
      expect(parseCssColor('Gray'), const Color(0xFF808080));
      expect(parseCssColor('white'), const Color(0xFFFFFFFF));
      expect(parseCssColor('transparent'), const Color(0x00000000));
    });

    test('refuses what it cannot measure', () {
      for (final value in [
        'currentColor',
        'inherit',
        'var(--muted)',
        'rebeccapurple',
        '',
      ]) {
        expect(parseCssColor(value), isNull, reason: value);
      }
    });
  });

  group('readableEmailTextColor', () {
    test('lifts text that fails contrast, keeping it grey', () {
      final lifted = readableEmailTextColor(_invisibleOnDark, _pane);
      expect(lifted, isNotNull);
      expect(emailContrastRatio(lifted!, _pane), greaterThanOrEqualTo(7));
      // Neutral in, neutral out: a muted card header stays muted.
      expect((lifted.r - lifted.b).abs(), lessThan(0.02));
    });

    test('leaves a colour that already reads', () {
      // The reported message's secondary grey: 5.8:1 on the pane.
      expect(readableEmailTextColor(const Color(0xFF999999), _pane), isNull);
      expect(readableEmailTextColor(const Color(0xFFFFFFFF), _pane), isNull);
    });

    test('darkens light text on a light surface', () {
      final fixed = readableEmailTextColor(const Color(0xFFEEEEEE), _paper);
      expect(fixed, isNotNull);
      expect(emailContrastRatio(fixed!, _paper), greaterThanOrEqualTo(7));
      expect(fixed.r, lessThan(0.5));
    });

    test('keeps a colour that carries meaning', () {
      // A brown accent: lifting it must not wash the hue out.
      final lifted = readableEmailTextColor(const Color(0xFF6B3F1D), _pane);
      expect(lifted, isNotNull);
      expect(lifted!.r, greaterThan(lifted.g));
      expect(lifted.g, greaterThan(lifted.b));
    });
  });

  group('withReadableEmailColors', () {
    test('repairs the reported header and leaves its neighbours alone', () {
      const html =
          '<div style="font-family:Arial">'
          '<span style="color:#333;font-weight:bold">Haze</span>'
          '<span style="color:#999">2407286504@qq.com</span>'
          '</div>';
      final result = withReadableEmailColors(html, backdrop: _pane);

      expect(result, contains('font-weight:bold'));
      expect(result, contains('color:#999'));
      expect(result, isNot(contains('color:#333')));
      // The repaired colour reads on the pane it renders over.
      final match = RegExp(r'color:(#[0-9a-f]{6})').firstMatch(result)!;
      expect(
        emailContrastRatio(parseCssColor(match.group(1)!)!, _pane),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('returns the sender bytes untouched when nothing needs repair', () {
      const html = '<p style="color:#e0d6cf">fine</p><p>inherited</p>';
      expect(withReadableEmailColors(html, backdrop: _pane), same(html));
    });

    test('leaves colours the sender paired with their own background', () {
      const html =
          '<table style="background:#ffffff"><tr>'
          '<td style="color:#333333">dark on the sender white card</td>'
          '</tr></table>'
          '<table bgcolor="#111111"><tr>'
          '<td style="color:#eeeeee">light on the sender dark card</td>'
          '</tr></table>';
      expect(withReadableEmailColors(html, backdrop: _pane), same(html));
    });

    test('darkens text on a sender card that is too light for it', () {
      const html =
          '<div style="background:#f4f4f4">'
          '<span style="color:#e8e8e8">washed out</span></div>';
      final result = withReadableEmailColors(html, backdrop: _pane);
      expect(result, isNot(contains('color:#e8e8e8')));
    });

    test('reads a background given as a shorthand or an attribute', () {
      // Both shorthands put the text on the sender's white, so neither is
      // touched; the same text with no background is repaired.
      const carded =
          '<div style="background:#ffffff no-repeat">'
          '<span style="color:#333333">a</span></div>'
          '<div bgcolor="#ffffff"><span style="color:#333333">b</span></div>';
      expect(withReadableEmailColors(carded, backdrop: _pane), same(carded));

      const bare = '<div><span style="color:#333333">c</span></div>';
      expect(
        withReadableEmailColors(bare, backdrop: _pane),
        isNot(contains('color:#333333')),
      );
    });

    test(
      'reads a table layout: muted text on a card, plain text on the pane',
      () {
        // The shape GitHub-style mail uses: a white card cell and a cell that
        // renders straight on the pane.
        const html =
            '<table><tr>'
            '<td bgcolor="#f6f8fa" style="color:#57606a">card caption</td>'
            '<td style="color:#333333">pane caption</td>'
            '</tr></table>';
        final result = withReadableEmailColors(html, backdrop: _pane);
        // The card keeps the sender's muted grey; the pane cell is lifted.
        expect(result, contains('color:#57606a'));
        expect(result, isNot(contains('color:#333333')));
        expect(result, contains('bgcolor="#f6f8fa"'));
        expect(result, contains('card caption'));
        expect(result, contains('pane caption'));
      },
    );

    test('leaves text under a painted image alone', () {
      const html =
          '<div style="background-image:url(\'card.png\')">'
          '<span style="color:#333333">unmeasurable</span></div>'
          '<div style="background:linear-gradient(#fff,#eee)">'
          '<span style="color:#333333">also unmeasurable</span></div>';
      expect(withReadableEmailColors(html, backdrop: _pane), same(html));
    });

    test('repairs a legacy font colour', () {
      const html = '<font color="#333333" face="Arial">Haze</font>';
      final result = withReadableEmailColors(html, backdrop: _pane);
      expect(result, contains('face="Arial"'));
      expect(result, isNot(contains('#333333')));
      expect(result, contains('color="#'));
    });

    test('does not mistake a quoted url for a declaration', () {
      const html =
          '<p style="color:#333333;background-image:url(\'a;color:#fff.png\')">'
          'x</p>';
      final result = withReadableEmailColors(html, backdrop: _pane);
      expect(result, contains("url('a;color:#fff.png')"));
    });

    test('leaves colours it cannot parse as written', () {
      const html = '<span style="color:var(--muted)">x</span>';
      expect(withReadableEmailColors(html, backdrop: _pane), same(html));
    });

    test('reads rgb() and short hex too', () {
      const html =
          '<span style="color:rgb(51,51,51)">a</span>'
          '<span style="color:#333">b</span>';
      final result = withReadableEmailColors(html, backdrop: _pane);
      expect(result, isNot(contains('rgb(51,51,51)')));
      expect(result, isNot(contains('color:#333')));
    });
  });

  group('readerEmailDocument', () {
    /// The reported message: a card header in plain `#333` with no styling of
    /// its own, so it renders on the pane.
    const message =
        '<div><span style="color:#333333">Haze</span>'
        '<br><span style="color:#999999">2407286504@qq.com</span></div>';

    test('repairs an unstyled message on a dark pane', () {
      final document = readerEmailDocument(
        message,
        createSolWattTheme(Brightness.dark),
      );
      expect(document, contains('<style>'));
      expect(document, isNot(contains('color:#333333')));
      expect(document, contains('color:#999999'));

      final lifted = RegExp(r'color:(#[0-9a-f]{6})').firstMatch(document)!;
      final pane = createSolWattTheme(
        Brightness.dark,
      ).colorScheme.surfaceContainerLow;
      expect(
        emailContrastRatio(parseCssColor(lifted.group(1)!)!, pane),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('leaves the same message alone on a light pane', () {
      // A light pane is what the sender assumed in the first place.
      expect(
        readerEmailDocument(message, createSolWattTheme(Brightness.light)),
        contains('color:#333333'),
      );
    });

    test('leaves a message with its own stylesheet to its palette', () {
      const styled =
          '<style>span { color: #333333 }</style>'
          '<span style="color:#333333">Haze</span>';
      final document = readerEmailDocument(
        styled,
        createSolWattTheme(Brightness.dark),
      );
      expect(document, contains('color:#333333'));
      // The sender's own stylesheet, and nothing that re-palettes it: the
      // pane's own typography is the one part a styled message opts out of.
      expect(
        '<style>span { color: #333333 }</style>'.allMatches(document).length,
        1,
      );
      expect(document, isNot(contains("font-family: 'Nunito'")));
    });
  });
}
