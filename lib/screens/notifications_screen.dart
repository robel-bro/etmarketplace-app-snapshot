// 📁 lib/screens/notifications_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/client.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'product_detail_screen.dart';
import 'order_tracking_screen.dart';
import 'invoice_screen.dart';

// ─── Notification model (unchanged) ──
class NotificationItem {
  final int id;
  final String title;
  final String body;
  final String type;
  final bool read;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.read,
    this.metadata,
    required this.createdAt,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) => NotificationItem(
        id: json['id'],
        title: json['title'] ?? '',
        body: json['body'] ?? '',
        type: json['notification_type'] ?? '',
        read: json['read'] ?? false,
        metadata: json['metadata'] as Map<String, dynamic>?,
        createdAt: DateTime.parse(json['created_at']),
      );

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inDays > 7) return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  String get category {
    switch (type) {
      case 'new_order':
      case 'order_placed':
      case 'order_delivered':
        return 'order';
      case 'order_shipped':
        return 'shipping';
      case 'flash_deal':
      case 'super_deal':
      case 'hot_deal':
      case 'new_arrival':
      case 'new_collection':
        return 'promotion';
      case 'payout_paid':
        return 'receipt';
      default:
        return 'order';
    }
  }

  String get subject {
    if (type == 'flash_deal' || type == 'super_deal' || type == 'hot_deal' || type == 'new_arrival') {
      final name = metadata?['product_name'] ?? '';
      final price = metadata?['price'] != null ? 'ETB ${metadata!['price']}' : '';
      final discount = metadata?['discount'] != null ? '${metadata!['discount']}% OFF' : '';
      return [name, price, discount].where((s) => s.isNotEmpty).join(' • ');
    }
    if (type == 'order_placed' || type == 'order_shipped' || type == 'order_delivered') {
      return 'Order #${metadata?['order_id'] ?? ''}';
    }
    if (type == 'new_order') {
      return 'Order #${metadata?['order_id'] ?? ''} • ${metadata?['product_name'] ?? ''}';
    }
    if (type == 'payout_paid') {
      return 'Payout of ETB ${metadata?['amount'] ?? ''}';
    }
    return body;
  }

  String? get orderId => metadata?['order_id']?.toString();
  String? get productName => metadata?['product_name']?.toString();
  double? get price => metadata?['price']?.toDouble();
  double? get originalPrice => metadata?['original_price']?.toDouble();
  int? get discount => metadata?['discount_percentage'] ?? metadata?['discount'];
  int? get soldCount => metadata?['sold_count'];
  double? get rating => metadata?['rating']?.toDouble();
  String? get imageUrl => metadata?['image_url']?.toString();
  double? get amount {
    final a = metadata?['amount'] ?? metadata?['price'];
    return a?.toDouble();
  }
}

// ─── Reusable avatar widget (fixed substring crash) ──
class _NotificationAvatar extends StatelessWidget {
  final NotificationItem item;
  final double size;
  const _NotificationAvatar({required this.item, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final img = item.imageUrl;
    if (img != null && img.isNotEmpty) {
      return ClipOval(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200, width: 2),
            shape: BoxShape.circle,
          ),
          child: Image.network(img, width: size, height: size, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _initialsWidget(item.title)),
        ),
      );
    }
    return _initialsWidget(item.title);
  }

  Widget _initialsWidget(String name) {
    final initialsRaw = name.split(' ').map((e) => e.isNotEmpty ? e[0] : '').join().toUpperCase();
    final initials = initialsRaw.length >= 2 ? initialsRaw.substring(0, 2) : initialsRaw;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryActive],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: -0.2),
      ),
    );
  }
}

