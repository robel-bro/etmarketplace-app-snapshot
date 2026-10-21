// lib/widgets/notification_bell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/client.dart';
import '../providers/auth_provider.dart';

final unreadNotificationsProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final res = await ApiClient.instance.get('/api/v1/notifications/unread_count');
    return res.data['unread_count'] ?? 0;
  } catch (_) {
    return 0;
  }
});

class NotificationBell extends ConsumerWidget {
  const NotificationBell({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.valueOrNull;
    final isLoggedIn = user != null;

    // Guest – simple person icon
    if (!isLoggedIn) {
      return IconButton(
        onPressed: () => Navigator.pushNamed(context, '/login'),
        icon: const Icon(Icons.person_outline, size: 24),
        color: Colors.black87,
        splashRadius: 20,
      );
    }

    // Logged in – clean notification bell with optional badge
    final unreadAsync = ref.watch(unreadNotificationsProvider);
    final unreadCount = unreadAsync.value ?? 0;

    return IconButton(
      onPressed: () {
        Navigator.pushNamed(context, '/notifications').then((_) {
          ref.invalidate(unreadNotificationsProvider);
        });
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            unreadCount > 0 ? Icons.notifications_active : Icons.notifications_outlined,
            size: 24,
          ),
          if (unreadCount > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      color: Colors.black87,
      splashRadius: 20,
    );
  }
}