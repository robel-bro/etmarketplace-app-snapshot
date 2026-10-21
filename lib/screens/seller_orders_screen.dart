// 📁 lib/screens/seller_orders_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'invoice_screen.dart';

class SellerOrdersScreen extends StatefulWidget {
  const SellerOrdersScreen({Key? key}) : super(key: key);
  @override
  State<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends State<SellerOrdersScreen> {
  List<Map<String, dynamic>> _allOrders = [];
  List<Map<String, dynamic>> _filteredOrders = [];
  bool _isLoading = true;
  String? _error;

  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'all';
  String _sortBy = 'newest';

  // ★ Auto-refresh timer
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    if (ApiClient.hasToken) {
      _fetchOrders();
      _startAutoRefresh();
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ★ Start periodic silent refresh every 30 seconds
  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _fetchOrders(silent: true),
    );
  }

  // ★ Fetch orders; if silent = true, don't show full-screen loading
  Future<void> _fetchOrders({bool silent = false}) async {
    if (!ApiClient.hasToken) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (!silent && mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final res = await ApiClient.instance.get('/seller/orders');
      final List data = res.data is List ? res.data : (res.data['data'] ?? []);
      final List<Map<String, dynamic>> loadedOrders =
          data.map((o) => Map<String, dynamic>.from(o)).toList();
      if (!mounted) return;
      setState(() {
        _allOrders = loadedOrders;
        if (!silent) _isLoading = false;
        _applyFilters();
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _error = AppLocalizations.of(context).translate('error_fetching_orders');
          _isLoading = false;
        });
      }
      // If silent refresh fails, ignore; next timer will retry
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    var filtered = _allOrders.where((o) {
      final id = o['id'].toString();
      final buyer = (o['buyer_name'] ?? '').toLowerCase();
      final address = (o['shipping_address'] ?? '').toLowerCase();
      final items = (o['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final itemTitles = items.map((item) => (item['title'] ?? '').toLowerCase()).join(' ');
      final matchesSearch = query.isEmpty ||
          id.contains(query) ||
          buyer.contains(query) ||
          address.contains(query) ||
          itemTitles.contains(query);
      final status = o['status'] ?? '';
      final matchesStatus = _statusFilter == 'all' || status == _statusFilter;
      return matchesSearch && matchesStatus;
    }).toList();

    switch (_sortBy) {
      case 'oldest':
        filtered.sort((a, b) => (a['created_at'] ?? '').compareTo(b['created_at'] ?? ''));
        break;
      case 'highest':
        filtered.sort((a, b) => (double.tryParse(b['total']?.toString() ?? '0') ?? 0)
            .compareTo(double.tryParse(a['total']?.toString() ?? '0') ?? 0));
        break;
      case 'lowest':
        filtered.sort((a, b) => (double.tryParse(a['total']?.toString() ?? '0') ?? 0)
            .compareTo(double.tryParse(b['total']?.toString() ?? '0') ?? 0));
        break;
      case 'newest':
      default:
        filtered.sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
        break;
    }

    setState(() => _filteredOrders = filtered);
  }

  Future<void> _acceptOrder(int orderId) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ApiClient.instance.post('/seller/orders/$orderId/accept');
      _fetchOrders(); // refresh immediately
      _showSnack(l10n.translate('order_accepted').replaceAll('{id}', orderId.toString()), AppColors.success);
    } catch (e) {
      _showSnack(l10n.translate('accept_failed'), AppColors.error);
    }
  }

