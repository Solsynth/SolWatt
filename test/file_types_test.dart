import 'package:flutter_test/flutter_test.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/utils/file_types.dart';

void main() {
  group('effectiveMimeType', () {
    test('a generic type yields to the filename', () {
      expect(
        effectiveMimeType(mimeType: 'application/octet-stream', name: 'a.jpg'),
        'image/jpeg',
      );
      expect(
        effectiveMimeType(mimeType: '', name: 'clip.mp4'),
        'video/mp4',
      );
      expect(
        effectiveMimeType(mimeType: 'binary/octet-stream', name: 'b.png'),
        'image/png',
      );
    });

    test('a declared type wins over the filename', () {
      expect(
        effectiveMimeType(mimeType: 'application/pdf', name: 'a.jpg'),
        'application/pdf',
      );
      expect(
        effectiveMimeType(mimeType: 'image/webp', name: 'a.jpg'),
        'image/webp',
      );
    });

    test('a text part named like a picture is a mislabelled picture', () {
      // Parts without a Content-Type land as text/plain while their filename
      // says what the bytes are.
      expect(
        effectiveMimeType(mimeType: 'text/plain', name: 'shot.JPG'),
        'image/jpeg',
      );
    });

    test('a text part keeps its type', () {
      expect(
        effectiveMimeType(mimeType: 'text/plain', name: 'notes.txt'),
        'text/plain',
      );
      expect(
        effectiveMimeType(mimeType: 'text/plain', name: 'readme'),
        'text/plain',
      );
    });

    test('unknown extensions keep the declared type', () {
      expect(
        effectiveMimeType(mimeType: 'application/octet-stream', name: 'x.bin'),
        'application/octet-stream',
      );
      expect(
        effectiveMimeType(mimeType: '', name: 'trailing.'),
        '',
      );
    });

    test('matching is case-insensitive', () {
      expect(mimeTypeForFilename('PHOTO.JPeG'), 'image/jpeg');
      expect(mimeTypeForFilename('photo'), isNull);
    });
  });

  group('file kinds', () {
    IDisplayableCloudFile file(String name, String mimeType) =>
        SnCloudFileReference(id: 'f-1', name: name, mimeType: mimeType);

    test('judge pictures and videos by type or filename', () {
      expect(isImageFile(file('photo.jpg', 'application/octet-stream')), isTrue);
      expect(isImageFile(file('photo.jpg', 'image/jpeg')), isTrue);
      expect(isImageFile(file('report.pdf', 'application/pdf')), isFalse);
      expect(isVideoFile(file('clip.MP4', '')), isTrue);
      expect(isVideoFile(file('report.pdf', 'application/pdf')), isFalse);
    });
  });
}
