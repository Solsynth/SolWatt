import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/utils/file_types.dart';
import 'package:solwatt/core/widgets/content/cloud_file_attachment_list.dart';
import 'package:solwatt/core/widgets/content/cloud_file_lightbox.dart';
import 'package:solwatt/drive/widgets/cloud_files.dart'
    show CloudImageWidget, CloudVideoWidget;
import 'package:solwatt/ui/cloud_files.dart' show CloudFileChip;
import 'package:solwatt/drive/files/file_detail.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/realtime/realtime.dart';
import 'package:solwatt/websocket.dart';

const _mailboxWork = MailMailbox(
  id: 'mb-1',
  accountId: 'acc-1',
  workspaceId: 'ws-1',
  address: 'work@example.com',
  name: 'Work',
  isDefault: true,
  isVerified: true,
);

const _workspace = Workspace(
  id: 'ws-1',
  slug: 'ws-1',
  name: 'Test Workspace',
  isBundled: false,
);

// The reported case: a picture whose declared type says nothing, so only the
// filename identifies it.
const _photo = SnCloudFileReference(
  id: 'f-photo',
  name: 'photo.JPG',
  mimeType: 'application/octet-stream',
  size: 4096,
);

const _secondPhoto = SnCloudFileReference(
  id: 'f-photo-2',
  name: 'holiday.jpeg',
  mimeType: '',
  size: 8192,
);

const _document = SnCloudFileReference(
  id: 'f-doc',
  name: 'report.pdf',
  mimeType: 'application/pdf',
  size: 65536,
);

const _clip = SnCloudFileReference(
  id: 'f-clip',
  name: 'clip.mp4',
  mimeType: 'application/octet-stream',
  size: 1048576,
);

/// A text-only message with two pictures and a PDF attached.
final _email = MailEmail(
  id: 'e-1',
  mailboxId: 'mb-1',
  threadId: 't-1',
  subject: 'Trip photos',
  body: 'Photos from the trip, plus the report.',
  contentType: 'text/plain',
  isDraft: false,
  from: MailRecipient(address: 'alice@example.com', name: 'Alice'),
  isRead: true,
  createdAt: DateTime(2026, 9, 25, 10, 30),
  attachments: const [_photo, _secondPhoto, _document, _clip],
);

final _thread = MailThread(
  id: 't-1',
  mailboxId: 'mb-1',
  subject: 'Trip photos',
  messageCount: 1,
  unreadCount: 0,
  participants: const ['alice@example.com'],
  latestMessage: _email,
  latestAt: DateTime(2026, 9, 25, 10, 30),
);

/// The harness refuses every HTTP request, so an image the lightbox loads
/// reports one error per attempt. Drain them: what is under test is which
/// surface opened, not whether the picture decoded.
void _drainLoadErrors(WidgetTester tester) {
  while (tester.takeException() != null) {}
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  test('pictures qualify for the lightbox by type or by filename', () {
    expect(isImageFile(_photo), isTrue); // .JPG with a generic type
    expect(isImageFile(_secondPhoto), isTrue); // .jpeg with no type
    expect(isImageFile(_document), isFalse);
    expect(
      isImageFile(
        const SnCloudFileReference(
          id: 'f-txt',
          name: 'a.txt',
          mimeType: 'text/plain',
        ),
      ),
      isFalse,
    );
    expect(isVideoFile(_clip), isTrue);
    expect(isVideoFile(_document), isFalse);
  });

  testWidgets('attachments open in the lightbox, or the file page if not an '
      'image', (tester) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => switch (call.method) {
        'isMaximized' => false,
        _ => null,
      },
    );

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appAccessProvider.overrideWith(
            (ref) => const AsyncValue.data(AppAccess.ready),
          ),
          selectedWorkspaceProvider.overrideWith((ref) async => _workspace),
          mailboxesProvider.overrideWith((ref) async => const [_mailboxWork]),
          mailHostProvider.overrideWith((ref) async => 'example.com'),
          mailboxUnreadCountsProvider.overrideWith(
            (ref) async => const {'mb-1': 0},
          ),
          mailCredentialsProvider.overrideWith(
            (ref) async => const <MailCredential>[],
          ),
          mailSenderAvatarUrlsProvider.overrideWith(
            (ref) async => const <String, String>{},
          ),
          threadsProvider.overrideWith(
            (ref, query) async =>
                PaginatedResult<MailThread>(items: [_thread], totalCount: 1),
          ),
          threadProvider.overrideWith((ref, id) async => [_email]),
          emailProvider.overrideWith((ref, id) async => _email),
          realtimeBridgeProvider.overrideWith((ref) => RealtimeBridge(ref)),
          websocketStateProvider.overrideWith(WebSocketStateNotifier.new),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en', 'US')],
          path: 'assets/i18n',
          fallbackLocale: const Locale('en', 'US'),
          useFallbackTranslations: true,
          child: SolWattApp(),
        ),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );

    // Open the message. The body is plain text, so the attachment footer is
    // revealed by the body's own first metrics report, not by a scroll.
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
    // Media previews in place; the document stays a chip. The two pictures and
    // the video preview, one chip for the PDF.
    expect(find.byType(CloudFileAttachmentList), findsOneWidget);
    expect(find.byType(CloudImageWidget), findsNWidgets(2));
    expect(find.byType(CloudFileChip), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);

    // Tapping an image opens the lightbox on that image.
    await tester.tap(find.byType(CloudImageWidget).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CloudFileLightbox), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CloudFileLightbox),
        matching: find.text('photo.JPG'),
      ),
      findsOneWidget,
    );
    // Both pictures ride along, so the gallery can page between them.
    expect(
      find.descendant(
        of: find.byType(CloudFileLightbox),
        matching: find.text('1 / 2'),
      ),
      findsOneWidget,
    );
    _drainLoadErrors(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(CloudFileLightbox),
        matching: find.byIcon(Symbols.close),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CloudFileLightbox), findsNothing);
    _drainLoadErrors(tester);

    // A video preview opens the file page, where it plays.
    await tester.tap(find.byType(CloudVideoWidget));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(FileDetailScreen), findsOneWidget);
    expect(find.byType(CloudFileLightbox), findsNothing);
    _drainLoadErrors(tester);

    // So does a document, which never had a preview to tap.
    Navigator.of(
      tester.element(find.byType(FileDetailScreen)),
    ).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('report.pdf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(FileDetailScreen), findsOneWidget);
    expect(find.byType(CloudFileLightbox), findsNothing);
    _drainLoadErrors(tester);
  });
}