  Future<void> _rejectOrder(int orderId) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ApiClient.instance.post('/seller/orders/$orderId/reject');
      _fetchOrders();
      _showSnack(l10n.translate('order_rejected').replaceAll('{id}', orderId.toString()), AppColors.success);
    } catch (e) {
      _showSnack(l10n.translate('reject_failed'), AppColors.error);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderDetailsSheet(
        order: order,
        onAccept: () => _acceptOrder(order['id']),
        onReject: () => _rejectOrder(order['id']),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      color: AppColors.pageBackground,
      child: Column(
        children: [
          Container(
            color: AppColors.cardBackground,
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => _applyFilters(),
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: l10n.translate('search_orders_hint'),
                          hintStyle: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                          prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textMuted),
                          filled: true,
                          fillColor: AppColors.hoverState,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _SortButton(
                      currentSort: _sortBy,
                      onSelected: (value) {
                        setState(() => _sortBy = value);
                        _applyFilters();
                      },
                      l10n: l10n,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _filterChip(l10n.translate('filter_all'), 'all'),
                      const SizedBox(width: AppSpacing.xs),
                      _filterChip(l10n.translate('filter_pending_payment'), 'pending'),
                      const SizedBox(width: AppSpacing.xs),
                      _filterChip(l10n.translate('filter_pending_accept'), 'pending_acceptance'),
                      const SizedBox(width: AppSpacing.xs),
                      _filterChip(l10n.translate('filter_accepted'), 'accepted'),
                      const SizedBox(width: AppSpacing.xs),
                      _filterChip(l10n.translate('filter_processing'), 'processing'),
                      const SizedBox(width: AppSpacing.xs),
                      _filterChip(l10n.translate('filter_delivered'), 'delivered'),
                      const SizedBox(width: AppSpacing.xs),
                      _filterChip(l10n.translate('filter_cancelled'), 'cancelled'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: AppColors.productListBackground,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
                  : _error != null
                      ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(_error!, style: textTheme.bodyLarge?.copyWith(color: AppColors.error))))
                      : _filteredOrders.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.inbox_rounded, size: 48, color: AppColors.textMuted.withOpacity(0.4)),
                                  const SizedBox(height: 16),
                                  Text(l10n.translate('no_orders_found'), style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 24),
                              itemCount: _filteredOrders.length,
                              itemBuilder: (context, index) {
                                final order = _filteredOrders[index];
                                return _OrderCard(
                                  order: order,
                                  onTap: () => _showOrderDetails(order),
                                  onAccept: () => _acceptOrder(order['id']),
                                  onReject: () => _rejectOrder(order['id']),
                                  onViewInvoice: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => OrderInvoiceScreen(orderId: order['id']),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final active = _statusFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() => _statusFilter = value);
        _applyFilters();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.hoverState,
          borderRadius: BorderRadius.circular(AppShapes.radiusSm),
          border: Border.all(color: active ? AppColors.primary : AppColors.borderLight, width: 1),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? Colors.white : AppColors.textPrimary)),
      ),
    );
  }
}

// ────────── Helper Widgets (only Accept/Reject & Invoice) ──────────

class _SortButton extends StatelessWidget {
  final String currentSort;
  final ValueChanged<String> onSelected;
  final AppLocalizations l10n;
  const _SortButton({required this.currentSort, required this.onSelected, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      offset: const Offset(0, 48),
      color: AppColors.cardBackground,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusMd), side: const BorderSide(color: AppColors.borderLight)),
      child: Container(
        height: 46,
        width: 46,
        decoration: BoxDecoration(color: AppColors.hoverState, borderRadius: BorderRadius.circular(AppShapes.radiusMd)),
        child: const Icon(Icons.sort_rounded, color: AppColors.textPrimary, size: 20),
      ),
      itemBuilder: (context) => [
        _popupItem('newest', l10n.translate('sort_newest_first'), Icons.arrow_downward_rounded),
        _popupItem('oldest', l10n.translate('sort_oldest_first'), Icons.arrow_upward_rounded),
        _popupItem('highest', l10n.translate('sort_highest_total'), Icons.trending_up_rounded),
        _popupItem('lowest', l10n.translate('sort_lowest_total'), Icons.trending_down_rounded),
      ],
    );
  }

  PopupMenuItem<String> _popupItem(String value, String text, IconData icon) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textPrimary),
          const SizedBox(width: 10),
          Text(text, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (currentSort == value) const Icon(Icons.check, size: 18, color: AppColors.primary),
        ],
      ),
    );
  }
}

