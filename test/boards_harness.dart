/// Fixtures and the app harness shared by the boards widget tests.
///
/// The router is an app-wide singleton, so a test file can only pump one app;
/// a scenario that needs its own router state lives in its own test file.
library;

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/realtime/realtime.dart';
import 'package:solwatt/websocket.dart';
import 'package:solwatt/mail/mail_address_suggestion.dart';

const boardWorkspace = Workspace(
  id: 'ws-1',
  slug: 'ws-1',
  name: 'Test Workspace',
  isBundled: false,
);

const roadmapBoard = Broad(
  id: 'board-a',
  name: 'Roadmap',
  description: 'What ships next',
  workspaceId: 'ws-1',
  taskPrefix: 'RM',
);

const choresBoard = Broad(id: 'board-b', name: 'Chores', workspaceId: 'ws-1');

const doingGroup = TaskGroup(id: 'group-1', name: 'Doing', broadId: 'board-a');

/// The Mail tab is where the shell opens, so the harness has to keep it
/// rendering; its content is irrelevant here.
const testMailbox = MailMailbox(
  id: 'mb-1',
  accountId: 'acc-1',
  workspaceId: 'ws-1',
  address: 'work@example.com',
  name: 'Work',
  isDefault: true,
  isVerified: true,
);

/// Twenty-four roadmap tasks, varied so a test can pick the shape it needs:
/// 1 carries Markdown, 2 tags, 3 a priority, 4 a deadline, 6 no key stamp.
final boardTasks = [
  for (var index = 1; index <= 24; index++)
    WorkTask(
      id: 'task-$index',
      name: 'Task $index',
      broadId: 'board-a',
      taskKey: index == 6 ? null : 'RM-$index',
      groupId: 'group-1',
      description: index == 1 ? 'Notes with *emphasis*' : null,
      content: index == 1 ? '**Bold** detail\n\n- item' : null,
      tags: index == 2 ? const ['design', 'urgent', 'api'] : const [],
      priority: index == 3 ? 2 : 0,
      deadlineAt: index == 4 ? DateTime(2026, 1, 1) : null,
    ),
];

Future<void> pumpBoardsApp(
  WidgetTester tester,
  Size size, {
  WattEngineClient? client,
  List<Workspace>? workspaces,
}) async {
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();
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
      key: ValueKey('boards-${size.width}x${size.height}'),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appAccessProvider.overrideWith(
          (ref) => const AsyncValue.data(AppAccess.ready),
        ),
        selectedWorkspaceProvider.overrideWith((ref) async => boardWorkspace),
        mailboxesProvider.overrideWith((ref) async => const [testMailbox]),
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
        broadsProvider.overrideWith(
          (ref) async => const [roadmapBoard, choresBoard],
        ),
        tasksProvider.overrideWith((ref, request) async => boardTasks),
        taskGroupsProvider.overrideWith(
          (ref, broadId) async =>
              broadId == roadmapBoard.id ? const [doingGroup] : const [],
        ),
        realtimeBridgeProvider.overrideWith((ref) => RealtimeBridge(ref)),
        websocketStateProvider.overrideWith(WebSocketStateNotifier.new),
        if (client != null) wattEngineClientProvider.overrideWithValue(client),
        if (workspaces != null)
          workspacesProvider.overrideWith((ref) async => workspaces),
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
}

/// The board tabs live behind the burger on every width (the rail shows mail
/// folders while Mail is active).
Future<void> openBoardsTab(WidgetTester tester) async {
  await tester.tap(find.byIcon(Symbols.menu));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationDrawer),
      matching: find.text('Boards'),
    ),
  );
  await tester.pumpAndSettle();
}

/// Rejects task creation the way WattEngine does when the board is over its
/// plan quota: HTTP 400 with the reason in a plain-text body.
class RejectingTaskClient extends WattEngineClient {
  RejectingTaskClient()
    : super(SolarNetworkAuthenticator(const FlutterSecureStorage()));

  static const reason =
      'Workspace plan (0) allows max 100 tasks per broad. Current count: 118.';

  @override
  Future<WorkTask> createTask(String broadId, WorkTaskDraft task) async {
    final options = RequestOptions(path: '/ideask/broads/$broadId/tasks');
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<String>(
        requestOptions: options,
        statusCode: 400,
        data: reason,
      ),
    );
  }
}
