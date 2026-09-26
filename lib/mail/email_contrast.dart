/// Contrast repair for message HTML that carries its colours inline.
///
/// A message without a stylesheet of its own inherits the reading pane's
/// colours, but whatever colours the sender wrote inline were picked against a
/// white page: a plain `color:#333` card header lands at 1.3:1 on a dark pane —
/// there, but unreadable. [withReadableEmailColors] rewrites exactly those
/// colours, keeping the sender's hue, spacing and markup.
///
/// Left alone:
/// * text that already has enough contrast,
/// * text on a background the sender painted themselves — that pair is theirs
///   to choose, and dark text on a light card is not a bug,
/// * anything under a painted background image, which cannot be measured,
/// * colours this file cannot parse, and messages that ship a stylesheet
///   (their colours come from rules this pass cannot evaluate),
/// * every message whose message palette already reads on the pane.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart' show Color;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// The contrast a message's own colour must reach to be left alone, and the
/// contrast a rewritten colour aims for.
///
/// WCAG asks for 4.5:1 on body text; a colour just under it is repaired all the
/// way to 7:1 rather than nudged to the threshold, so a repaired run does not
/// read as marginally darker than its neighbours.
const double kEmailMinimumContrast = 4.5;
const double kEmailTargetContrast = 7;

/// Rewrites the text colours in [html] that fall below [minimumContrast]
/// against the surface they actually sit on, aiming for [targetContrast].
///
/// [backdrop] is the colour behind the message: the pane it renders on, which
/// is what an element without a background of its own shows through to.
String withReadableEmailColors(
  String html, {
  required Color backdrop,
  double minimumContrast = kEmailMinimumContrast,
  double targetContrast = kEmailTargetContrast,
}) {
  final fragment = html_parser.parseFragment(html);
  var rewrote = false;

  void visit(dom.Element element, Color? backdrop) {
    final background = _resolveBackdrop(element, backdrop);
    // A null background means the pane's colour is unknown under this element
    // (a painted image, or an unreadable background): leave the colours there
    // exactly as the sender wrote them.
    final surface = switch (background) {
      _SolidBackdrop(:final color) => color,
      _InheritedBackdrop() => backdrop,
      _ImageBackdrop() => null,
    };

    if (surface != null) {
      final repainted = _repaint(
        element,
        surface,
        minimumContrast,
        targetContrast,
      );
      if (repainted != null) {
        rewrote = true;
        element.attributes['style'] = repainted.style;
        final attribute = repainted.attribute;
        if (attribute != null) element.attributes['color'] = attribute;
      }
    }

    for (final child in element.children) {
      visit(child, surface);
    }
  }

  for (final node in fragment.nodes) {
    if (node is dom.Element) visit(node, backdrop);
  }
  // Only a rewrite pays for re-serialising: an untouched message keeps the
  // sender's bytes, whatever the parser would have normalised.
  return rewrote ? fragment.outerHtml : html;
}

/// The contrast ratio between two opaque colours, per WCAG 2.
double emailContrastRatio(Color a, Color b) {
  final first = _relativeLuminance(a);
  final second = _relativeLuminance(b);
  final lighter = math.max(first, second);
  final darker = math.min(first, second);
  return (lighter + 0.05) / (darker + 0.05);
}

/// The colour to show [text] in so it reads on [background], or null when it
/// already reads well enough.
///
/// The replacement keeps the text's hue and moves it only as far as
/// [targetContrast] requires — toward white on a dark background, toward black
/// on a light one — so a lifted muted grey stays a grey rather than turning
/// white.
Color? readableEmailTextColor(
  Color text,
  Color background, {
  double minimumContrast = kEmailMinimumContrast,
  double targetContrast = kEmailTargetContrast,
}) {
  final solid = _over(text, background);
  if (emailContrastRatio(solid, background) >= minimumContrast) return null;
  final target = _relativeLuminance(background) < 0.18
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF000000);
  for (var step = 1; step <= _liftSteps; step++) {
    final candidate = Color.lerp(solid, target, step / _liftSteps)!;
    if (emailContrastRatio(candidate, background) >= targetContrast) {
      return candidate;
    }
  }
  return target;
}