String _formatETB(dynamic amount) {
  final double value = (amount is num) ? amount.toDouble() : double.tryParse(amount?.toString() ?? '0') ?? 0.0;
  final parts = value.toStringAsFixed(2).split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (Match m) => '${m[1]},',
  );
  return 'ETB $intPart.${parts[1]}';
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onTap;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onViewInvoice;

  const _OrderCard({
    required this.order,
    required this.onTap,
    required this.onAccept,
    required this.onReject,
    required this.onViewInvoice,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final id = order['id'];
    final customer = order['buyer_name'] ?? '—';
    final createdAt = order['created_at'];
    final date = createdAt != null
        ? (DateTime.tryParse(createdAt.toString())?.toLocal().toString().substring(0, 10) ?? '—')
        : '—';
    final items = (order['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final status = order['status'] ?? 'pending';
    final paymentStatus = order['payment_status'] ?? '';
    final deliveryCost = double.tryParse(order['consolidated_shipping']?.toString() ?? order['shipping_cost']?.toString() ?? '0') ?? 0;
    final deadlineStr = order['acceptance_deadline'];

    double subtotal = 0.0;
    for (final item in items) {
      final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
      final quantity = item['quantity'] ?? 1;
      subtotal += price * quantity;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          splashColor: AppColors.primary.withOpacity(0.05),
          highlightColor: AppColors.primary.withOpacity(0.02),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text('#$id', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        const SizedBox(width: 6),
                        if (paymentStatus == 'refunded')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                            ),
                            child: const Text('Refunded',
                                style: TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                    _StatusBadge(status: status),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                          children: [
                            TextSpan(text: l10n.translate('buyer_label').replaceAll('{name}', customer)),
                            const TextSpan(text: '   '),
                            TextSpan(
                              text: l10n.translate('date_label').replaceAll('{date}', date),
                              style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if ((status == 'pending' || status == 'pending_acceptance') && deadlineStr != null)
                      _CountdownTimer(deadlineStr: deadlineStr, l10n: l10n),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 70,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: items.length > 4 ? 5 : items.length,
                          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
                          itemBuilder: (context, index) {
                            if (index < 4) {
                              final item = items[index];
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                                child: Image.network(
                                  item['image'] ?? '',
                                  width: 70, height: 70, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 70, height: 70,
                                    decoration: BoxDecoration(
                                      color: AppColors.hoverState,
                                      borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                                    ),
                                    child: const Icon(Icons.image_outlined, size: 24, color: AppColors.textMuted),
                                  ),
                                ),
                              );
                            }
                            return Container(
                              width: 70, height: 70,
                              decoration: BoxDecoration(
                                color: AppColors.hoverState,
                                borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                              ),
                              alignment: Alignment.center,
                              child: Text('+${items.length - 4}',
                                  style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${l10n.translate("subtotal")}: ${_formatETB(subtotal)}',
                            style: textTheme.bodySmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w600)),
                        if (deliveryCost > 0)
                          Text('${l10n.translate("delivery_fee")}: ${_formatETB(deliveryCost)}',
                              style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text('${l10n.translate("total")}: ${_formatETB(subtotal + deliveryCost)}',
                            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: _ActionButtons(
                    status: status,
                    onAccept: onAccept,
                    onReject: onReject,
                    onViewInvoice: onViewInvoice,
                    l10n: l10n,
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

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  Color _statusColor() {
    switch (status) {
      case 'pending': case 'pending_acceptance': return Colors.orange;
      case 'accepted': case 'processing': return AppColors.primary;
      case 'shipped': return AppColors.info;
      case 'delivered': case 'completed': return AppColors.success;
      case 'cancelled': case 'returned': return AppColors.error;
      default: return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeStatus = status.isEmpty ? 'unknown' : status;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: _statusColor())),
        const SizedBox(width: 4),
        Text(
          safeStatus[0].toUpperCase() + safeStatus.substring(1).replaceAll('_', ' '),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
      ],
    );
  }
}

class _CountdownTimer extends StatefulWidget {
  final String deadlineStr;
  final AppLocalizations l10n;
  const _CountdownTimer({required this.deadlineStr, required this.l10n});

  @override
  State<_CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<_CountdownTimer> {
  Timer? _timer;
  Duration? _remaining;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }

  void _updateRemaining() {
    final deadline = DateTime.tryParse(widget.deadlineStr);
    if (deadline == null) {
      setState(() => _remaining = null);
      return;
    }
    final remaining = deadline.difference(DateTime.now());
    setState(() => _remaining = remaining.isNegative ? Duration.zero : remaining);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;
    if (remaining == null) return const SizedBox.shrink();
    if (remaining == Duration.zero) {
      return Text(widget.l10n.translate('expired'),
          style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700, fontSize: 11));
    }
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    return Text(
      widget.l10n.translate('time_left').replaceAll('{hours}', hours.toString()).replaceAll('{minutes}', minutes.toString()),
      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 11),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final String status;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onViewInvoice;
  final AppLocalizations l10n;

  const _ActionButtons({
    required this.status,
    required this.onAccept,
    required this.onReject,
    required this.onViewInvoice,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    if (status == 'delivered' || status == 'completed') {
      return _OutlineButton(l10n.translate('invoice'), onTap: onViewInvoice);
    }
    if (status == 'cancelled' || status == 'returned') {
      return const SizedBox.shrink();
    }
    // Accept/Reject for both 'pending' and 'pending_acceptance'
    if (status == 'pending' || status == 'pending_acceptance') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PrimaryButton(l10n.translate('accept'), onTap: onAccept),
          const SizedBox(width: AppSpacing.xs),
          _OutlineButton(l10n.translate('reject'), onTap: onReject),
        ],
      );
    }
    // For accepted, processing, shipped – no seller action needed here
    return const SizedBox.shrink();
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  const _PrimaryButton(this.label, {required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(AppShapes.radiusSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white24,
        highlightColor: Colors.white10,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: Colors.white),
                const SizedBox(width: 4),
              ],
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  const _OutlineButton(this.label, {required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppShapes.radiusSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.primary.withOpacity(0.1),
        highlightColor: AppColors.primary.withOpacity(0.05),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary),
            borderRadius: BorderRadius.circular(AppShapes.radiusSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
              ],
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────── Details Sheet (with Return Info) ──────────
class _OrderDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _OrderDetailsSheet({
    Key? key,
    required this.order,
    required this.onAccept,
    required this.onReject,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final items = (order['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final address = order['shipping_address'] ?? '—';
    final paymentMethod = order['payment_method'] ?? '—';
    final status = order['status'] ?? 'pending';
    final created = order['created_at'];
    final date = created != null
        ? (DateTime.tryParse(created.toString())?.toLocal().toString().substring(0, 16) ?? '')
        : '';
    final deadlineStr = order['acceptance_deadline'];
    final deliveryPin = order['delivery_pin'];
    final returnRequest = order['return_request'] as Map<String, dynamic>?;

    final discount = double.tryParse(order['discount_amount']?.toString() ?? '0') ?? 0;
    final serviceFee = double.tryParse(order['service_fee']?.toString() ?? '0') ?? 0;
    final vat = double.tryParse(order['vat_amount']?.toString() ?? '0') ?? 0;
    final deliveryCost = double.tryParse(order['consolidated_shipping']?.toString() ?? order['shipping_cost']?.toString() ?? '0') ?? 0;

    double subtotal = 0;
    for (final item in items) {
      final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
      final quantity = item['quantity'] ?? 1;
      subtotal += price * quantity;
    }

    final total = subtotal + serviceFee + vat - discount + deliveryCost;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 24, offset: Offset(0, -4))],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 32, height: 4,
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.15), borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 24),
            Text(l10n.translate('order_details_title').replaceAll('{id}', order['id'].toString()),
                style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text('$date  •  ${order['buyer_name'] ?? ''}',
                style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w500)),
            const SizedBox(height: 20),
            if (deliveryPin != null && (status == 'processing' || status == 'shipped'))
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline, size: 16, color: AppColors.success),
                        const SizedBox(width: 6),
                        Text(l10n.translate('delivery_pin'), style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.success)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(deliveryPin, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 6, color: AppColors.success)),
                    const SizedBox(height: 6),
                    Text(l10n.translate('share_pin_message'), textAlign: TextAlign.center, style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
            if (returnRequest != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: AppColors.info),
                        const SizedBox(width: 6),
                        Text('Return Information',
                            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.info)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text('Status: ', style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                        _StatusBadge(status: returnRequest['status'] ?? ''),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Reason: ${returnRequest['reason']?.toString().replaceAll('_', ' ') ?? ''}',
                        style: textTheme.bodySmall?.copyWith(color: AppColors.textPrimary)),
                    if (returnRequest['details'] != null) ...[
                      const SizedBox(height: 2),
                      Text('Details: ${returnRequest['details']}',
                          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                    ],
                    if (returnRequest['liability'] != null) ...[
                      const SizedBox(height: 4),
                      Text('Liability: ${returnRequest['liability']}',
                          style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                    if (returnRequest['return_shipping_cost'] != null &&
                        (double.tryParse(returnRequest['return_shipping_cost'].toString()) ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Penalty: ${_formatETB(returnRequest['return_shipping_cost'])}',
                          style: textTheme.bodySmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w700),
                        ),
                      ),
                    if (returnRequest['admin_notes'] != null) ...[
                      const SizedBox(height: 4),
                      Text('Admin Notes: "${returnRequest['admin_notes']}"',
                          style: textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: AppColors.textMuted)),
                    ],
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.hoverState,
                borderRadius: BorderRadius.circular(AppShapes.radiusMd),
              ),
              child: Column(
                children: [
                  _DetailRow(label: l10n.translate('address'), value: address),
                  const SizedBox(height: 8),
                  _DetailRow(label: l10n.translate('payment'), value: paymentMethod),
                  const SizedBox(height: 8),
                  _DetailRow(
                    label: l10n.translate('status_label'),
                    value: status,
                    isStatusBadge: true,
                  ),
                  if ((status == 'pending' || status == 'pending_acceptance') && deadlineStr != null) ...[
                    const SizedBox(height: 8),
                    _DetailRow(
                      label: l10n.translate('deadline_label'),
                      value: _formatDeadline(deadlineStr, l10n),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(l10n.translate('items_label').replaceAll('{count}', items.length.toString()),
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            ...items.map((item) => _ItemTile(item: item)),
            const SizedBox(height: 16),
            const Divider(color: AppColors.borderLight),
            const SizedBox(height: 16),
            _PriceRow(label: l10n.translate('subtotal'), amount: subtotal, isRed: true),
            if (discount > 0)
              _PriceRow(label: l10n.translate('discount'), amount: discount, isRed: true),
            if (serviceFee > 0)
              _PriceRow(label: l10n.translate('service_fee'), amount: serviceFee),
            if (vat > 0)
              _PriceRow(label: l10n.translate('vat'), amount: vat),
            if (deliveryCost > 0)
              _PriceRow(label: l10n.translate('delivery_fee'), amount: deliveryCost),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.translate('total'), style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                Text(_formatETB(total),
                    style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 24),
            if (status == 'pending' || status == 'pending_acceptance')
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PrimaryButton(l10n.translate('accept'), onTap: onAccept),
                  const SizedBox(width: 12),
                  _OutlineButton(l10n.translate('reject'), onTap: onReject),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _formatDeadline(String deadlineStr, AppLocalizations l10n) {
    final dt = DateTime.tryParse(deadlineStr);
    if (dt == null) return deadlineStr;
    final remaining = dt.difference(DateTime.now());
    if (remaining.isNegative) return l10n.translate('expired');
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    return '${dt.toLocal().toString().substring(0, 16)} (${l10n.translate("time_left").replaceAll("{hours}", hours.toString()).replaceAll("{minutes}", minutes.toString())})';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isStatusBadge;
  final Widget? icon;

  const _DetailRow({
    required this.label,
    required this.value,
    this.isStatusBadge = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 100,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: isStatusBadge
              ? _StatusBadge(status: value)
              : Row(
                  children: [
                    if (icon != null) ...[
                      icon!,
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        value,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final double amount;
  final bool isRed;
  const _PriceRow({required this.label, required this.amount, this.isRed = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w500)),
          Text(
            _formatETB(amount),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: isRed ? AppColors.error : AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final title = item['title'] ?? '';
    final quantity = item['quantity'] ?? 1;
    final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
    final image = item['image'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.hoverState,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppShapes.radiusSm),
            child: Image.network(
              image, width: 56, height: 56, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                ),
                child: const Icon(Icons.image_outlined, size: 24, color: AppColors.textMuted),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('Qty: $quantity', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 16),
                    Text(_formatETB(price), style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}