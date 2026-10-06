import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_ui/material_ui.dart' as mui;

import 'package:solwatt/main.dart';
import 'package:solwatt/shared/widgets/app_scaffold.dart';
import 'package:solwatt/theme.dart';

/// The fork chrome — the whole drive page plus every `island_ui_foundation`
/// overlay — paints from `mui.Theme`, not from Flutter's. Two things have to
/// hold or that chrome drifts away from the app: [AppOverlayHost] must provide
/// the fork theme as an ancestor of the *overlay* (snackbars are inserted as
/// sibling entries, so a theme inside the app entry never reaches them), and
/// the fork theme must be seeded from the user's accent.
///
/// Colors are asserted against the fork's own ladder for the accent the app
/// was launched with, not against hard-coded values, so the tests fail on a
/// wrong ancestor or a dropped accent rather than on a Material retune.
const _teal = Color(0xff0d9488);
const _rose = Color(0xffe11d48);

const _message = 'workspace is now active';
// The toast queue is a package-level singleton shared by every pump in this
// file, so each test posts its own message.
const _accentMessage = 'the accent changed';

Widget _harness({
  required GlobalKey<OverlayState> overlayKey,
  required Color accent,
}) {
  // The host carries the app's websocket indicator entry, so the tree needs a
  // scope even though nothing here reads a provider of its own.
  return ProviderScope(
    child: MaterialApp(
      theme: createSolWattTheme(Brightness.light, seedColor: accent),
      localizationsDelegates: mui.GlobalMaterialLocalizations.delegates,
      builder: (context, child) => AppOverlayHost(
        overlayKey: overlayKey,
        accentSeed: accent,
        child: child,
      ),
      home: const AppScaffold(body: SizedBox.shrink()),
    ),
  );
}

/// The scheme the fork chrome has to paint with: the fork's own ladder for the
/// accent the app was launched with. Deliberately *not* `createSolWattForkTheme`
/// — reading the expectation back out of the code under test would let a
/// dropped accent (or a wrong theme) satisfy its own assertion.
mui.ColorScheme _expectedScheme(Color accent) =>
    mui.ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.light);

/// The toast's message style, read off the rendered text: the fork content
/// builder paints it with the fork scheme's `onSurfaceVariant`.
Color? _toastMessageColor(WidgetTester tester, String message) =>
    tester.widget<Text>(find.text(message)).style?.color;

/// The page shell's surface is painted by the *fork* `Material` (that is what
/// `AppScaffold` builds), so this has to look for the fork's type. The shell's
/// own wrapper is the outermost one; the `Scaffold` inside paints a second,
/// transparent one.
Color _scaffoldSurface(WidgetTester tester) => tester
    .widgetList<mui.Material>(
      find.descendant(
        of: find.byType(AppScaffold),
        matching: find.byType(mui.Material),
      ),
    )
    .first
    .color!;

void main() {
  testWidgets('overlay chrome and the page shell read the accent-seeded fork '
      'theme', (tester) async {
    final overlayKey = GlobalKey<OverlayState>();
    IslandUIFoundation.configureOverlay(overlayKey);

    await tester.pumpWidget(_harness(overlayKey: overlayKey, accent: _teal));
    await tester.pump();

    // The file page's shell is a fork `Material` painted from the fork scheme.
    expect(_scaffoldSurface(tester), _expectedScheme(_teal).surface);

    showSnackBar(_message);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(_message), findsOneWidget);
    expect(
      _toastMessageColor(tester, _message),
      _expectedScheme(_teal).onSurfaceVariant,
    );
    // Non-vacuous: the fallback fork theme (no `mui.Theme` ancestor) resolves
    // this slot to the fork's own baseline color.
    expect(
      _toastMessageColor(tester, _message),
      isNot(mui.ThemeData.fallback().colorScheme.onSurfaceVariant),
    );
  });

  testWidgets('a mounted toast follows an accent change', (tester) async {
    // The two accents have to resolve differently, or the swap below would
    // pass without the toast following anything.
    expect(
      _expectedScheme(_rose).onSurfaceVariant,
      isNot(_expectedScheme(_teal).onSurfaceVariant),
    );
    final overlayKey = GlobalKey<OverlayState>();
    IslandUIFoundation.configureOverlay(overlayKey);

    await tester.pumpWidget(_harness(overlayKey: overlayKey, accent: _teal));
    await tester.pump();
    showSnackBar(_accentMessage);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      _toastMessageColor(tester, _accentMessage),
      _expectedScheme(_teal).onSurfaceVariant,
    );

    await tester.pumpWidget(_harness(overlayKey: overlayKey, accent: _rose));
    await tester.pump();

    expect(
      _toastMessageColor(tester, _accentMessage),
      _expectedScheme(_rose).onSurfaceVariant,
    );
    expect(_scaffoldSurface(tester), _expectedScheme(_rose).surface);
  });
}
