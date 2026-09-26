import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as mui;

import 'package:solwatt/theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('fork theme mirrors the app theme ($brightness)', () {
      final app = createSolWattTheme(brightness);
      final fork = createSolWattForkTheme(app);

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

      // Colors, icons, dividers and density follow the app theme too.
      expect(fork.brightness, brightness);
      expect(fork.colorScheme.surfaceContainer, app.colorScheme.surface);
      expect(fork.colorScheme.primary, app.colorScheme.primary);
      expect(fork.iconTheme.weight, app.iconTheme.weight);
      expect(fork.iconTheme.opticalSize, app.iconTheme.opticalSize);
      expect(fork.dividerTheme.color, app.colorScheme.outlineVariant);
      expect(fork.visualDensity.horizontal, app.visualDensity.horizontal);
      expect(fork.visualDensity.vertical, app.visualDensity.vertical);
    });
  }

  test('fork theme keeps a fork typography scale, not the app subclass', () {
    final fork = createSolWattForkTheme(createSolWattTheme(Brightness.light));
    // The two TextTheme classes are unrelated; this only compiles because the
    // fork reuses Flutter's TextStyle.
    expect(fork.textTheme, isA<mui.TextTheme>());
    expect(fork.textTheme.labelLarge?.fontFamily, SolWattFonts.sans);
  });
}
