/// Domain model for Phase 18 In-App Notification Inbox & FCM Device Tokens.
class NotificationEventItem {
  const NotificationEventItem({
    required this.id,
    required this.eventType,
    required this.localeSnapshot,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String eventType;
  final String localeSnapshot;
  final String title;
  final String body;
  final String createdAt;
  final String? readAt;

  bool get isUnread => readAt == null;

  NotificationEventItem copyWith({
    String? readAt,
  }) {
    return NotificationEventItem(
      id: id,
      eventType: eventType,
      localeSnapshot: localeSnapshot,
      title: title,
      body: body,
      createdAt: createdAt,
      readAt: readAt ?? this.readAt,
    );
  }
}
