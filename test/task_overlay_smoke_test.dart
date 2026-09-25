import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solwatt/tasks/app_task.dart';
import 'package:solwatt/tasks/task_overlay.dart';
import 'package:solwatt/tasks/tasks_notifier.dart';

void main() {
  SharedPreferences.setMockInitialValues({});

  testWidgets('task overlay bar, sheet, tile and import details render', (
    tester,
  ) async {
    await EasyLocalization.ensureInitialized();
    await tester.pumpWidget(
      ProviderScope(
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
              home: Consumer(
                builder: (context, ref, _) {
                  final notifier = ref.read(appTasksProvider.notifier);
                  return Scaffold(
                    body: Column(
                      children: [
                        const TaskOverlayHost(),
                        Expanded(
                          child: Center(
                            child: Wrap(
                              children: [
                                FilledButton(
                                  onPressed: () {
                                    final id = notifier.addTask(
                                      title: 'photo.jpg',
                                      type: AppTaskType.driveUpload,
                                      status: AppTaskStatus.inProgress,
                                      metadata: {
                                        'fileSize': 1000,
                                        'transmissionProgress': 0.4,
                                      },
                                    );
                                    notifier.updateTask(
                                      id,
                                      progress: 0.4,
                                      statusMessage: 'Uploading 1 of 1…',
                                    );
                                  },
                                  child: const Text('add-upload'),
                                ),
                                FilledButton(
                                  onPressed: () {
                                    final id = notifier.addTask(
                                      title: 'Import emails',
                                      type: AppTaskType.mailImport,
                                      status: AppTaskStatus.inProgress,
                                      metadata: {
                                        'imported': 3,
                                        'duplicates': 1,
                                        'failed': 0,
                                      },
                                    );
                                    notifier.updateTask(
                                      id,
                                      progress: 0.5,
                                      statusMessage: 'Importing 1 of 2…',
                                    );
                                  },
                                  child: const Text('add-import'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    // Bar slides in with title + percentage.
    await tester.pumpAndSettle();
    await tester.tap(find.text('add-upload'));
    await tester.pumpAndSettle();
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);

    // Sheet lists the tile with its circular indicator.
    await tester.tap(find.text('photo.jpg'));
    await tester.pumpAndSettle();
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('40'), findsOneWidget); // inside the circular indicator

    // Expanded details: transmission header, bytes row, progress bar.
    await tester.tap(find.text('photo.jpg').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Uploading 1 of 1…'),
      findsWidgets,
    ); // bar + tile subtitle + details header
    expect(find.text('40.0%'), findsOneWidget);
    expect(find.text('400 B / 1000 B'), findsOneWidget);

    // Close the sheet, add a mail-import task, inspect its counters.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text('add-import'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import emails').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import emails').last); // expand the tile
    await tester.pumpAndSettle();
    expect(find.text('Imported'), findsOneWidget);
    expect(find.text('Duplicates'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
  });
}