/// Parses a CSS colour as it appears in a message: hex (3, 4, 6 or 8 digits),
/// `rgb()`/`rgba()`, the CSS 2.1 colour keywords, and the `transparent`
/// keyword. Returns null for anything else — named colours outside that set,
/// `currentColor`, `inherit`, `var(...)` — which the caller then leaves as
/// written.
Color? parseCssColor(String value) {
  final text = value.trim().toLowerCase();
  if (text.isEmpty) return null;
  if (text == 'transparent') return const Color(0x00000000);
  if (text.startsWith('#')) return _parseHex(text.substring(1));
  if (text.startsWith('rgb')) return _parseRgbFunction(text);
  return _keywordColors[text];
}

const int _liftSteps = 64;

/// The `color` value a `style` attribute declares, with the span it occupies so
/// a rewrite can splice it in place and leave every other declaration's bytes
/// untouched.
({String value, int start, int end})? _colorDeclaration(String style) {
  for (final match in _colorPropertyPattern.allMatches(style)) {
    if (_insideQuotes(style, match.start)) continue;
    final end = style.indexOf(';', match.end);
    return (
      value: style.substring(match.end, end < 0 ? style.length : end),
      start: match.end,
      end: end < 0 ? style.length : end,
    );
  }
  return null;
}

final _colorPropertyPattern = RegExp(r'(?:^|;)\s*color\s*:\s*');

/// Whether [index] sits inside a quoted value — a semicolon or `color:` inside
/// a `url("…")` is part of that value, not a declaration.
bool _insideQuotes(String style, int index) {
  var single = 0;
  var double = 0;
  for (var i = 0; i < index; i++) {
    if (style[i] == "'") single++;
    if (style[i] == '"') double++;
  }
  return single.isOdd || double.isOdd;
}

/// What an element says about the surface behind its text.
sealed class _Backdrop {
  const _Backdrop();
}

/// No background of its own: the parent's surface shows through.
final class _InheritedBackdrop extends _Backdrop {
  const _InheritedBackdrop();
}

/// A parsed background colour.
final class _SolidBackdrop extends _Backdrop {
  const _SolidBackdrop(this.color);

  final Color color;
}

/// A background this pass cannot measure (an image or gradient). Text inside is
/// left alone: on an image, contrast is a guess.
final class _ImageBackdrop extends _Backdrop {
  const _ImageBackdrop();
}

_Backdrop _resolveBackdrop(dom.Element element, Color? inherited) {
  final attributes = element.attributes;
  final style = attributes['style'];
  if (style != null) {
    final image = _declarationValue(style, 'background-image');
    if (image != null && !_isNone(image)) return const _ImageBackdrop();
    final shorthand = _declarationValue(style, 'background');
    if (shorthand != null) {
      if (_paintsImage(shorthand)) return const _ImageBackdrop();
      final color = _firstColorToken(shorthand);
      if (color != null) return _solid(color, inherited);
    }
    final backgroundColor = _declarationValue(style, 'background-color');
    if (backgroundColor != null) {
      final color = parseCssColor(backgroundColor);
      if (color == null) return const _InheritedBackdrop();
      return _solid(color, inherited);
    }
  }
  final bgcolor = attributes['bgcolor'];
  if (bgcolor != null) {
    final color = parseCssColor(bgcolor);
    if (color != null) return _solid(color, inherited);
  }
  return const _InheritedBackdrop();
}

/// A background colour is only measurable once it is opaque: anything
/// translucent is composited over [inherited], and left unmeasured when that is
/// unknown.
_Backdrop _solid(Color color, Color? inherited) {
  if (color.a >= 1) return _SolidBackdrop(color);
  if (inherited == null) return const _ImageBackdrop();
  return _SolidBackdrop(_over(color, inherited));
}

String? _declarationValue(String style, String property) {
  final pattern = RegExp('(?:^|;)\\s*$property\\s*:\\s*');
  for (final match in pattern.allMatches(style)) {
    if (_insideQuotes(style, match.start)) continue;
    final end = style.indexOf(';', match.end);
    return style.substring(match.end, end < 0 ? style.length : end);
  }
  return null;
}

bool _paintsImage(String value) {
  final text = value.toLowerCase();
  return text.contains('url(') || text.contains('gradient(');
}

bool _isNone(String value) => value.trim().toLowerCase().startsWith('none');

/// The first token of a `background` shorthand that parses as a colour, so
/// `#fff no-repeat` and `no-repeat #fff` both yield the colour.
Color? _firstColorToken(String shorthand) {
  for (final token in shorthand.split(RegExp(r'\s+'))) {
    final color = parseCssColor(token);
    if (color != null) return color;
  }
  return null;
}

