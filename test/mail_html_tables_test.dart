import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:solar_network_foundation/solar_network_foundation.dart';

import 'package:solwatt/workspace/editor/html_tables.dart';
import 'package:solwatt/workspace/editor/solar_editor.dart';

void main() {
  test('flattens table sections so row positions stay continuous', () {
    const html =
        '<table>'
        '<thead><tr><th>H1</th><th>H2</th></tr></thead>'
        '<tbody><tr><td>a</td><td>b</td></tr></tbody>'
        '</table>';

    final body = html_parser.parse(normalizeHtmlTables(html)).body!;
    final table = body.querySelector('table')!;
    expect(table.querySelectorAll('thead'), isEmpty);
    expect(table.querySelectorAll('tbody'), hasLength(1));
    expect(table.querySelectorAll('tr'), hasLength(2));
    expect(table.querySelectorAll('th'), hasLength(2));
    expect(table.querySelectorAll('td'), hasLength(2));
  });

  test('pads ragged rows and expands colspan', () {
    const html =
        '<table><tbody>'
        '<tr><td colspan="2">a</td></tr>'
        '<tr><td>b</td></tr>'
        '</tbody></table>';

    final body = html_parser.parse(normalizeHtmlTables(html)).body!;
    final rows = body.querySelectorAll('tr');
    expect(rows, hasLength(2));
    expect(rows[0].children, hasLength(2));
    expect(rows[1].children, hasLength(2));
    expect(rows[0].children.first.attributes, isNot(contains('colspan')));

    // The decoder needs a cell at every coordinate, and the encoder walks
    // those coordinates.
    final document = solarHTMLToDocument(normalizeHtmlTables(html));
    final markdown = solarDocumentToMarkdown(document);
    expect(markdown, contains('a'));
    expect(markdown, contains('b'));
  });

  test('keeps every tbody row when a table has several sections', () {
    const html =
        '<table>'
        '<tbody><tr><td>a</td><td>b</td></tr></tbody>'
        '<tbody><tr><td>c</td><td>d</td></tr></tbody>'
        '</table>';

    final body = html_parser.parse(normalizeHtmlTables(html)).body!;
    expect(body.querySelectorAll('tr'), hasLength(2));
    expect(body.querySelectorAll('td'), hasLength(4));

    final markdown = solarDocumentToMarkdown(
      solarHTMLToDocument(normalizeHtmlTables(html)),
    );
    expect(markdown, contains('a'));
    expect(markdown, contains('d'));
  });

  test('keeps the text of a table that has no rows', () {
    final normalized = normalizeHtmlTables('<table>just text</table>');
    final body = html_parser.parse(normalized).body!;
    expect(body.querySelectorAll('table'), isEmpty);
    expect(body.text, contains('just text'));
  });

  test('leaves markup outside tables alone', () {
    const html =
        '<p>Hello <strong>there</strong></p>'
        '<table><tbody><tr><td>a</td></tr></tbody></table>'
        '<p>Bye</p>';
    final body = html_parser.parse(normalizeHtmlTables(html)).body!;
    expect(body.querySelector('strong')?.text, 'there');
    expect(body.children.where((e) => e.localName == 'p'), hasLength(2));
  });

  testWidgets('the composer loads a thead/tbody message without throwing', (
    tester,
  ) async {
    final controller = createSolarEditor();
    addTearDown(controller.dispose);

    // Replies arrive wrapped in a quote, which is how the reported stack
    // reached the table encoder.
    const html =
        '<p>See below</p><blockquote>'
        '<table>'
        '<thead><tr><th>Plan</th><th>Price</th></tr></thead>'
        '<tbody><tr><td>Pro</td><td>10</td></tr></tbody>'
        '</table>'
        '</blockquote>';

    expect(() => controller.setHTML(html), returnsNormally);
    expect(controller.markdown, contains('Pro'));
    expect(controller.markdown, contains('10'));
  });
}
