import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as mui;

import 'package:solwatt/theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('fork theme mirrors the app theme ($brightness)', () {
      for (final accent in kAccentColorOptions) {
        final reason = 'accent $accent in $brightness';
        final app = createSolWattTheme(brightness, seedColor: accent);
        final fork = createSolWattForkTheme(app, accent);

        // Typography carries over slot by slot: the fork chrome reads its own
        // text theme, and nothing in it may fall back to the platform font.
        expect(fork.textTheme.bodyMedium, app.textTheme.bodyMedium);
        expect(fork.textTheme.titleMedium, app.textTheme.titleMedium);
        expect(fork.textTheme.headlineSmall, app.textTheme.headlineSmall);
        expect(fork.textTheme.bodyMedium?.fontFamily, SolWattFonts.sans);
        expect(fork.textTheme.titleMedium?.fontFamily, SolWattFonts.sans);
        expect(
          fork.textTheme.headlineSmall?.fontWeight,
          app.textTheme.headlineSmall?.fontWeight,
        );
        // Same for the styles that are not pulled out of a slot.
        expect(fork.textTheme.bodySmall?.fontFamily, SolWattFonts.sans);

        // Colors, icons, dividers and density follow the app theme too. The
        // two `ColorScheme` classes are unrelated types (the fork keeps its
        // own copy), so the tokens the fork chrome paints with are compared
        // one by one. Everything but `surfaceContainer` comes straight out of
        // the fork's `fromSeed`, which must stay in step with Flutter's — the
        // fork builds the whole drive page and the overlay chrome, so an
        // accent the fork scheme drops shows up as the default amber.
        expect(fork.brightness, brightness);
        expect(
          fork.colorScheme.surfaceContainer,
          app.colorScheme.surface,
          reason: reason,
        );
        expect(fork.colorScheme.primary, app.colorScheme.primary, reason: reason);
        expect(
          fork.colorScheme.onPrimary,
          app.colorScheme.onPrimary,
          reason: reason,
        );
        expect(
          fork.colorScheme.primaryContainer,
          app.colorScheme.primaryContainer,
          reason: reason,
        );
        expect(
          fork.colorScheme.secondary,
          app.colorScheme.secondary,
          reason: reason,
        );
        expect(
          fork.colorScheme.tertiary,
          app.colorScheme.tertiary,
          reason: reason,
        );
        expect(fork.colorScheme.error, app.colorScheme.error, reason: reason);
        expect(fork.colorScheme.surface, app.colorScheme.surface, reason: reason);
        expect(
          fork.colorScheme.onSurface,
          app.colorScheme.onSurface,
          reason: reason,
        );
        expect(
          fork.colorScheme.onSurfaceVariant,
          app.colorScheme.onSurfaceVariant,
          reason: reason,
        );
        expect(
          fork.colorScheme.surfaceTint,
          app.colorScheme.surfaceTint,
          reason: reason,
        );
        expect(
          fork.colorScheme.surfaceContainerHigh,
          app.colorScheme.surfaceContainerHigh,
          reason: reason,
        );
        expect(
          fork.colorScheme.surfaceContainerHighest,
          app.colorScheme.surfaceContainerHighest,
          reason: reason,
        );
        expect(fork.colorScheme.outline, app.colorScheme.outline, reason: reason);
        expect(
          fork.colorScheme.outlineVariant,
          app.colorScheme.outlineVariant,
          reason: reason,
        );
        expect(
          fork.colorScheme.inverseSurface,
          app.colorScheme.inverseSurface,
          reason: reason,
        );
        expect(
          fork.colorScheme.onInverseSurface,
          app.colorScheme.onInverseSurface,
          reason: reason,
        );

        expect(fork.iconTheme.weight, app.iconTheme.weight);
        expect(fork.iconTheme.opticalSize, app.iconTheme.opticalSize);
        expect(fork.dividerTheme.color, app.colorScheme.outlineVariant);
        expect(fork.visualDensity.horizontal, app.visualDensity.horizontal);
        expect(fork.visualDensity.vertical, app.visualDensity.vertical);
      }
    });
  }

  test('the accent options seed distinct fork schemes', () {
    // Guards the loop above against a vacuous pass: if two accents produced
    // the same scheme, "the fork follows the accent" would be untestable.
    final primaries = <int>{
      for (final accent in kAccentColorOptions)
        createSolWattForkTheme(
          createSolWattTheme(Brightness.light, seedColor: accent),
          accent,
        ).colorScheme.primary.toARGB32(),
    };
    expect(primaries, hasLength(kAccentColorOptions.length));
  });

  test('fork theme keeps a fork typography scale, not the app subclass', () {
    final fork = createSolWattForkTheme(
      createSolWattTheme(Brightness.light),
      kSolWattSeedColor,
    );
    // The two TextTheme classes are unrelated; this only compiles because the
    // fork reuses Flutter's TextStyle.
    expect(fork.textTheme, isA<mui.TextTheme>());
    expect(fork.textTheme.labelLarge?.fontFamily, SolWattFonts.sans);
  });
}
