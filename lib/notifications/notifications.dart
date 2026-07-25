import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/ui/alert.dart';
import 'package:url_launcher/url_launcher_string.dart';

const kNotificationsAttentionModalId = 'notifications';

/// Unread notification count for the SolWatt Ring tenant.
final notificationUnreadCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final session = await ref.watch(authSessionProvider.future);
  if (session == null) return 0;
  try {
    return await ref
        .watch(solarNetworkClientProvider)
        .notifications
        .getUnreadCount(app: kNotificationTenantAppId);
  } catch (_) {
    return 0;
  }
});

/// Paginated notification inbox for the SolWatt Ring tenant.
final notificationListProvider =
    FutureProvider.autoDispose<List<SnNotification>>((ref) async {
      final session = await ref.watch(authSessionProvider.future);
      if (session == null) return const [];
      final page = await ref
          .watch(solarNetworkClientProvider)
          .notifications
          .getNotifications(offset: 0, take: 40, app: kNotificationTenantAppId);
      return page.items;
    });

/// Marks every SolWatt-tenant notification as read and refreshes providers.
Future<void> markAllNotificationsRead(WidgetRef ref) async {
  final client = ref.read(solarNetworkClientProvider);
  await client.notifications.markAllAsRead(app: kNotificationTenantAppId);
  ref.invalidate(notificationUnreadCountProvider);
  ref.invalidate(notificationListProvider);
}

/// Marks a single notification as read (best-effort) and refreshes counts.
Future<void> markNotificationRead(WidgetRef ref, String notificationId) async {
  try {
    await ref
        .read(solarNetworkClientProvider)
        .notifications
        .markAsRead(notificationId);
  } catch (_) {
    // Viewing the list may already have marked it server-side.
  }
  ref.invalidate(notificationUnreadCountProvider);
  ref.invalidate(notificationListProvider);
}

/// Opens the SolWatt notifications attention modal (Island-style).
///
/// Uses [showAttentionModal] + [AttentionModalScaffold] from
/// `island_ui_foundation` — blur barrier, card on desktop, full sheet on
/// narrow layouts.
Future<void> showNotificationsAttentionModal() {
  return showAttentionModal(
    id: kNotificationsAttentionModalId,
    replaceIfExists: true,
    barrierDismissible: true,
    builder: (context, dismiss) => NotificationModal(onDismiss: dismiss),
  );
}

/// Island-style notification inbox presented inside an attention modal.
class NotificationModal extends HookConsumerWidget {
  const NotificationModal({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useEffect(() {
      Future.microtask(() {
        ref.invalidate(notificationUnreadCountProvider);
        ref.invalidate(notificationListProvider);
      });
      return null;
    }, const []);

    final isMarkingAll = useState(false);
    final list = ref.watch(notificationListProvider);
    final scheme = Theme.of(context).colorScheme;

    Future<void> markAllRead() async {
      isMarkingAll.value = true;
      try {
        await markAllNotificationsRead(ref);
      } catch (error) {
        if (context.mounted) showErrorAlert(error);
      } finally {
        if (context.mounted) isMarkingAll.value = false;
      }
    }

    Future<void> openNotification(SnNotification notification) async {
      if (notification.viewedAt == null) {
        await markNotificationRead(ref, notification.id);
      }
      final uri = notification.meta['action_uri']?.toString();
      if (uri == null || uri.isEmpty) return;
      if (uri.startsWith('http://') || uri.startsWith('https://')) {
        await launchUrlString(uri);
      }
      // In-app deep links can be wired when SolWatt has matching routes.
      if (context.mounted) {
        dismissAttentionModal(kNotificationsAttentionModalId);
      }
    }

    return AttentionModalScaffold(
      titleText: 'Notifications',
      onDismiss: onDismiss,
      maxWidth: 560,
      actions: [
        IconButton(
          tooltip: 'Mark all as read',
          onPressed: isMarkingAll.value ? null : markAllRead,
          icon: isMarkingAll.value
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                )
              : const Icon(Symbols.done_all),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: () {
            ref.invalidate(notificationListProvider);
            ref.invalidate(notificationUnreadCountProvider);
          },
          icon: const Icon(Symbols.refresh),
        ),
      ],
      child: Column(
        children: [
          if (isMarkingAll.value)
            LinearProgressIndicator(minHeight: 2, color: scheme.primary),
          Expanded(
            child: list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _NotificationsError(
                error: error,
                onRetry: () {
                  ref.invalidate(notificationListProvider);
                  ref.invalidate(notificationUnreadCountProvider);
                },
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const _NotificationsEmpty();
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(notificationListProvider);
                    ref.invalidate(notificationUnreadCountProvider);
                    await ref.read(notificationListProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      indent: 72,
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    itemBuilder: (context, index) {
                      final notification = items[index];
                      return NotificationTile(
                        notification: notification,
                        onTap: () => openNotification(notification),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationsEmpty extends StatelessWidget {
  const _NotificationsEmpty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.notifications_off,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('No notifications yet', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              'SolWatt alerts for this account will show up here.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsError extends StatelessWidget {
  const _NotificationsError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.error, size: 48, color: scheme.error),
            const SizedBox(height: 16),
            Text('Could not load notifications', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// Single notification row for the attention modal list.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
  });

  final SnNotification notification;
  final VoidCallback onTap;

  IconData get _icon => switch (notification.topic) {
    final t when t.contains('task') => Symbols.task_alt,
    final t when t.contains('board') || t.contains('broad') =>
      Symbols.view_kanban,
    final t when t.contains('workspace') => Symbols.workspaces,
    final t when t.contains('invite') => Symbols.group_add,
    final t when t.contains('plan') || t.contains('billing') =>
      Symbols.payments,
    _ => Symbols.notifications,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final unread = notification.viewedAt == null;
    final when = _formatRelative(notification.createdAt.toLocal());

    return ListTile(
      isThreeLine:
          notification.body.isNotEmpty || notification.subtitle.isNotEmpty,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: unread
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        child: Icon(
          _icon,
          size: 20,
          color: unread ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        notification.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: text.titleSmall?.copyWith(
          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (notification.subtitle.isNotEmpty)
            Text(
              notification.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          if (notification.body.isNotEmpty)
            Text(
              notification.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          const SizedBox(height: 4),
          Text(
            when,
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      trailing: unread
          ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}

/// Compact bell button with optional unread badge for the app shell.
class NotificationBellButton extends ConsumerWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(notificationUnreadCountProvider).value ?? 0;
    final scheme = Theme.of(context).colorScheme;
    final badge = math.min(count, 99);

    return Tooltip(
      message: badge > 0 ? 'Notifications ($badge unread)' : 'Notifications',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: showNotificationsAttentionModal,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Symbols.notifications,
                  color: scheme.onSurfaceVariant,
                  fill: badge > 0 ? 1 : 0,
                ),
                if (badge > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: scheme.error,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: TextStyle(
                          color: scheme.onError,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatRelative(DateTime value) {
  final now = DateTime.now();
  final diff = now.difference(value);
  if (diff.inSeconds < 45) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
