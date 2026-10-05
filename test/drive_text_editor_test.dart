import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/widgets/content/file_viewer_contents.dart';
import 'package:solwatt/network.dart';

/// Answers drive requests by `METHOD path` and records every request, so a test
/// can assert the exact save the editor issues.
class _DriveStub implements HttpClientAdapter {
  _DriveStub(this.answers);

  final Map<String, ResponseBody> answers;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final key = '${options.method} ${options.uri.path}';
    final answer = answers[key];
    if (answer == null) {
      throw StateError('unexpected request: $key');
    }
    return answer;
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _text(String body) => ResponseBody.fromString(
  body,
  200,
  headers: {
    Headers.contentTypeHeader: ['text/markdown'],
  },
);

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

SnCloudFile _file({int size = 20}) => SnCloudFile(
  id: 'file-1',
  accountId: 'account-1',
  description: null,
  indexed: true,
  isFolder: false,
  isMarkedRecycle: false,
  name: 'notes.md',
  object: SnCloudFileObject(
    id: 'object-1',
    size: size,
    meta: const {},
    mimeType: 'text/markdown',
    hash: 'hash-1',
    hasCompression: false,
    hasThumbnail: false,
    fileReplicas: const [],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    deletedAt: null,
  ),
  objectId: 'object-1',
  parentId: null,
  resourceIdentifier: 'file-1',
  storageId: null,
  storageUrl: null,
  mimeType: 'text/markdown',
  applicationType: null,
  usage: null,
  permissionStatus: null,
  uploadedAt: DateTime(2026, 1, 1),
  expiredAt: null,
  updatedAt: DateTime(2026, 1, 1),
  createdAt: DateTime(2026, 1, 1),
  deletedAt: null,
);

/// Serves the editor's copy from memory: probing the real i18n assets from a
/// widget test leaves easy_localization's load pending once a previous test in
/// the same file has failed the `en.json` probe, so the harness would never
/// render. Strings mirror `assets/i18n/en-US.json`.
class _StubAssetLoader extends AssetLoader {
  const _StubAssetLoader();

  static const Map<String, String> strings = {
    'cancel': 'Cancel',
    'discardChanges': 'Discard changes',
    'discardChangesPrompt': 'Discard unsaved changes?',
    'editFileContent': 'Edit file',
    'fileContentLoadFailed': 'Failed to load file content: {}',
    'fileSaveFailed': 'Failed to save file: {}',
    'fileSaved': 'File saved',
    'markdownPreview': 'Preview',
    'markdownSource': 'Source',
    'save': 'Save',
    'unsavedChanges': 'Unsaved changes',
  };

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      strings;
}

SolarNetworkClient _client(_DriveStub stub) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example'));
  dio.httpClientAdapter = stub;
  return SolarNetworkClient.fromDio(dio);
}

Widget _harness({required SolarNetworkClient client, required Widget child}) {
  // Toasts land on the foundation overlay the app configures in `main.dart`.
  final overlayKey = GlobalKey<OverlayState>();
  IslandUIFoundation.configureOverlay(overlayKey);
  return ProviderScope(
    overrides: [solarNetworkClientProvider.overrideWith((ref) => client)],
    child: EasyLocalization(
      assetLoader: const _StubAssetLoader(),
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/i18n',
      fallbackLocale: const Locale('en', 'US'),
      useFallbackTranslations: true,
      child: Builder(
        builder: (context) => MaterialApp(
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: [
            ...context.localizationDelegates,
            ...mui.GlobalMaterialLocalizations.delegates,
          ],
          home: Overlay(
            key: overlayKey,
            initialEntries: [
              OverlayEntry(builder: (_) => Scaffold(body: child)),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a markdown file renders and saves an edit in place', (
    tester,
  ) async {
    await EasyLocalization.ensureInitialized();
    const original = '# Title\n\noriginal body';
    const edited = '# Title\n\nedited body';
    final stub = _DriveStub({
      'GET /drive/files/file-1': _text(original),
      'PUT /drive/files/file-1': _json(_file(size: edited.length).toJson()),
    });
    SnCloudFile? saved;

    await tester.pumpWidget(
      _harness(
        client: _client(stub),
        child: TextFileContent(
          item: _file(),
          workspaceId: 'ws-1',
          onSaved: (file) => saved = file,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Loaded content renders as markdown, not as raw source.
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.text(original), findsNothing);

    await tester.tap(find.byTooltip('Edit file'));
    await tester.pumpAndSettle();
    expect(find.text(original), findsOneWidget);

    await tester.enterText(find.byType(TextField), edited);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final put = stub.requests.singleWhere((request) => request.method == 'PUT');
    expect(put.uri.path, '/drive/files/file-1');
    expect(put.uri.queryParameters['workspace_id'], 'ws-1');
    expect(put.data, edited);
    expect(
      put.headers[Headers.contentTypeHeader],
      'text/plain; charset=utf-8',
    );

    // Back to the rendered view, with the refreshed metadata handed to the host.
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(saved?.id, 'file-1');
    expect(saved?.size, edited.length);
  });

  testWidgets('a refused save keeps the draft and reports the server error', (
    tester,
  ) async {
    await EasyLocalization.ensureInitialized();
    const original = '# Title';
    final stub = _DriveStub({
      'GET /drive/files/file-1': _text(original),
      'PUT /drive/files/file-1': _json({'error': 'forbidden'}, 403),
    });

    await tester.pumpWidget(
      _harness(
        client: _client(stub),
        child: TextFileContent(item: _file()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit file'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '# Title\n\nrejected');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('# Title\n\nrejected'), findsOneWidget);
    expect(find.text('Failed to save file: forbidden'), findsOneWidget);
  });

  testWidgets('read-only surfaces keep no editor', (tester) async {
    await EasyLocalization.ensureInitialized();
    final stub = _DriveStub({
      'GET /drive/files/file-1': _text('# Title'),
    });

    await tester.pumpWidget(
      _harness(
        client: _client(stub),
        child: TextFileContent(item: _file(), editable: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.byTooltip('Edit file'), findsNothing);
    expect(find.byTooltip('Source'), findsOneWidget);
  });
}
