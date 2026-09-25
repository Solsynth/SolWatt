import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solwatt/mail/import/mail_import_service.dart';
import 'package:solwatt/mail/mail_settings_page.dart';
import 'package:solwatt/network.dart';

const _workspace = Workspace(
  id: 'ws-1',
  slug: 'ws-1',
  name: 'Test Workspace',
  isBundled: false,
);

const _mailboxWork = MailMailbox(
  id: 'mb-1',
  accountId: 'acc-1',
  workspaceId: 'ws-1',
  address: 'work@example.com',
  name: 'Work',
  isDefault: true,
  isVerified: true,
);

const _mboxBytes = '''
From alice@example.com Sat Sep 25 10:00:00 2026
Subject: one

body one
From bob@example.com Sat Sep 25 11:00:00 2026
Subject: two

body two
''';

final class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile(this._name, this._bytes);

  final String _name;
  final Uint8List _bytes;

  @override
  String get name => _name;

  @override
  Uri get uri => Uri.dataFromBytes(_bytes);

  @override
  XFile get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => _bytes.length;

  @override
  Future<int?> length() async => _bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Stream<Uint8List> readAsByteStream() async* {
    yield _bytes;
  }
}

class _MockFilePicker extends FilePickerPlatform {
  _MockFilePicker(this.files);

  final List<PlatformFile> files;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => files;
}

void main() {
  SharedPreferences.setMockInitialValues({});

  testWidgets('import preview gates requests until confirmed', (tester) async {
    await EasyLocalization.ensureInitialized();
    final overlayKey = GlobalKey<OverlayState>();
    IslandUIFoundation.configureOverlay(overlayKey);
    FilePickerPlatform.instance = _MockFilePicker([
      _FakePlatformFile(
        'emails.mbox',
        Uint8List.fromList(_mboxBytes.codeUnits),
      ),
    ]);
    var postedCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectedWorkspaceProvider.overrideWith((ref) async => _workspace),
          mailboxesProvider.overrideWith((ref) async => const [_mailboxWork]),
          mailImportServiceProvider.overrideWith(
            (ref) => MailImportService(
              poster: (items, dedupe) async {
                postedCount += items.length;
                return MailImportResult(imported: items.length);
              },
            ),
          ),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en', 'US')],
          path: 'assets/i18n',
          fallbackLocale: const Locale('en', 'US'),
          useFallbackTranslations: true,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              builder: (context, child) => Overlay(
                key: overlayKey,
                initialEntries: [
                  OverlayEntry(
                    builder: (_) => child ?? const SizedBox.shrink(),
                  ),
                ],
              ),
              home: Consumer(
                builder: (context, ref, _) {
                  // Resolve these before the action reads `.value`.
                  ref.watch(selectedWorkspaceProvider);
                  ref.watch(mailboxesProvider);
                  return Scaffold(
                    body: Center(
                      child: FilledButton(
                        onPressed: () =>
                            importEmailsAction(context, ref, mailboxId: 'mb-1'),
                        child: const Text('go'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Parsing runs in a real background isolate (`compute`), whose result is
    // only delivered while the test pumps real async — hence runAsync.
    Future<void> pickAndParse() async {
      await tester.runAsync(() async {
        await tester.tap(find.text('go'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
    }

    await pickAndParse();

    // Preview dialog: count, per-file row, target mailbox. No request yet.
    expect(find.text('Import preview'), findsOneWidget);
    expect(find.text('Import 2 emails into Work?'), findsOneWidget);
    expect(find.text('emails.mbox'), findsOneWidget);
    expect(find.text('2 emails'), findsOneWidget);
    expect(postedCount, 0);

    // Cancelling drops the task and sends nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(postedCount, 0);
    expect(find.text('Import preview'), findsNothing);

    // Confirming sends the parsed messages; the action's continuation runs in
    // the real zone it started in, so wait for it inside runAsync.
    await pickAndParse();
    await tester.runAsync(() async {
      await tester.tap(find.text('Import'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(postedCount, 2);
    expect(
      find.text('Imported 2 emails, 0 duplicates skipped, 0 failed.'),
      findsOneWidget,
    );
  });
}