// ─── Main Notifications Screen ──
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationItem> _notifications = [];
  bool _isLoading = true;
  int _previousCount = 0;
  String _searchQuery = '';
  bool _showSearch = false;
  String _filterCategory = 'all';
  final Set<int> _starredIds = {};

  @override
  void initState() {
    super.initState();
    if (ApiClient.hasToken) _fetchNotifications();
    else setState(() => _isLoading = false);
  }

  Future<void> _fetchNotifications() async {
    if (!ApiClient.hasToken) return;
    try {
      final res = await ApiClient.instance.get('/api/v1/notifications');
      final List data = (res.data is List)
          ? res.data
          : ((res.data?['notifications'] ?? res.data?['data'] ?? []) as List);
      final newNotifs = data.map((j) => NotificationItem.fromJson(j)).toList();
      if (newNotifs.length > _previousCount && _previousCount > 0) {
        await SystemSound.play(SystemSoundType.click);
      }
      setState(() {
        _notifications = newNotifs;
        _previousCount = newNotifs.length;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markRead(int id) async {
    try {
      await ApiClient.instance.patch('/api/v1/notifications/$id/read');
      setState(() {
        final idx = _notifications.indexWhere((n) => n.id == id);
        if (idx != -1) {
          final old = _notifications[idx];
          _notifications[idx] = NotificationItem(
            id: old.id,
            title: old.title,
            body: old.body,
            type: old.type,
            read: true,
            metadata: old.metadata,
            createdAt: old.createdAt,
          );
        }
      });
    } catch (_) {}
  }

  void _toggleStar(int id) =>
      setState(() => _starredIds.contains(id) ? _starredIds.remove(id) : _starredIds.add(id));

  void _navigateFromNotification(NotificationItem item) {
    if (!item.read) _markRead(item.id);
    final orderId = item.orderId;
    switch (item.type) {
      case 'promotion':
      case 'flash_deal_started':
      case 'new_collection':
      case 'price_drop_alert':
      case 'new_arrival':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NotificationDetailScreen(
              notification: item,
              isStarred: _starredIds.contains(item.id),
              onToggleStar: () => _toggleStar(item.id),
            ),
          ),
        );
        break;
      case 'order_placed':
      case 'order_accepted':
      case 'order_shipped':
      case 'order_delivered':
      case 'order_auto_cancelled':
      case 'order_rejected_by_seller':
      case 'shipment_created':
      case 'shipment_updated':
      case 'delivery_accepted':
        if (orderId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OrderTrackingScreen(orderId: int.parse(orderId)),
            ),
          );
        }
        break;
      default:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NotificationDetailScreen(
              notification: item,
              isStarred: _starredIds.contains(item.id),
              onToggleStar: () => _toggleStar(item.id),
            ),
          ),
        );
    }
  }

  List<NotificationItem> get filteredEmails {
    var list = _notifications;
    if (_filterCategory == 'starred') {
      list = list.where((e) => _starredIds.contains(e.id)).toList();
    } else if (_filterCategory != 'all') {
      list = list.where((e) => e.category == _filterCategory).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((e) =>
              e.title.toLowerCase().contains(q) ||
              e.subject.toLowerCase().contains(q) ||
              e.body.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  int get unreadCount => _notifications.where((n) => !n.read).length;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF3E0),
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        title: Text(
          l10n.translate('notifications_title'),
          style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        ),
        actions: [
          if (_notifications.any((n) => !n.read))
            TextButton(
              onPressed: () {
                for (final n in _notifications.where((n) => !n.read)) {
                  _markRead(n.id);
                }
              },
              child: Text(
                l10n.translate('notifications_mark_all_read'),
                style: theme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.primary,
                ),
              ),
            ),
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search, color: AppColors.textPrimary),
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) _searchQuery = '';
            }),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                if (_showSearch) _buildSearchBar(theme, l10n),
                _buildCategoryFilters(theme, l10n),
                _buildCountRow(theme, l10n),
                Expanded(
                  child: filteredEmails.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inbox_rounded,
                                  size: 64, color: AppColors.textMuted.withOpacity(0.3)),
                              const SizedBox(height: 12),
                              Text(
                                _filterCategory == 'starred'
                                    ? l10n.translate('notifications_empty_starred')
                                    : l10n.translate('notifications_empty'),
                                style: theme.bodyLarge?.copyWith(color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchNotifications,
                          color: AppColors.primary,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                            separatorBuilder: (_, __) => const SizedBox(height: 4),
                            itemCount: filteredEmails.length,
                            itemBuilder: (_, i) =>
                                _notificationCard(filteredEmails[i], theme, l10n),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  String _formatETB(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final integerPart = parts[0].replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
    return 'ETB $integerPart.${parts[1]}';
  }

  Widget _buildSearchBar(TextTheme theme, AppLocalizations l10n) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
        child: TextField(
          autofocus: true,
          onChanged: (v) => setState(() => _searchQuery = v),
          style: theme.bodyMedium?.copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: l10n.translate('notifications_search_hint'),
            hintStyle: theme.bodySmall?.copyWith(color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.hoverState,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppShapes.radiusSm),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _searchQuery = ''),
                  )
                : null,
          ),
        ),
      );

  Widget _buildCategoryFilters(TextTheme theme, AppLocalizations l10n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        color: AppColors.cardBackground,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip(l10n.translate('notifications_filter_all'), 'all', theme),
              const SizedBox(width: 18),
              _filterChip(l10n.translate('notifications_filter_orders'), 'order', theme),
              const SizedBox(width: 18),
              _filterChip(l10n.translate('notifications_filter_shipping'), 'shipping', theme),
              const SizedBox(width: 18),
              _filterChip(l10n.translate('notifications_filter_receipts'), 'receipt', theme),
              const SizedBox(width: 18),
              _filterChip(l10n.translate('notifications_filter_deals'), 'promotion', theme),
              const SizedBox(width: 18),
              _filterChip(l10n.translate('notifications_filter_starred'), 'starred', theme),
            ],
          ),
        ),
      );

  Widget _filterChip(String label, String category, TextTheme theme) {
    final isActive = _filterCategory == category;
    return GestureDetector(
      onTap: () => setState(() => _filterCategory = category),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(
          label,
          style: theme.bodyMedium?.copyWith(
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildCountRow(TextTheme theme, AppLocalizations l10n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        color: AppColors.productListBackground,
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      l10n.translate('notifications_count_new').replaceAll('{count}', '$unreadCount'),
                      style: theme.bodySmall?.copyWith(color: AppColors.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Flexible(
                    child: Text(
                      l10n.translate('notifications_count_starred').replaceAll('{count}', '${_starredIds.length}'),
                      style: theme.bodySmall?.copyWith(color: AppColors.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              l10n.translate('notifications_count_total').replaceAll('{count}', '${filteredEmails.length}'),
              style: theme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      );

  // ── Notification Card – date top‑right, star centred right, tap restored ──
  Widget _notificationCard(NotificationItem notif, TextTheme theme, AppLocalizations l10n) {
    final unread = !notif.read;
    final isStarred = _starredIds.contains(notif.id);
    final catColor = _catColor(notif.category);

    return Dismissible(
      key: Key('${notif.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async =>
          await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.translate('notifications_delete_title')),
          content: Text(l10n.translate('notifications_delete_message')),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: BorderSide(color: AppColors.borderLight),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(l10n.translate('notifications_cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(l10n.translate('notifications_delete')),
            ),
          ],
        ),
      ) ?? false,
      onDismissed: (_) {
        ApiClient.instance.delete('/api/v1/notifications/${notif.id}');
        setState(() => _notifications.remove(notif));
      },
      child: GestureDetector(
        onTap: () => _navigateFromNotification(notif),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (unread)
                      Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(AppShapes.radiusMd),
                            bottomLeft: Radius.circular(AppShapes.radiusMd),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: AppSpacing.xs,
                          top: AppSpacing.sm,
                          bottom: AppSpacing.sm,
                          right: 40, // space for date + star
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _NotificationAvatar(item: notif),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    notif.title,
                                    style: theme.titleMedium?.copyWith(
                                      fontSize: 15,
                                      fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                                      color: AppColors.textPrimary,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          color: catColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          notif.subject,
                                          style: theme.bodySmall?.copyWith(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: unread ? AppColors.textPrimary : AppColors.textMuted,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (notif.body.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      notif.body,
                                      style: theme.bodySmall?.copyWith(
                                        fontSize: 12,
                                        color: AppColors.textMuted,
                                        height: 1.35,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  if (notif.orderId != null || notif.amount != null) ...[
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        if (notif.orderId != null) ...[
                                          Flexible(
                                            child: Text(
                                              notif.orderId!,
                                              style: theme.bodySmall?.copyWith(
                                                fontSize: 12,
                                                color: AppColors.textMuted,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        if (notif.amount != null)
                                          Flexible(
                                            child: Text(
                                              _formatETB(notif.amount!),
                                              style: theme.bodyMedium?.copyWith(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: AppColors.textPrimary,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Date – top‑right corner
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.xs,
              child: Text(
                notif.timeAgo,
                style: theme.bodySmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            // Star – vertically centred on the right
            Positioned(
              right: AppSpacing.xs,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.center,
                child: GestureDetector(
                  onTap: () => _toggleStar(notif.id),
                  child: Icon(
                    isStarred ? Icons.star : Icons.star_border,
                    size: 22,
                    color: isStarred ? AppColors.starGold : AppColors.textMuted,
                  ),
                ),
              ),
            ),
            // Unread dot – below date
            if (unread)
              Positioned(
                top: AppSpacing.sm + 16,
                right: AppSpacing.xs + 14,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _catColor(String cat) {
    switch (cat) {
      case 'order': return Colors.orange;
      case 'shipping': return AppColors.info;
      case 'receipt': return AppColors.success;
      case 'promotion': return AppColors.error;
      default: return AppColors.textMuted;
    }
  }
}

// ─── Detail Screen (unchanged, lighter weights) ──
class NotificationDetailScreen extends StatelessWidget {
  final NotificationItem notification;
  final bool isStarred;
  final VoidCallback onToggleStar;

  const NotificationDetailScreen({
    Key? key,
    required this.notification,
    required this.isStarred,
    required this.onToggleStar,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final isOrder = notification.category == 'order' || notification.category == 'shipping';

    return Scaffold(
      backgroundColor: const Color(0xFFFFF3E0),
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.translate('notifications_detail_title'),
          style: theme.titleMedium?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isStarred ? Icons.star : Icons.star_border,
              color: isStarred ? AppColors.starGold : AppColors.textPrimary,
            ),
            onPressed: onToggleStar,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(theme),
                  if (notification.imageUrl != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _buildImageBlock(theme),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  _buildMetadataRow(theme, l10n),
                  const SizedBox(height: AppSpacing.md),
                  _buildBody(theme),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (isOrder || notification.category == 'promotion')
              _buildActionButtons(context, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(TextTheme theme) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NotificationAvatar(item: notification),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  style: theme.titleMedium?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notification.subject,
                  style: theme.bodySmall?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  notification.timeAgo,
                  style: theme.bodySmall?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _buildImageBlock(TextTheme theme) => ClipRRect(
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            children: [
              Image.network(
                notification.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: AppColors.hoverState),
              ),
              if (notification.discount != null && notification.discount! > 0)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '-${notification.discount}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _buildMetadataRow(TextTheme theme, AppLocalizations l10n) {
    final cat = notification.category;
    final badgeText = cat == 'promotion'
        ? l10n.translate('notifications_new_arrival_badge')
        : l10n.translate('notifications_flash_deal_badge');
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: cat == 'promotion'
                ? AppColors.primary.withOpacity(0.1)
                : AppColors.error.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            badgeText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cat == 'promotion' ? AppColors.primary : AppColors.error,
            ),
          ),
        ),
        const Spacer(),
        if (notification.soldCount != null && notification.soldCount! > 0)
          Text(
            l10n.translate('notifications_sold_count').replaceAll('{count}', '${notification.soldCount}'),
            style: theme.bodySmall?.copyWith(fontSize: 12, color: AppColors.textMuted),
          ),
        if (notification.rating != null) ...[
          const SizedBox(width: 8),
          Icon(Icons.star, size: 16, color: Colors.amber),
          const SizedBox(width: 2),
          Text('${notification.rating}', style: theme.bodyMedium?.copyWith(fontSize: 12)),
        ],
      ],
    );
  }

  Widget _buildBody(TextTheme theme) {
    if (notification.price != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ETB ${notification.price!.toStringAsFixed(2)}',
                style: theme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (notification.originalPrice != null &&
                  notification.originalPrice! > notification.price!) ...[
                const SizedBox(width: 8),
                Text(
                  'ETB ${notification.originalPrice!.toStringAsFixed(2)}',
                  style: theme.bodySmall?.copyWith(
                    fontSize: 12,
                    decoration: TextDecoration.lineThrough,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            notification.body,
            style: theme.bodyMedium?.copyWith(fontSize: 13, color: AppColors.textPrimary, height: 1.55),
          ),
        ],
      );
    }
    return Text(
      notification.body,
      style: theme.bodyMedium?.copyWith(fontSize: 13, color: AppColors.textPrimary, height: 1.55),
    );
  }

  Widget _buildActionButtons(BuildContext context, AppLocalizations l10n) {
    final orderId = notification.orderId;
    final bool hasOrder = orderId != null &&
        (notification.category == 'order' || notification.category == 'shipping');
    final bool hasProduct =
        notification.metadata?['product_id'] != null ||
            notification.metadata?['collection_id'] != null ||
            notification.type == 'flash_deal_started';

    if (!hasOrder && !hasProduct) return const SizedBox.shrink();

    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(42),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
      elevation: 0,
    );

    if (hasOrder && hasProduct) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OrderTrackingScreen(orderId: int.parse(orderId!)),
                ),
              ),
              icon: const Icon(Icons.local_shipping, size: 18, color: Colors.white),
              label: Text(l10n.translate('notifications_track_package'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              style: buttonStyle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _navigateToProduct(context),
              icon: const Icon(Icons.shopping_bag, size: 18, color: Colors.white),
              label: Text(l10n.translate('notifications_shop_now'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              style: buttonStyle,
            ),
          ),
        ],
      );
    }

    if (hasOrder) {
      return ElevatedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: int.parse(orderId!))),
        ),
        icon: const Icon(Icons.local_shipping, size: 18, color: Colors.white),
        label: Text(l10n.translate('notifications_track_package'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        style: buttonStyle,
      );
    }

    return ElevatedButton.icon(
      onPressed: () => _navigateToProduct(context),
      icon: const Icon(Icons.shopping_bag, size: 18, color: Colors.white),
      label: Text(l10n.translate('notifications_shop_now'),
          style: const TextStyle(fontWeight: FontWeight.w600)),
      style: buttonStyle,
    );
  }

  void _navigateToProduct(BuildContext context) {
    if (notification.metadata?['product_id'] != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(productId: int.parse('${notification.metadata!['product_id']}')),
        ),
      );
    } else if (notification.metadata?['collection_id'] != null) {
      Navigator.pushNamed(context, '/collection-detail',
          arguments: '${notification.metadata!['collection_id']}');
    } else if (notification.type == 'flash_deal_started') {
      Navigator.pushNamed(context, '/flash-deals');
    }
  }
}