/// The colour declaration or `<font color>` attribute of [element], revised for
/// [background], or null when it needs no revision.
({String style, String? attribute})? _repaint(
  dom.Element element,
  Color background,
  double minimumContrast,
  double targetContrast,
) {
  final style = element.attributes['style'] ?? '';
  final declaration = _colorDeclaration(style);
  final attribute = element.attributes['color'];
  final declared = declaration?.value ?? attribute;
  if (declared == null) return null;
  final color = parseCssColor(declared);
  if (color == null) return null;
  final readable = readableEmailTextColor(
    color,
    background,
    minimumContrast: minimumContrast,
    targetContrast: targetContrast,
  );
  if (readable == null) return null;
  final hex = _cssHex(readable);
  if (declaration != null) {
    return (
      style: style.replaceRange(declaration.start, declaration.end, hex),
      attribute: null,
    );
  }
  return (style: style, attribute: hex);
}

Color? _parseHex(String digits) {
  int? channel(String hex) => int.tryParse(hex, radix: 16);
  switch (digits.length) {
    case 3:
    case 4:
      final values = [
        for (final digit in digits.split(''))
          if (channel('$digit$digit') case final value?) value else -1,
      ];
      if (values.contains(-1)) return null;
      return Color.fromARGB(
        digits.length == 4 ? values[3] : 255,
        values[0],
        values[1],
        values[2],
      );
    case 6:
    case 8:
      final expanded = <int>[];
      for (var i = 0; i < digits.length; i += 2) {
        final value = channel(digits.substring(i, i + 2));
        if (value == null) return null;
        expanded.add(value);
      }
      return Color.fromARGB(
        digits.length == 8 ? expanded[3] : 255,
        expanded[0],
        expanded[1],
        expanded[2],
      );
  }
  return null;
}

Color? _parseRgbFunction(String value) {
  final open = value.indexOf('(');
  final close = value.lastIndexOf(')');
  if (open < 0 || close < open) return null;
  final parts = value
      .substring(open + 1, close)
      .split(RegExp(r'[,\s/]+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length < 3 || parts.length > 4) return null;
  final channels = [for (final part in parts.take(3)) _parseChannel(part)];
  if (channels.contains(null)) return null;
  final alpha = parts.length == 4 ? _parseAlpha(parts[3]) : 1;
  if (alpha == null) return null;
  return Color.fromARGB(
    (alpha * 255).round().clamp(0, 255),
    channels[0]!,
    channels[1]!,
    channels[2]!,
  );
}

int? _parseChannel(String value) {
  final text = value.trim();
  if (text.endsWith('%')) {
    final percent = double.tryParse(text.substring(0, text.length - 1));
    if (percent == null) return null;
    return (percent * 255 / 100).round().clamp(0, 255);
  }
  final number = double.tryParse(text);
  if (number == null) return null;
  return number.round().clamp(0, 255);
}

double? _parseAlpha(String value) {
  final text = value.trim();
  if (text.endsWith('%')) {
    final percent = double.tryParse(text.substring(0, text.length - 1));
    return percent == null ? null : (percent / 100).clamp(0, 1);
  }
  return double.tryParse(text)?.clamp(0, 1);
}

/// [foreground] composited over [background] with straight alpha.
Color _over(Color foreground, Color background) {
  final alpha = foreground.a;
  if (alpha >= 1) return foreground;
  double blend(double front, double back) => front * alpha + back * (1 - alpha);
  return Color.from(
    alpha: 1,
    red: blend(foreground.r, background.r),
    green: blend(foreground.g, background.g),
    blue: blend(foreground.b, background.b),
  );
}

double _relativeLuminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

String _cssHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}

/// The CSS 2.1 colour keywords, which is what hand-written messages use.
const Map<String, Color> _keywordColors = {
  'black': Color(0xFF000000),
  'silver': Color(0xFFC0C0C0),
  'gray': Color(0xFF808080),
  'grey': Color(0xFF808080),
  'white': Color(0xFFFFFFFF),
  'maroon': Color(0xFF800000),
  'red': Color(0xFFFF0000),
  'purple': Color(0xFF800080),
  'fuchsia': Color(0xFFFF00FF),
  'magenta': Color(0xFFFF00FF),
  'green': Color(0xFF008000),
  'lime': Color(0xFF00FF00),
  'olive': Color(0xFF808000),
  'yellow': Color(0xFFFFFF00),
  'navy': Color(0xFF000080),
  'blue': Color(0xFF0000FF),
  'teal': Color(0xFF008080),
  'aqua': Color(0xFF00FFFF),
  'cyan': Color(0xFF00FFFF),
  'orange': Color(0xFFFFA500),
};
