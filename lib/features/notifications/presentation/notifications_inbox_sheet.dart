import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rentflow/features/notifications/data/notifications_repository.dart';
import 'package:rentflow/features/notifications/domain/notification_models.dart';

/// Phase 18 In-App Notification Inbox sheet.
class NotificationsInboxSheet extends ConsumerWidget {
  const NotificationsInboxSheet({
    required this.scrollController,
    super.key,
  });

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsControllerProvider).valueOrNull ??
        const <NotificationEventItem>[];
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'Notifications (${items.where((NotificationEventItem n) => n.isUnread).length})',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        ...items.map(
          (NotificationEventItem n) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              key: Key('notification_card_${n.id}'),
              margin: EdgeInsets.zero,
              child: ListTile(
                title: Text(
                  n.title,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: n.isUnread ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
                subtitle: Text('${n.body}\nLocale: ${n.localeSnapshot}'),
                trailing: n.isUnread
                    ? IconButton(
                        key: Key('mark_notification_read_${n.id}'),
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        onPressed: () => ref
                            .read(notificationsControllerProvider.notifier)
                            .markRead(n.id),
                        icon: const Icon(Icons.done_all_outlined),
                      )
                    : const Icon(
                        Icons.check_circle,
                        color: Color(0xFF14532D),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
