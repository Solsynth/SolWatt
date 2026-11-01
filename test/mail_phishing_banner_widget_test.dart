import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solwatt/mail/mail_screen.dart';

import 'mail_phishing_fixtures.dart';

/// One pump per file: the localization harness installs the delegate once, and
/// a second `pumpWidget` in the same isolate renders an empty tree.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('renders the verdict for forged, suspicious and clean senders', (
    tester,
  ) async {
    await tester.pumpWidget(
      localizationHarness(
        Column(
          children: [
            MailSenderSafetyBanner(
              email: emailFixture(authentication: phishingVerdict()),
            ),
            MailSenderSafetyBanner(
              email: emailFixture(
                authentication: {
                  'spf': 'fail',
                  'warnings': [
                    'Possible phishing: SPF verification failed',
                    'Some future verdict',
                  ],
                },
              ),
            ),
            MailSenderSafetyBanner(email: emailFixture()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Forged sender: escalated title, both warnings, and the hint in tooltip.
    expect(find.byIcon(Symbols.phishing), findsOneWidget);
    final phishingTooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byIcon(Symbols.phishing),
        matching: find.byType(Tooltip),
      ),
    );
    expect(phishingTooltip.message, contains('senderSafetyPhishingTitle'.tr()));
    expect(phishingTooltip.message, contains('senderSafetyPhishingHint'.tr()));
    expect(phishingTooltip.message, contains('senderWarningSpoofedSender'.tr()));
    expect(phishingTooltip.message, contains('senderWarningDmarcReject'.tr()));

    // Bare warnings: lower-intensity title, mapped line, and unrecognised string.
    expect(find.byIcon(Symbols.warning), findsOneWidget);
    final warningTooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byIcon(Symbols.warning),
        matching: find.byType(Tooltip),
      ),
    );
    expect(warningTooltip.message, contains('senderSafetySuspiciousTitle'.tr()));
    expect(warningTooltip.message, contains('senderWarningSpfFail'.tr()));
    expect(warningTooltip.message, contains('Some future verdict'));

    // The message without a verdict contributes no icons or warnings.
    expect(find.byType(Tooltip), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
