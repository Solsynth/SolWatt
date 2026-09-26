import 'package:flutter_test/flutter_test.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/mail/mail_screen.dart';
import 'package:solwatt/network.dart';

EmailBodyScroll _sample(double y, double? maxY) =>
    EmailBodyScroll(y: y, maxY: maxY);

void main() {
  group('EmailBodyScroll', () {
    test('a body that already fits counts as being at the bottom', () {
      expect(_sample(0, 0).atBottom, isTrue);
    });

    test('a long body is not at the bottom at the top', () {
      expect(_sample(0, 900).atBottom, isFalse);
    });

    test('resting a few pixels short of the end still counts', () {
      expect(_sample(896, 900).atBottom, isTrue);
    });

    test('an unmeasured extent is not at the bottom', () {
      expect(_sample(500, null).atBottom, isFalse);
    });
  });

  group('BodyFooterRevealController', () {
    test('starts hidden', () {
      expect(BodyFooterRevealController().visible, isFalse);
    });

    test('reveals once the reader scrolls to the end', () {
      final footer = BodyFooterRevealController();
      expect(footer.update(_sample(0, 900)), isFalse);
      expect(footer.update(_sample(500, 900)), isFalse);
      expect(footer.update(_sample(900, 900)), isTrue);
      expect(footer.visible, isTrue);
      // Stayed at the end: no further change.
      expect(footer.update(_sample(900, 900)), isFalse);
    });

    test('reveals immediately when the message already fits', () {
      final footer = BodyFooterRevealController();
      expect(footer.update(_sample(0, 0)), isTrue);
      expect(footer.visible, isTrue);
    });

    test('hides again once scrolled back up past the threshold', () {
      final footer = BodyFooterRevealController();
      footer.update(_sample(900, 900));
      expect(footer.visible, isTrue);
      expect(footer.update(_sample(890, 900)), isFalse);
      expect(footer.update(_sample(860, 900)), isTrue);
      expect(footer.visible, isFalse);
    });

    test('a clamp back to the end does not re-reveal the footer', () {
      final footer = BodyFooterRevealController();
      footer.update(_sample(900, 900));
      footer.update(_sample(860, 900)); // user scrolls up -> hidden
      expect(footer.visible, isFalse);
      // Hiding the footer grows the body, so WebKit clamps the offset back to
      // the (new) end. That is not the reader arriving at the bottom.
      expect(footer.update(_sample(780, 780)), isFalse);
      expect(footer.visible, isFalse);
      // Arriving at the end by scrolling down reveals it again.
      expect(footer.update(_sample(800, 900)), isFalse);
      expect(footer.update(_sample(900, 900)), isTrue);
      expect(footer.visible, isTrue);
    });

    test('trackpad jitter at the end does not flap the footer', () {
      final footer = BodyFooterRevealController();
      footer.update(_sample(900, 900));
      for (final y in [898.0, 900.0, 898.0, 900.0]) {
        expect(footer.update(_sample(y, 900)), isFalse);
      }
      expect(footer.visible, isTrue);
    });

    test('adoptOrigin absorbs a clamp jump without changing visibility', () {
      final footer = BodyFooterRevealController()..update(_sample(900, 900));
      expect(footer.visible, isTrue);
      // The pane resized; the offset lands somewhere new. Not reader input.
      footer.adoptOrigin(400);
      expect(footer.visible, isTrue);
      // A small step from the new origin is not a 500px jump upwards.
      expect(footer.update(_sample(390, 900)), isFalse);
      expect(footer.visible, isTrue);
    });

    test('reset hides the footer for the next message', () {
      final footer = BodyFooterRevealController()..update(_sample(900, 900));
      expect(footer.visible, isTrue);
      footer.reset();
      expect(footer.visible, isFalse);
      // A fresh document starts at the top of a long body: still hidden.
      expect(footer.update(_sample(0, 900)), isFalse);
      expect(footer.visible, isFalse);
    });
  });

  group('emailHasFooterContent', () {
    MailEmail email({
      List<SnCloudFileReference> attachments = const [],
      String? deliveryStatus,
      bool isDraft = false,
    }) => MailEmail(
      id: 'e-1',
      mailboxId: 'mb-1',
      subject: 'Subject',
      body: 'Body',
      isDraft: isDraft,
      attachments: attachments,
      deliveryStatus: deliveryStatus,
    );

    test('a plain incoming message has no footer content', () {
      expect(emailHasFooterContent(email()), isFalse);
    });

    test('attachments warrant the footer', () {
      expect(
        emailHasFooterContent(
          email(attachments: const [SnCloudFileReference(id: 'f-1')]),
        ),
        isTrue,
      );
    });

    test('delivery state on a sent message warrants the footer', () {
      expect(
        emailHasFooterContent(email(deliveryStatus: 'delivered')),
        isTrue,
      );
    });

    test('drafts never show the delivery footer', () {
      expect(
        emailHasFooterContent(email(deliveryStatus: 'failed', isDraft: true)),
        isFalse,
      );
    });
  });
}
