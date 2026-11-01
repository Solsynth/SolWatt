import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solwatt/mail/mail_screen.dart';

import 'mail_phishing_fixtures.dart';

/// One pump per file: a second `pumpWidget` in the same isolate renders an
/// empty tree, so the reader route is exercised in its own test file.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('warns above the body when the reader opens a spoofed message', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      appHarness(
        thread: threadFixture(authentication: phishingVerdict()),
        prefs: prefs,
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    await tester.tap(find.text('Alice').first);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );

    // The safety indicator is part of the sender field in the open message.
    final safetyIcon = find.byType(MailSenderSafetyIcon);
    expect(safetyIcon, findsOneWidget);
    final tooltip = tester.widget<Tooltip>(
      find.descendant(of: safetyIcon, matching: find.byType(Tooltip)),
    );
    expect(tooltip.message, contains('senderSafetyPhishingTitle'.tr()));
    expect(tooltip.message, contains('senderSafetyPhishingHint'.tr()));
    expect(
      find.descendant(of: safetyIcon, matching: find.byIcon(Symbols.phishing)),
      findsOneWidget,
    );

    // It sits above the message body in the sender metadata.
    final body = find.byType(EmailPlainTextBody);
    expect(body, findsOneWidget);
    expect(tester.getTopLeft(safetyIcon).dy, lessThan(tester.getTopLeft(body).dy));
    expect(tester.takeException(), isNull);
  });
}
