import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:solwatt/mail/mail_screen.dart';
import 'package:solwatt/network.dart';

MailEmail _email({required bool isRead, required bool isStarred}) => MailEmail(
  id: 'e-1',
  mailboxId: 'mb-1',
  subject: 'Subject',
  body: 'Body',
  isDraft: false,
  isRead: isRead,
  isStarred: isStarred,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  test('email context menu exposes read, star, folder and delete actions', () {
    final starred = _email(isRead: false, isStarred: true);
    final moves = <String>[];
    var readToggles = 0;
    var starToggles = 0;
    var deletes = 0;

    final items = emailContextMenuItems(
      isRead: starred.isRead,
      isStarred: starred.isStarred,
      onToggleRead: () => readToggles++,
      onToggleStar: () => starToggles++,
      onMove: moves.add,
      onDelete: () => deletes++,
    );

    final actions = items.whereType<MenuAction>().toList();
    expect(items.whereType<MenuSeparator>().length, 2);
    expect(actions.length, 6);

    final starAction = actions.firstWhere(
      (action) => action.state == MenuActionState.checkOn,
    );
    final deleteAction = actions.firstWhere(
      (action) => action.attributes.destructive,
    );
    expect(actions.where((action) => action.attributes.destructive).length, 1);

    actions[0].callback(); // mark read / unread
    starAction.callback();
    for (final folder in ['archive', 'spam', 'trash']) {
      actions
          .firstWhere(
            (action) =>
                action.title ==
                (switch (folder) {
                  'archive' => 'folderArchive'.tr(),
                  'spam' => 'folderSpam'.tr(),
                  _ => 'folderTrash'.tr(),
                }),
          )
          .callback();
    }
    deleteAction.callback();

    expect(readToggles, 1);
    expect(starToggles, 1);
    expect(deletes, 1);
    expect(moves, ['archive', 'spam', 'trash']);
  });

  test('unread unstarred message reports unstarred menu state', () {
    final items = emailContextMenuItems(
      isRead: true,
      isStarred: false,
      onToggleRead: () {},
      onToggleStar: () {},
      onMove: (_) {},
      onDelete: () {},
    );

    final actions = items.whereType<MenuAction>().toList();
    expect(
      actions.any((action) => action.state == MenuActionState.checkOn),
      isFalse,
    );
    expect(actions.first.title, 'markUnread'.tr());
    expect(actions[1].title, 'star'.tr());
  });
}
