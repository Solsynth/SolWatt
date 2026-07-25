import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/ui/alert.dart';
import 'package:url_launcher/url_launcher_string.dart';

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

/// Opens the notification inbox as an overlay dialog.
Future<void> showNotificationsDialog(WidgetRef ref) {
  return showOverlayDialog<void>(
    builder: (context, close) =>
        _NotificationsDialog(onClose: () => close(null)),
  );
}

class _NotificationsDialog extends ConsumerStatefulWidget {
  const _NotificationsDialog({required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<_NotificationsDialog> createState() =>
      _NotificationsDialogState();
}

class _NotificationsDialogState extends ConsumerState<_NotificationsDialog> {
  var _markingAll = false;

  Future<void> _markAll() async {
    setState(() => _markingAll = true);
    try {
      await markAllNotificationsRead(ref);
    } catch (error) {
      if (mounted) showErrorAlert(error);
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _openNotification(SnNotification notification) async {
    if (notification.viewedAt == null) {
      await markNotificationRead(ref, notification.id);
    }
    final uri = notification.meta['action_uri']?.toString();
    if (uri == null || uri.isEmpty) return;
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      await launchUrlString(uri);
    }
    // In-app deep links can be wired when SolWatt has matching routes.
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final list = ref.watch(notificationListProvider);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
        title: Row(
          children: [
            Expanded(child: Text('Notifications', style: text.titleLarge)),
            IconButton(
              tooltip: 'Mark all as read',
              onPressed: _markingAll ? null : _markAll,
              icon: _markingAll
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
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
            IconButton(
              tooltip: 'Close',
              onPressed: widget.onClose,
              icon: const Icon(Symbols.close),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          height: 480,
          child: Column(
            children: [
              if (_markingAll)
                LinearProgressIndicator(minHeight: 2, color: scheme.primary),
              Expanded(
                child: list.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Symbols.error, size: 40, color: scheme.error),
                          const SizedBox(height: 12),
                          Text(
                            'Could not load notifications',
                            style: text.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            error.toString(),
                            textAlign: TextAlign.center,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.tonal(
                            onPressed: () {
                              ref.invalidate(notificationListProvider);
                              ref.invalidate(notificationUnreadCountProvider);
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  data: (items) {
                    if (items.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Symbols.notifications_off,
                                size: 40,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No notifications yet',
                                style: text.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'SolWatt alerts for this account will show up here.',
                                textAlign: TextAlign.center,
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(notificationListProvider);
                        ref.invalidate(notificationUnreadCountProvider);
                        await ref.read(notificationListProvider.future);
                      },
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final notification = items[index];
                          return _NotificationTile(
                            notification: notification,
                            onTap: () => _openNotification(notification),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

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
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          const SizedBox(height: 2),
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
          onTap: () => showNotificationsDialog(ref),
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
