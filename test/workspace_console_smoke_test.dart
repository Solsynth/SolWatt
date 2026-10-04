import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/mail/mail_address_suggestion.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/realtime/realtime.dart';
import 'package:solwatt/websocket.dart';

const _active = Workspace(id: 'ws-1', slug: 'ws-1', name: 'Test Workspace');

const _workspaces = [
  _active,
  Workspace(
    id: 'ws-2',
    slug: 'acme',
    name: 'Acme Team',
    description: 'Everything, everywhere.',
    type: WorkspaceType.organization,
    plan: WorkspacePlanTier.pro,
  ),
];

const _mailbox = MailMailbox(
  id: 'mb-1',
  accountId: 'acc-1',
  workspaceId: 'ws-2',
  address: 'work@example.com',
  name: 'Work',
  isDefault: true,
  isVerified: true,
);

/// Answers the workspace console's reads without touching the network: the
/// test binding turns every real request into an HTTP 400.
class _ConsoleClient extends WattEngineClient {
  _ConsoleClient()
    : super(SolarNetworkAuthenticator(const FlutterSecureStorage()));

  @override
  Future<List<WorkspaceMember>> listWorkspaceMembers(String slug) async =>
      const [
        WorkspaceMember(
          id: 'm-1',
          accountId: 'acc-1',
          role: 100,
          fallbackNick: 'Ada Lovelace',
          fallbackUsername: 'ada',
        ),
      ];

  @override
  Future<WorkspaceDriveUsage> getWorkspaceDriveUsage(String workspaceId) async =>
      const WorkspaceDriveUsage(
        workspaceId: 'ws-2',
        usedBytes: 1024 * 1024,
        totalBytes: 4096 * 1024,
        remainingBytes: 3072 * 1024,
        totalFileCount: 12,
      );

  @override
  Future<String> getMailHost() async => 'example.com';

  @override
  Future<List<MailMailbox>> listMailboxes({String? workspaceId}) async =>
      const [_mailbox];

  @override
  Future<MailUsageSummary> getWorkspaceMailboxUsage(String workspaceId) async =>
      const MailUsageSummary(used: 10, limit: 100, remaining: 90);

  @override
  Future<List<MailCustomDomain>> listCustomDomains({
    required String workspaceId,
  }) async => const [
    MailCustomDomain(
      id: 'd-1',
      workspaceId: 'ws-2',
      domain: 'acme.example',
      verifiedForSending: true,
    ),
  ];

  @override
  Future<List<MailCredential>> listMailCredentials() async => const [];

  @override
  Future<List<FlywheelOwnerApp>> listFlywheelApps(String workspaceId) async =>
      [
        FlywheelOwnerApp(
          appId: 'dev.solsynth.maidkit',
          retainedRevisionCount: 3,
          blobCount: 2,
          retainedRevisionCountTotal: 5,
          retainedBytes: 2048,
          lastUpdatedAt: DateTime(2026, 1, 1),
        ),
      ];
}

Future<void> _pumpShell(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({
    'selected_workspace_id': _active.id,
  });
  await EasyLocalization.ensureInitialized();
  PackageInfo.setMockInitialValues(
    appName: 'SolWatt',
    packageName: 'dev.solsynth.solwatt',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (call) async => switch (call.method) {
      'isMaximized' => false,
      _ => null,
    },
  );

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appAccessProvider.overrideWith(
          (ref) => const AsyncValue.data(AppAccess.ready),
        ),
        secureStorageProvider.overrideWithValue(FlutterSecureStorage()),
        selectedWorkspaceProvider.overrideWith((ref) async => _active),
        workspacesProvider.overrideWith((ref) async => _workspaces),
        wattEngineClientProvider.overrideWithValue(_ConsoleClient()),
        mailboxesProvider.overrideWith((ref) async => const [_mailbox]),
        mailHostProvider.overrideWith((ref) async => 'example.com'),
        mailboxUnreadCountsProvider.overrideWith((ref) async => const {}),
        mailCredentialsProvider.overrideWith(
          (ref) async => const <MailCredential>[],
        ),
        threadsProvider.overrideWith(
          (ref, query) async =>
              const PaginatedResult<MailThread>(items: [], totalCount: 0),
        ),
        mailSenderIndexProvider.overrideWith(
          (ref) async => const <String, MailAddressSuggestion>{},
        ),
        broadsProvider.overrideWith((ref) async => const <Broad>[]),
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
  for (var attempt = 0; attempt < 40; attempt++) {
    if (find.byIcon(Symbols.menu).evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

void main() {
  testWidgets('drawer opens the workspace console and its detail', (
    tester,
  ) async {
    await _pumpShell(tester, const Size(420, 900));

    await tester.tap(find.byIcon(Symbols.menu));
    await tester.pumpAndSettle();
    expect(find.text('Manage workspaces'), findsOneWidget);

    await tester.tap(find.text('Manage workspaces'));
    await tester.pumpAndSettle();

    // Management screen: the registry of the account's workspaces.
    expect(find.text('Test Workspace'), findsOneWidget);
    expect(find.text('Acme Team'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // Open the per-workspace console.
    await tester.tap(find.text('Acme Team'));
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Mail'), findsOneWidget);
    expect(find.text('Flywheel'), findsOneWidget);
    expect(find.text('Everything, everywhere.'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);

    // Mail tab: workspace mailboxes, domains and usage.
    await tester.tap(find.text('Mail'));
    await tester.pumpAndSettle();
    expect(find.text('work@example.com'), findsOneWidget);

    // The domains section sits below the fold; the list builds lazily.
    await tester.drag(find.byType(ListView).last, const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(find.text('acme.example'), findsOneWidget);

    // Flywheel tab: the workspace's apps.
    await tester.tap(find.text('Flywheel'));
    await tester.pumpAndSettle();
    expect(find.text('MaidKit'), findsOneWidget);
  });
}
