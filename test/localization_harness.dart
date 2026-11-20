/// Loads the shipped English bundle into easy_localization's singleton before
/// a widget test pumps.
///
/// Widgets call `'key'.tr()` without a context, which resolves through
/// `Localization.instance`. Pumping an `EasyLocalization` widget instead would
/// load the bundle asynchronously, so the first frames would render raw keys
/// and any `find.byTooltip`/`find.text` in the test would miss.
library;

import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/widgets.dart';

/// Reads `assets/i18n/en-US.json` and installs it as the active translation.
void loadTestLocalization() {
  final raw = File('assets/i18n/en-US.json').readAsStringSync();
  final bundle = json.decode(raw) as Map<String, dynamic>;
  Localization.load(
    const Locale('en', 'US'),
    translations: Translations(bundle),
    fallbackTranslations: Translations(bundle),
    useFallbackTranslationsForEmptyResources: true,
  );
}
