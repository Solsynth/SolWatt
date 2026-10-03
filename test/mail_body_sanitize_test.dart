import 'package:flutter_test/flutter_test.dart';

import 'package:solwatt/mail/mail_screen.dart';

void main() {
  group('sanitizeEmailHtml', () {
    test('removes script bodies', () {
      final result = sanitizeEmailHtml(
        '<p>hello</p><script>fetch("https://evil.test")</script><p>bye</p>',
      );
      expect(result, isNot(contains('script')));
      expect(result, isNot(contains('evil.test')));
      expect(result, contains('<p>hello</p>'));
      expect(result, contains('<p>bye</p>'));
    });

    test('removes unclosed and self-closing script tags', () {
      expect(
        sanitizeEmailHtml('<p>a</p><script src="x.js">'),
        isNot(contains('script')),
      );
      expect(
        sanitizeEmailHtml('<p>a</p><script src="x.js" />'),
        isNot(contains('script')),
      );
    });

    test('removes inline event handlers in all quoting styles', () {
      final result = sanitizeEmailHtml(
        '<img src="a.png" onerror="steal()">'
        "<body onload='boot()'>"
        '<a href="#" onclick=go()>x</a>',
      );
      expect(result, isNot(contains('onerror')));
      expect(result, isNot(contains('onload')));
      expect(result, isNot(contains('onclick')));
      expect(result, contains('<img src="a.png"'));
      expect(result, contains('href="#"'));
    });

    test('neutralises javascript: hrefs without leaving stray quotes', () {
      final result = sanitizeEmailHtml(
        """<a href="javascript:alert('x')">x</a>""",
      );
      expect(result, isNot(contains('javascript:')));
      expect(result, '<a href="about:blank#blocked">x</a>');
    });

    test('neutralises unquoted javascript: urls', () {
      final result = sanitizeEmailHtml('<a href=javascript:alert(1)>x</a>');
      expect(result, isNot(contains('javascript:')));
    });

    test('removes embedded objects', () {
      final result = sanitizeEmailHtml(
        '<p>a</p><iframe src="https://evil.test"></iframe>'
        '<object data="x"></object><embed src="y">',
      );
      expect(result, isNot(contains('iframe')));
      expect(result, isNot(contains('object')));
      expect(result, isNot(contains('embed')));
      expect(result, contains('<p>a</p>'));
    });

    test('removes target attributes so every link stays in one frame', () {
      final result = sanitizeEmailHtml(
        '<a href="https://example.com/a" target="_blank">a</a>'
        "<a href='https://example.com/b' TARGET='_blank'>b</a>"
        '<a href="https://example.com/c" target=_top>c</a>'
        '<a title="1 > 2" href="https://example.com/d" target="_blank">d</a>'
        '<base target="_blank">',
      );
      expect(result, isNot(contains('target')));
      expect(result, contains('<a href="https://example.com/a">a</a>'));
      expect(result, contains("<a href='https://example.com/b'>b</a>"));
      expect(result, contains('<a href="https://example.com/c">c</a>'));
      expect(result, contains('<a title="1 > 2" href="https://example.com/d">d</a>'));
    });

    test('leaves attributes and urls that merely spell target alone', () {
      const body =
          '<div data-target="panel">'
          '<a href="https://example.com/?target=panel">x</a>'
          '</div>';
      expect(sanitizeEmailHtml(body), body);
    });

    test('keeps ordinary message markup and links intact', () {
      const body =
          '<div style="color:red"><p>Hi <b>there</b></p>'
          '<a href="https://example.com/a?b=1&c=2">link</a>'
          '<img src="https://cdn.test/a.png" alt="pic"></div>';
      expect(sanitizeEmailHtml(body), body);
    });
  });
}
