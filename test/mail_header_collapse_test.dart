import 'package:flutter_test/flutter_test.dart';

import 'package:solwatt/mail/mail_screen.dart';

void main() {
  group('HeaderCollapseController', () {
    test('starts expanded', () {
      expect(HeaderCollapseController().expanded, isTrue);
    });

    test('scrolling down past the threshold hides the header', () {
      final header = HeaderCollapseController();
      expect(header.update(10), isFalse);
      expect(header.update(20), isFalse);
      expect(header.update(30), isTrue);
      expect(header.expanded, isFalse);
      // Further scrolling down does not report a change.
      expect(header.update(200), isFalse);
    });

    test('scrolling back up past the threshold restores it', () {
      final header = HeaderCollapseController();
      header.update(100); // hide
      expect(header.expanded, isFalse);
      expect(header.update(90), isFalse);
      expect(header.update(70), isTrue);
      expect(header.expanded, isTrue);
    });

    test('a small reversal does not count towards the opposite threshold', () {
      final header = HeaderCollapseController()..update(100);
      expect(header.expanded, isFalse);
      // Down-then-up jitter: each reversal restarts the run.
      for (final y in [95, 100, 95, 100, 95]) {
        expect(header.update(y.toDouble()), isFalse);
      }
      expect(header.expanded, isFalse);
    });

    test('returning to the top always restores the header', () {
      final header = HeaderCollapseController()..update(500);
      expect(header.expanded, isFalse);
      // A step smaller than the threshold leaves it hidden...
      expect(header.update(490), isFalse);
      expect(header.expanded, isFalse);
      // ...and reaching the top restores it regardless.
      expect(header.update(0), isTrue);
      expect(header.expanded, isTrue);
    });

    test('an expanded header is not re-reported at the top', () {
      final header = HeaderCollapseController();
      expect(header.update(0), isFalse);
      expect(header.expanded, isTrue);
    });

    test('repeated identical offsets are ignored', () {
      final header = HeaderCollapseController();
      expect(header.update(100), isTrue);
      expect(header.update(100), isFalse);
      expect(header.update(100), isFalse);
    });

    test('adoptOrigin absorbs a clamp jump without flipping the header', () {
      final header = HeaderCollapseController()..update(200);
      expect(header.expanded, isFalse);
      // The pane resized, so WebKit clamped the offset back to the new end.
      header.adoptOrigin(40);
      expect(header.expanded, isFalse);
      // Continuing from the new origin is not an upward jump of 160px.
      expect(header.update(35), isFalse);
      expect(header.expanded, isFalse);
    });

    test('reset expands and forgets the scroll origin', () {
      final header = HeaderCollapseController()..update(1000);
      header.reset();
      expect(header.expanded, isTrue);
      // A fresh email starting mid-document must not flip the header.
      expect(header.update(1000), isFalse);
      expect(header.expanded, isTrue);
    });
  });
}
