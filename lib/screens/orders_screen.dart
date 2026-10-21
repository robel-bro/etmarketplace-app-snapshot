// 📁 lib/screens/orders_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/client.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'order_tracking_screen.dart';
import 'invoice_screen.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({Key? key}) : super(key: key);
  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  List<Order> _orders = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (ApiClient.hasToken) {
      _fetchOrders();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchOrders() async {
    if (!ApiClient.hasToken) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      final res = await ApiClient.instance.get('/orders');
      final List data;
      if (res.data is Map && res.data['data'] != null) {
        data = res.data['data'] as List;
      } else if (res.data is List) {
        data = res.data as List;
      } else {
        data = [];
      }
      _orders = data.map((json) => Order.fromJson(json)).toList();
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = AppLocalizations.of(context).translate('error_fetching_orders');
      });
    }
  }

  String formatETB(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final integerPart = parts[0].replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
    return 'ETB $integerPart.${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    Future<bool> _onWillPop() async {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
      }
      return false;
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          toolbarHeight: 44,
          automaticallyImplyLeading: true,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF7A00), Color(0xFFD84315)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          elevation: 0,
          iconTheme: const IconThemeData(color: AppColors.white),
          title: Text(
            l10n.translate('my_orders'),
            style: textTheme.titleMedium?.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(Icons.receipt_long_rounded,
                  color: AppColors.white.withOpacity(0.9), size: 20),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        l10n.translate('error_prefix').replaceAll('{message}', _error!),
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  )
                : _orders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 64,
                                color: AppColors.textMuted.withOpacity(0.4)),
                            const SizedBox(height: 16),
                            Text(
                              l10n.translate('no_orders_yet'),
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, AppSpacing.sm, 8, AppSpacing.xl),
                        itemCount: _orders.length,
                        itemBuilder: (context, index) => _buildOrderCard(_orders[index], l10n),
                      ),
      ),
    );
  }

  Widget _buildOrderCard(Order order, AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;

    Color statusColor;
    switch (order.status) {
      case 'delivered':
      case 'completed':
        statusColor = AppColors.success;
        break;
      case 'shipped':
        statusColor = AppColors.info;
        break;
      case 'processing':
      case 'accepted':
        statusColor = AppColors.primary;
        break;
      case 'pending_acceptance':
      case 'pending':
        statusColor = AppColors.warning;
        break;
      case 'cancelled':
        statusColor = AppColors.error;
        break;
      default:
        statusColor = AppColors.textMuted;
    }

    final primaryProduct = order.items.isNotEmpty ? order.items.first.title : '${l10n.translate("order_prefix")}${order.id}';
    final shippingCost = order.consolidatedShipping > 0
        ? order.consolidatedShipping
        : order.shippingCost;

    final itemsWidgets = order.items.map((item) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppShapes.radiusSm),
            child: Image.network(
              item.imageUrl ?? '',
              width: 48, height: 48, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: AppColors.hoverState,
                  borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                ),
                child: const Icon(Icons.image_outlined, size: 22, color: Colors.black26),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.title,
              style: textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text('x${item.quantity}',
              style: textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              )),
          const SizedBox(width: 8),
          Text(
            formatETB(item.price),
            style: textTheme.bodyMedium?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    )).toList();

    final cardDecoration = BoxDecoration(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(AppShapes.radiusMd),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        clipBehavior: Clip.none,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: order.id)),
          ),
          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
          splashColor: Colors.black.withOpacity(0.05),
          highlightColor: Colors.black.withOpacity(0.02),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: cardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        primaryProduct,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(status: order.status, color: statusColor),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${l10n.translate("order_prefix")}${order.id}  •  ${order.date}',
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                if (order.status == 'pending_acceptance' && order.acceptanceDeadline != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: _CountdownChip(deadline: order.acceptanceDeadline!, l10n: l10n),
                  ),
                const SizedBox(height: 8),
                ...itemsWidgets,
                const SizedBox(height: 6),
                if (order.deliveryRequests.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.local_shipping, size: 14, color: AppColors.info),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _deliveryText(order, l10n),
                            style: textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: AppColors.info,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // ★ Return Policy Card ★
                if (order.returnWindowDays != null)
                  _buildReturnPolicyCard(order, textTheme, l10n),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      order.items.length == 1
                          ? '${order.items.length} ${l10n.translate("item_singular")}'
                          : '${order.items.length} ${l10n.translate("item_plural")}',
                      style: textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    if (shippingCost > 0)
                      Text(
                        '${l10n.translate("delivery_fee")}: ${formatETB(shippingCost)}',
                        style: textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => OrderInvoiceScreen(orderId: order.id)),
                        );
                      },
                      icon: const Icon(Icons.receipt_outlined, size: 16),
                      label: Text(l10n.translate('invoice'), style: const TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    RichText(
                      text: TextSpan(
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                        children: [
                          TextSpan(text: '${l10n.translate('total')}: '),
                          TextSpan(
                            text: formatETB(order.total),
                            style: textTheme.titleMedium?.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReturnPolicyCard(Order order, TextTheme textTheme, AppLocalizations l10n) {
    final deadline = order.returnDeadline ??
        (order.deliveredAt != null
            ? order.deliveredAt!.add(Duration(days: order.returnWindowDays!))
            : null);
    final bool isEligible = order.isReturnEligible;
    final int? daysLeft = order.returnDaysLeft;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.undo, size: 16, color: AppColors.info),
              const SizedBox(width: 6),
              Text(
                'Return Policy',
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.info,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Window: ${order.returnWindowDays} days after delivery',
            style: textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
          if (order.restockingFeePercent != null && order.restockingFeePercent! > 0)
            Text(
              'Restocking fee: ${order.restockingFeePercent!.toStringAsFixed(0)}%',
              style: textTheme.bodySmall?.copyWith(fontSize: 11, color: AppColors.textPrimary),
            ),
          if (order.returnShippingResponsibility != null)
            Text(
              'Return shipping by: ${order.returnShippingResponsibility}',
              style: textTheme.bodySmall?.copyWith(fontSize: 11, color: AppColors.textPrimary),
            ),
          if (deadline != null)
            Text(
              'Deadline: ${_formatDate(deadline)}',
              style: textTheme.bodySmall?.copyWith(fontSize: 11, color: AppColors.textPrimary),
            ),
          if (isEligible && daysLeft != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (order.hasActiveReturnRequest)
                    Text(
                      'Return request sent (${order.activeReturnRequest?['status'] ?? 'pending'})',
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.info,
                        fontSize: 12,
                      ),
                    )
                  else ...[
                    Text(
                      '$daysLeft day${daysLeft == 1 ? '' : 's'} left',
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 30,
                      child: ElevatedButton(
                        onPressed: () => _requestReturn(order.id),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                          ),
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        child: const Text('Request Return'),
                      ),
                    ),
                  ],
                ],
              ),
            )
          else if (!isEligible && order.status == 'delivered')
            const Text(
              'Return window closed',
              style: TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _requestReturn(int orderId) {
    showDialog(
      context: context,
      builder: (_) => _ReturnRequestDialog(orderId: orderId, onSuccess: _fetchOrders),
    );
  }

  String _deliveryText(Order order, AppLocalizations l10n) {
    final dr = order.deliveryRequests.first;
    final status = dr.status.replaceAll('_', ' ');
    final partner = dr.logisticsPartner != null ? ' by ${dr.logisticsPartner!.name}' : '';
    return l10n.translate('delivery_label')
        .replaceAll('{status}', status)
        .replaceAll('{partner}', partner);
  }
}

class _ReturnRequestDialog extends StatefulWidget {
  final int orderId;
  final VoidCallback onSuccess;
  const _ReturnRequestDialog({required this.orderId, required this.onSuccess});

  @override
  _ReturnRequestDialogState createState() => _ReturnRequestDialogState();
}

class _ReturnRequestDialogState extends State<_ReturnRequestDialog> {
  String _reason = '';
  String _details = '';
  bool _saving = false;

  Future<void> _submit() async {
    if (_reason.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ApiClient.instance.post('/return_requests', data: {
        'order_id': widget.orderId,
        'reason': _reason,
        'details': _details,
      });
      widget.onSuccess();
      Navigator.pop(context);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit return request')),
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request Return'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _reason.isEmpty ? null : _reason,
            items: ['defective', 'damaged', 'wrong_item', 'not_as_described', 'change_of_mind', 'other']
                .map((r) => DropdownMenuItem(value: r, child: Text(r.replaceAll('_', ' '))))
                .toList(),
            onChanged: (v) => setState(() => _reason = v ?? ''),
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(labelText: 'Details (optional)'),
            maxLines: 3,
            onChanged: (v) => _details = v,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Submit'),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final Color color;
  const _StatusBadge({required this.status, required this.color});

  String _friendlyStatus(String backendStatus) {
    switch (backendStatus) {
      case 'pending':
      case 'pending_acceptance':
        return 'Order Placed';
      case 'accepted':
      case 'processing':
        return 'Accepted';
      case 'shipped':
        return 'On the Way';
      case 'delivered':
      case 'completed':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      default:
        return backendStatus.replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 5),
        Text(
          _friendlyStatus(status),
          style: textTheme.bodySmall?.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _CountdownChip extends StatelessWidget {
  final DateTime deadline;
  final AppLocalizations l10n;
  const _CountdownChip({required this.deadline, required this.l10n});
  @override
  Widget build(BuildContext context) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) {
      return Text(
        l10n.translate('expired'),
        style: const TextStyle(
          color: AppColors.error,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      );
    }
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    return Text(
      l10n.translate('time_left')
          .replaceAll('{hours}', hours.toString())
          .replaceAll('{minutes}', minutes.toString()),
      style: const TextStyle(
        color: AppColors.primary,
        fontWeight: FontWeight.w700,
        fontSize: 10,
      ),
    );
  }
}