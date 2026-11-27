import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rentflow/features/notifications/domain/notification_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository contract for Phase 18 In-App Notification Inbox and FCM Device
/// Token Registration.
abstract class NotificationsRepository {
  Future<List<NotificationEventItem>> listNotifications();

  Future<void> markAsRead(String notificationId);

  Future<void> registerDeviceToken({
    required String fcmToken,
    String platform = 'android',
  });
}

class SupabaseNotificationsRepository implements NotificationsRepository {
  const SupabaseNotificationsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<NotificationEventItem>> listNotifications() async {
    final rows = await _client
        .from('notification_events')
        .select(
            'id, event_type, locale_snapshot, title_key, body_key, created_at, read_at')
        .order('created_at', ascending: false);

    return (rows as List<dynamic>).cast<Map<String, dynamic>>().map((
      Map<String, dynamic> r,
    ) {
      return NotificationEventItem(
        id: r['id'] as String,
        eventType: r['event_type'] as String,
        localeSnapshot: r['locale_snapshot'] as String,
        title: r['title_key'] as String,
        body: r['body_key'] as String,
        createdAt: r['created_at'].toString(),
        readAt: r['read_at']?.toString(),
      );
    }).toList();
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    await _client.from('notification_events').update(<String, dynamic>{
      'read_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', notificationId);
  }

  @override
  Future<void> registerDeviceToken({
    required String fcmToken,
    String platform = 'android',
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || fcmToken.trim().isEmpty) {
      return;
    }
    await _client.from('device_tokens').upsert(<String, dynamic>{
      'profile_id': uid,
      'fcm_token': fcmToken.trim(),
      'platform': platform,
      'active': true,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}

class InMemoryNotificationsRepository implements NotificationsRepository {
  InMemoryNotificationsRepository() {
    _items.addAll(const <NotificationEventItem>[
      NotificationEventItem(
        id: 'notif-1',
        eventType: 'monthly_rent_reminder',
        localeSnapshot: 'bn_BD',
        title: 'ভাড়া পরিশোধের স্মারক · S-01',
        body: 'নভেম্বর ২০২৬-এর ভাড়া ৳১২,০০০ ৫ নভেম্বরের মধ্যে প্রদেয়।',
        createdAt: '2026-11-01T09:00:00Z',
      ),
      NotificationEventItem(
        id: 'notif-2',
        eventType: 'agreement_expiry_reminder',
        localeSnapshot: 'en',
        title: 'Agreement Expiry Reminder · AG-2026-04',
        body:
            'Agreement for Shop S-01 expires within the 3-calendar-month window.',
        createdAt: '2026-11-01T09:05:00Z',
      ),
    ]);
  }

  final List<NotificationEventItem> _items = <NotificationEventItem>[];
  final List<String> registeredTokens = <String>[];

  @override
  Future<List<NotificationEventItem>> listNotifications() async =>
      List<NotificationEventItem>.unmodifiable(_items);

  @override
  Future<void> markAsRead(String notificationId) async {
    final idx =
        _items.indexWhere((NotificationEventItem n) => n.id == notificationId);
    if (idx >= 0) {
      _items[idx] = _items[idx].copyWith(readAt: '2026-11-27T11:00:00Z');
    }
  }

  @override
  Future<void> registerDeviceToken({
    required String fcmToken,
    String platform = 'android',
  }) async {
    if (fcmToken.trim().isNotEmpty) {
      registeredTokens.add(fcmToken.trim());
    }
  }
}

final notificationsRepositoryProvider =
    Provider<NotificationsRepository>((Ref ref) {
  return InMemoryNotificationsRepository();
});

class NotificationsController
    extends AsyncNotifier<List<NotificationEventItem>> {
  @override
  Future<List<NotificationEventItem>> build() async {
    return ref.watch(notificationsRepositoryProvider).listNotifications();
  }

  Future<void> markRead(String notificationId) async {
    final repo = ref.read(notificationsRepositoryProvider);
    await repo.markAsRead(notificationId);
    state = AsyncData<List<NotificationEventItem>>(
      await repo.listNotifications(),
    );
  }
}

final notificationsControllerProvider =
    AsyncNotifierProvider<NotificationsController, List<NotificationEventItem>>(
  NotificationsController.new,
);
