/// Normalizes incoming HTML tables for the block editor's HTML decoder.
///
/// Mail bodies are whatever the sender's client produced, and tables are the
/// one block where the decoder's data model is stricter than HTML. The decoder
/// counts columns from the first row and rows from each table *section*,
/// starting over at zero for every `<thead>`/`<tbody>`/`<tfoot>`. A normal
/// email table with a header section and a body section therefore decodes with
/// duplicate `(row, column)` coordinates, and the cells the encoder later asks
/// for do not exist.
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Rewrites every table into the rectangular grid the editor's HTML decoder
/// can read.
///
/// The sections are flattened into one `<tbody>` so row positions stay
/// continuous; `colspan` is expanded and short rows are padded so every
/// `(row, column)` coordinate has a cell. A table that contains no rows or
/// cells is replaced by its text instead of being handed to the decoder as an
/// empty grid.
///
/// Only tables change; the rest of the document is serialized as the HTML
/// parser saw it.
String normalizeHtmlTables(String html) {
  final body = html_parser.parse(html).body;
  if (body == null) return html;

  // Innermost first: normalizing an outer table moves its cells (and any table
  // nested inside one) without detaching them, so the inner node is still in
  // the document when its turn comes.
  for (final table in body.querySelectorAll('table').toList().reversed) {
    _normalizeTable(table);
  }
  return body.innerHtml;
}

void _normalizeTable(dom.Element table) {
  final rows = <dom.Element>[];
  void collectRows(dom.Element section) {
    for (final child in section.children) {
      switch (child.localName) {
        case 'tr':
          rows.add(child);
        case 'thead' || 'tbody' || 'tfoot':
          collectRows(child);
      }
    }
  }

  collectRows(table);

  final captions = table.children
      .where((child) => child.localName == 'caption')
      .toList(growable: false);
  final width = rows.fold<int>(0, (widest, row) {
    final rowWidth = _cells(
      row,
    ).fold<int>(0, (sum, cell) => sum + _colSpan(cell));
    return rowWidth > widest ? rowWidth : widest;
  });

  if (width == 0) {
    // Nothing the grid can hold: keep the visible text rather than deleting a
    // caption or a table built out of non-table elements.
    _replaceWithText(table);
    return;
  }

  final tbody = dom.Element.tag('tbody');
  for (final row in rows) {
    final normalizedRow = dom.Element.tag('tr');
    for (final cell in _cells(row)) {
      final span = _colSpan(cell);
      cell.attributes.remove('colspan');
      cell.attributes.remove('rowspan');
      normalizedRow.append(cell);
      for (var extra = 1; extra < span; extra++) {
        normalizedRow.append(dom.Element.tag('td'));
      }
    }
    while (normalizedRow.children.length < width) {
      normalizedRow.append(dom.Element.tag('td'));
    }
    tbody.append(normalizedRow);
  }

  _preserveCaptions(table, captions);
  table.nodes
    ..clear()
    ..add(tbody);
}

List<dom.Element> _cells(dom.Element row) => row.children
    .where((child) => child.localName == 'td' || child.localName == 'th')
    .toList(growable: false);

int _colSpan(dom.Element cell) {
  final span = int.tryParse(cell.attributes['colspan'] ?? '');
  if (span == null || span < 1) return 1;
  // Layout tables sometimes carry absurd spans; a huge grid would only cost
  // memory once the decoder expands it.
  return span > 64 ? 64 : span;
}

void _preserveCaptions(dom.Element table, List<dom.Element> captions) {
  final parent = table.parent;
  if (parent == null) return;
  for (final caption in captions) {
    final text = caption.text.trim();
    if (text.isEmpty) continue;
    parent.insertBefore(dom.Element.tag('p')..text = text, table);
  }
}

void _replaceWithText(dom.Element table) {
  final text = table.text.trim();
  if (text.isEmpty) {
    table.remove();
  } else {
    table.replaceWith(dom.Element.tag('p')..text = text);
  }
}
