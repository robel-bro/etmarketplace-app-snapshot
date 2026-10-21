// 📁 lib/screens/order_tracking_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/client.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'invoice_screen.dart';
import 'product_detail_screen.dart';

const String kWebSocketUrl = 'ws://YOUR_BACKEND_HOST/cable';
const String kBaseUrl = 'http://10.0.2.2:3000';

class OrderTrackingScreen extends ConsumerStatefulWidget {
  final int? orderId;
  const OrderTrackingScreen({Key? key, this.orderId}) : super(key: key);

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  final _idController = TextEditingController();
  Order? _order;
  bool _isLoading = false;
  String? _error;
  bool _initialFetchDone = false;

  String _liveStatus = '';
  String _eta = '';
  WebSocketChannel? _channel;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    if (widget.orderId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_initialFetchDone) {
          _initialFetchDone = true;
          _fetchOrder(widget.orderId!);
        }
      });
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _channel?.sink.close();
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchOrder(int id, {bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final res = await ApiClient.instance.get('/orders/$id');
      final order = Order.fromJson(res.data);
      if (mounted) {
        setState(() {
          _order = order;
          _updateLiveFromOrder();
          if (!silent) _isLoading = false;
        });
      }
      if (!silent) _connectWebSocket();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Order not found';
          if (!silent) _isLoading = false;
        });
      }
    }
  }

  void _updateLiveFromOrder() {
    if (_order == null) return;
    _liveStatus = _order!.status;

    if (_order!.estimatedDelivery != null &&
        _order!.estimatedDelivery!.isNotEmpty) {
      final ed = DateTime.tryParse(_order!.estimatedDelivery!);
      if (ed != null) {
        _eta = '${ed.day}/${ed.month}/${ed.year} ${ed.hour}:${ed.minute.toString().padLeft(2, '0')}';
      } else {
        _eta = _order!.estimatedDelivery!;
      }
    } else {
      _eta = 'Calculating...';
    }
  }

  void _connectWebSocket() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(kWebSocketUrl));
      _channel!.sink.add(jsonEncode({
        'command': 'subscribe',
        'identifier': jsonEncode({
          'channel': 'DeliveryChannel',
          'order_id': widget.orderId ?? _order!.id,
        }),
      }));
      _channel!.stream.listen(
        (message) => _handleWebSocketMessage(message),
        onError: (error) => _startPollingFallback(),
        onDone: _startPollingFallback,
      );
    } catch (e) {
      _startPollingFallback();
    }
  }

  void _handleWebSocketMessage(String message) {
    try {
      final data = jsonDecode(message);
      final msg = data['message'] ?? data;
      if (msg is! Map) return;
      setState(() {
        if (msg['status'] != null) _liveStatus = msg['status'];
        if (msg['estimated_delivery'] != null) {
          final ed = DateTime.tryParse(msg['estimated_delivery']);
          if (ed != null) {
            _eta = '${ed.day}/${ed.month}/${ed.year} ${ed.hour}:${ed.minute.toString().padLeft(2, '0')}';
          } else {
            _eta = msg['estimated_delivery'];
          }
        }
      });
    } catch (_) {}
  }

  void _startPollingFallback() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_order != null &&
          _order!.status != 'delivered' &&
          _order!.status != 'cancelled') {
        _fetchOrder(_order!.id, silent: true);
      }
    });
  }

  void _lookup() {
    final text = _idController.text.trim();
    if (text.isEmpty) return;
    final id = int.tryParse(text);
    if (id == null) {
      setState(() => _error = 'Invalid order number');
      return;
    }
    _fetchOrder(id);
  }

  Future<void> _downloadPdf() async {
    if (_order == null) return;
    final url = '$kBaseUrl/orders/${_order!.id}/invoice.pdf';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Card style (flat, white) ──
  BoxDecoration get _cardDecoration => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showLookup = widget.orderId == null && _order == null;
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
                colors: [AppColors.primary, AppColors.primaryActive],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            widget.orderId != null
                ? (_order != null && _order!.items.isNotEmpty
                    ? _order!.items.first.title
                    : '${l10n.translate("track_order_title")} #${widget.orderId}')
                : l10n.translate('track_order_title'),
            style: textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          centerTitle: true,
          actions: [
            if (_order != null) ...[
              IconButton(
                icon: const Icon(Icons.receipt_long_rounded,
                    color: Colors.white, size: 20),
                tooltip: l10n.translate('view_receipt'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => OrderInvoiceScreen(orderId: _order!.id)),
                ),
              ),
              if (_order!.status == 'completed' || _order!.status == 'delivered')
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf,
                      color: Colors.white, size: 20),
                  tooltip: l10n.translate('download_pdf'),
                  onPressed: _downloadPdf,
                ),
            ],
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Icon(
                Icons.local_shipping_rounded,
                color: Colors.white.withOpacity(0.9),
                size: 20,
              ),
            ),
          ],
        ),
        body: showLookup
            ? _buildLookupView(l10n, textTheme)
            : (_isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
                : (_order == null
                    ? Center(child: Text(_error ?? 'Order not found', style: const TextStyle(color: AppColors.error, fontSize: 14)))
                    : _buildOrderDetails(l10n, textTheme))),
      ),
    );
  }

  Widget _buildLookupView(AppLocalizations l10n, TextTheme textTheme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded, size: 48, color: AppColors.textMuted.withOpacity(0.3)),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.translate('enter_order_number'), textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Text(l10n.translate('track_in_real_time'), style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _idController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 15),
              decoration: InputDecoration(
                hintText: l10n.translate('order_id_hint'),
                hintStyle: TextStyle(color: Colors.black.withOpacity(0.3), fontSize: 14, fontWeight: FontWeight.w500),
                filled: true,
                fillColor: AppColors.hoverState,
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppShapes.radiusMd), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppShapes.radiusMd), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_error != null)
              Padding(padding: const EdgeInsets.only(bottom: AppSpacing.xs), child: Text(_error!, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600, fontSize: 13))),
            SizedBox(
              width: double.infinity,
              child: Material(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _isLoading ? null : _lookup,
                  splashColor: Colors.white24,
                  highlightColor: Colors.white10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: _isLoading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Center(child: Text(l10n.translate('track_order_button'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white))),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderDetails(AppLocalizations l10n, TextTheme textTheme) {
    final order = _order!;
    final currentStatus = _liveStatus.isNotEmpty ? _liveStatus : order.status;
    final bool isCancelled = order.status == 'cancelled';
    final bool isDelivered = currentStatus == 'delivered';

    final statusSteps = [
      {'key': 'placed', 'label': l10n.translate('order_placed'), 'icon': Icons.assignment_turned_in_rounded},
      {'key': 'accepted', 'label': l10n.translate('accepted'), 'icon': Icons.verified_user_rounded},
      {'key': 'on_the_way', 'label': l10n.translate('on_the_way'), 'icon': Icons.local_shipping_rounded},
      {'key': 'delivered', 'label': l10n.translate('delivered'), 'icon': Icons.task_alt_rounded},
    ];
    int currentStep;
    switch (currentStatus) {
      case 'pending': case 'pending_acceptance': currentStep = 0; break;
      case 'accepted': case 'processing': currentStep = 1; break;
      case 'shipped': currentStep = 2; break;
      case 'delivered': case 'completed': currentStep = 3; break;
      default: currentStep = 0;
    }

    final subtotal = order.subtotal;
    final discount = order.discountAmount;
    final serviceFee = order.serviceFee;
    final vat = order.vatAmount;
    final shipping = order.consolidatedShipping > 0 ? order.consolidatedShipping : order.shippingCost;
    final total = order.total;

    String fmt(double v) {
      final parts = v.toStringAsFixed(2).split('.');
      final integerPart = parts[0].replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
      return 'ETB $integerPart.${parts[1]}';
    }

    Widget _buildCard({required Widget child, EdgeInsetsGeometry? padding, EdgeInsetsGeometry? margin}) {
      return Container(
        margin: margin ?? const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: padding ?? const EdgeInsets.all(AppSpacing.md),
        decoration: _cardDecoration,
        child: child,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, AppSpacing.sm, 8, AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Delivery PIN
          if (order.deliveryPin != null && (order.status == 'shipped' || order.status == 'processing'))
            _buildCard(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline, size: 16, color: AppColors.success),
                      const SizedBox(width: 6),
                      Text(l10n.translate('delivery_pin'), style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.success)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(order.deliveryPin!, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: 8, color: AppColors.success)),
                  const SizedBox(height: 6),
                  Text(l10n.translate('share_pin_message'), textAlign: TextAlign.center, style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),

          // ETA
          if (!isCancelled && !isDelivered && _eta.isNotEmpty)
            _buildCard(
              child: Row(
                children: [
                  const Icon(Icons.local_shipping_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.translate('estimated_arrival').replaceAll('{eta}', _eta),
                      style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),

          // Progress Tracker
          if (!isCancelled)
            _buildCard(
              child: Row(
                children: statusSteps.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final step = entry.value;
                  final completed = idx <= currentStep;
                  final isCurrent = idx == currentStep;
                  return Expanded(
                    child: Column(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: completed ? AppColors.success : (isCurrent ? AppColors.primary : AppColors.borderLight),
                          ),
                          child: Icon(step['icon'] as IconData, size: 16, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          step['label'] as String,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                            color: completed ? AppColors.success : (isCurrent ? AppColors.primary : AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

          if (isCancelled)
            _buildCard(
              child: Center(
                child: Text(l10n.translate('order_cancelled_message'), style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
              ),
            ),

          // Acceptance deadline
          if (currentStatus == 'pending_acceptance' && order.acceptanceDeadline != null)
            _buildCard(
              child: Row(
                children: [
                  const Icon(Icons.timer, color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.translate('seller_accept_deadline').replaceAll('{deadline}', _formatDeadline(order.acceptanceDeadline!, l10n)),
                      style: textTheme.bodySmall?.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

          // Delivery Partner Info
          if (order.deliveryRequests.isNotEmpty)
            _buildCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Delivery Partner', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Builder(builder: (_) {
                    final dr = order.deliveryRequests.first;
                    final partnerName = dr.logisticsPartner?.name ?? 'Pending assignment';
                    final statusDisplay = dr.status.replaceAll('_', ' ');
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.local_shipping, size: 16, color: AppColors.info),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '$partnerName — $statusDisplay',
                                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                              ),
                            ),
                          ],
                        ),
                        if (dr.events.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ...dr.events.take(3).map((event) {
                            final eventDesc = '${event.status.replaceAll('_', ' ')}${event.location != null ? ' — ${event.location}' : ''}';
                            return Padding(
                              padding: const EdgeInsets.only(left: 22, bottom: 2),
                              child: Row(
                                children: [
                                  Expanded(child: Text(eventDesc, style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary))),
                                  const SizedBox(width: 8),
                                  Text(
                                    DateTime.tryParse(event.timestamp)?.toLocal().toString().substring(11, 16) ?? '',
                                    style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted, fontSize: 11),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                      ],
                    );
                  }),
                ],
              ),
            ),

          // Return Policy Card (always shown if policy exists)
          if (order.returnWindowDays != null)
            _buildReturnPolicyCard(order, textTheme, l10n),

          // Combined Order Items + Payment Summary Card
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.items.isNotEmpty ? order.items.first.title : '${l10n.translate("track_order_title")} #${order.id}',
                        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _StatusBadge(status: currentStatus),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${l10n.translate("track_order_title")} #${order.id}', style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: AppSpacing.sm),
                _InfoRow(icon: Icons.schedule_rounded, text: l10n.translate('placed_label').replaceAll('{date}', order.date)),
                if (order.estimatedDelivery != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _InfoRow(icon: Icons.local_shipping_rounded, text: l10n.translate('estimated_label').replaceAll('{eta}', _eta)),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text(l10n.translate('items_label'), style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: AppSpacing.xs),
                ...order.items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                        child: Image.network(item.imageUrl ?? '', width: 48, height: 48, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(width: 48, height: 48, decoration: BoxDecoration(color: AppColors.hoverState, borderRadius: BorderRadius.circular(AppShapes.radiusSm)), child: const Icon(Icons.image_outlined, size: 22, color: AppColors.textMuted)),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary), maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text('Qty: ${item.quantity}', style: textTheme.bodySmall?.copyWith(fontSize: 12, color: AppColors.textMuted)),
                                const SizedBox(width: AppSpacing.sm),
                                Text(fmt(item.price), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: AppSpacing.md),
                Text('Payment Summary', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _priceRow('Subtotal', subtotal, fmt),
                if (discount > 0) _priceRow('Discount', -discount, fmt, isRed: true),
                if (serviceFee > 0) _priceRow('Service Fee', serviceFee, fmt),
                if (vat > 0) _priceRow('VAT', vat, fmt),
                _priceRow('Delivery Fee', shipping, fmt),
                const SizedBox(height: 8),
                _priceRow('Total', total, fmt, isBold: true),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: Text(l10n.translate('view_receipt')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.borderLight),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusMd)),
                    ),
                    onPressed: () {
                      if (_order != null) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => OrderInvoiceScreen(orderId: _order!.id)));
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
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
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.undo, size: 18, color: AppColors.info),
              const SizedBox(width: 6),
              Text(
                'Return Policy',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Window: ${order.returnWindowDays} days after delivery',
            style: textTheme.bodySmall?.copyWith(color: AppColors.textPrimary),
          ),
          if (order.restockingFeePercent != null && order.restockingFeePercent! > 0)
            Text(
              'Restocking fee: ${order.restockingFeePercent!.toStringAsFixed(0)}%',
              style: textTheme.bodySmall?.copyWith(color: AppColors.textPrimary),
            ),
          if (order.returnShippingResponsibility != null)
            Text(
              'Return shipping by: ${order.returnShippingResponsibility}',
              style: textTheme.bodySmall?.copyWith(color: AppColors.textPrimary),
            ),
          if (deadline != null)
            Text(
              'Deadline: ${_formatDate(deadline)}',
              style: textTheme.bodySmall?.copyWith(color: AppColors.textPrimary),
            ),
          if (isEligible && daysLeft != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  if (order.hasActiveReturnRequest)
                    Text(
                      'Return request sent (${order.activeReturnRequest?['status'] ?? 'pending'})',
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.info,
                      ),
                    )
                  else ...[
                    Text(
                      '$daysLeft day${daysLeft == 1 ? '' : 's'} left',
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () => _requestReturn(order.id),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                        ),
                      ),
                      child: const Text('Request Return'),
                    ),
                  ],
                ],
              ),
            )
          else if (!isEligible && order.status == 'delivered')
            const Text(
              'Return window closed',
              style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
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
      builder: (_) => _ReturnRequestDialog(
        orderId: orderId,
        onSuccess: () {
          if (_order != null) _fetchOrder(_order!.id);
        },
      ),
    );
  }

  Widget _priceRow(String label, double amount, String Function(double) formatter,
      {bool isRed = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textMuted)),
          Text(
            formatter(amount),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                  color: isRed ? Colors.red : AppColors.textPrimary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _InfoRow({required IconData icon, required String text, Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? AppColors.textMuted),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 13,
                  color: color ?? AppColors.textMuted,
                  fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  Widget _StatusBadge({required String status}) {
    String display;
    Color color;
    switch (status) {
      case 'pending':
      case 'pending_acceptance':
        display = 'Order Placed';
        color = Colors.orange;
        break;
      case 'accepted':
      case 'processing':
        display = 'Accepted';
        color = AppColors.primary;
        break;
      case 'shipped':
        display = 'On the Way';
        color = AppColors.info;
        break;
      case 'delivered':
      case 'completed':
        display = 'Delivered';
        color = AppColors.success;
        break;
      case 'cancelled':
      case 'returned':
        display = 'Cancelled';
        color = AppColors.error;
        break;
      default:
        display = status.replaceAll('_', ' ').toUpperCase();
        color = AppColors.textMuted;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: AppSpacing.xxs),
        Text(display,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppColors.textPrimary)),
      ],
    );
  }

  String _formatDeadline(DateTime deadline, AppLocalizations l10n) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) return l10n.translate('deadline_passed');
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    return l10n
        .translate('deadline_format')
        .replaceAll('{hours}', hours.toString())
        .replaceAll('{minutes}', minutes.toString());
  }
}

// ★ Return Request Dialog (same as in orders_screen.dart)
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