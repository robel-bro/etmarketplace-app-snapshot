import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/client.dart';

// Notification model (unchanged)
class NotificationItem {
  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
  final NotificationType type;
  final Map<String, dynamic>? data;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.isRead,
    required this.type,
    this.data,
  });

  NotificationItem copyWith({
    String? id,
    String? title,
    String? message,
    DateTime? createdAt,
    bool? isRead,
    NotificationType? type,
    Map<String, dynamic>? data,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      type: type ?? this.type,
      data: data ?? this.data,
    );
  }

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'].toString(),
      title: json['title'] as String,
      message: json['message'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      isRead: json['is_read'] as bool? ?? false,
      type: _parseType(json['type'] as String?),
      data: json['data'] as Map<String, dynamic>?,
    );
  }

  static NotificationType _parseType(String? type) {
    switch (type) {
      case 'order':
        return NotificationType.order;
      case 'promotion':
        return NotificationType.promotion;
      case 'social':
        return NotificationType.social;
      default:
        return NotificationType.system;
    }
  }
}

enum NotificationType { order, promotion, system, social }

// StateNotifier
class NotificationNotifier extends StateNotifier<List<NotificationItem>> {
  NotificationNotifier() : super([]) {
    fetchNotifications();
  }

  Future<void> fetchNotifications() async {
    try {
      final response = await ApiClient.instance.get('/notifications');
      final List data = response.data['data'] ?? response.data;
      state = data.map((json) => NotificationItem.fromJson(json)).toList();
    } catch (e) {
      // No backend endpoint yet – leave list empty
      state = [];
    }
  }

  void markAsRead(String id) {
    state = [for (final n in state) if (n.id == id) n.copyWith(isRead: true) else n];
  }

  void markAllAsRead() {
    state = [for (final n in state) n.copyWith(isRead: true)];
  }

  void removeNotification(String id) {
    state = state.where((n) => n.id != id).toList();
  }

  void clearAll() => state = [];

  void addNotification(NotificationItem notification) {
    state = [notification, ...state];
  }

  int get unreadCount => state.where((n) => !n.isRead).length;
}

final notificationProvider = StateNotifierProvider<NotificationNotifier, List<NotificationItem>>((ref) {
  return NotificationNotifier();
});

final unreadNotificationsCountProvider = Provider<int>((ref) {
  return ref.watch(notificationProvider.notifier).unreadCount;
});