// lib/screens/checkout_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:collection/collection.dart';
import '../api/client.dart';
import '../providers/cart_provider.dart';
import '../providers/auth_provider.dart';
import '../services/checkout_service.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'order_tracking_screen.dart';

const String telebirrLogoUrl =
    'https://upload.wikimedia.org/wikipedia/commons/thumb/3/3c/Telebirr_logo.svg/512px-Telebirr_logo.svg.png';
const String chapaLogoUrl = 'https://chapapay.com/logo.png';

double _toDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

String _fmt(dynamic v) {
  final double val = _toDouble(v);
  if (val == 0) return '0.00';
  final parts = val.toStringAsFixed(2).split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return '$intPart.${parts[1]}';
}

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({Key? key}) : super(key: key);
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();

  // Address state
  List<Map<String, dynamic>> _addresses = [];
  bool _loadingAddrs = true;
  int? _selectedAddrId;
  String _currentFullAddress = '';
  Map<String, dynamic> _structured = {};
  double? _manualLat, _manualLng;

  String _carrierCode = '09';
  final _phoneLocalCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  List<Map<String, dynamic>> _regions = [];
  List<Map<String, dynamic>> _zones = [];
  List<Map<String, dynamic>> _woredas = [];
  int? _regionId, _zoneId, _woredaId;
  bool _loadingRegions = false;

  List<ShippingOption> _shippingOpts = [];
  ShippingOption? _selectedShipping;
  bool _loadingShipping = false;
  String? _shipError;

  List<PaymentGateway> _gateways = [];
  PaymentGateway? _selectedPay;
  bool _loadingPay = true;
  String? _payError;

  final _couponCtrl = TextEditingController();
  bool _applyingCoupon = false;
  String? _appliedCouponCode;
  String? _couponError;

  int? _orderId;
  bool _placing = false;

  // Backend summary values
  double _summarySubtotal = 0.0;
  double _summaryShipping = 0.0;
  double _summaryTotal = 0.0;
  double _serviceFee = 0.0;
  double _vat = 0.0;
  double _couponDiscount = 0.0;
  double _rawCarrierCost = 0.0;
  double _sellerSubsidy = 0.0;
  double _platformMarkup = 0.0;
  bool _loadingSummary = false;

  // Enriched summary data
  CheckoutSummaryAddress? _summaryAddress;
  List<CheckoutSummaryItem> _summaryItems = [];
  Map<String, dynamic> _deliveryDetails = {};

  Map<int, String> _vendorNames = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    await Future.wait([_fetchAddresses(), _fetchRegions(), _fetchPayments()]);
    _fetchVendorNames();

    if (_phoneLocalCtrl.text.isEmpty) {
      final auth = ref.read(authProvider);
      final userPhone = auth.value?.phone;
      if (userPhone != null && userPhone.isNotEmpty) {
        _parsePhone(userPhone);
      }
    }
  }

  // ─── Data fetching ────────────────────────────────────
  Future<void> _fetchAddresses() async {
    try {
      final res = await ApiClient.instance.get('/addresses');
      final List raw = res.data is List ? res.data : (res.data['data'] ?? []);
      setState(() {
        _addresses = raw.map((a) => {
          'id': (a['id'] as num?)?.toInt() ?? 0,
          'full_address': a['full_address'] ?? a['address_line'] ?? '',
          'phone': a['phone'] ?? '',
          'delivery_notes': a['delivery_notes'] ?? '',
        }).toList();
        _loadingAddrs = false;
        if (_addresses.isNotEmpty && _selectedAddrId == null) {
          final def = _addresses.first;
          _selectedAddrId = def['id'];
          _currentFullAddress = def['full_address'] ?? '';
          _parsePhone(def['phone'] as String? ?? '');
          _notesCtrl.text = def['delivery_notes'] ?? '';
          _fetchShipping(_selectedAddrId!);
        }
      });
    } catch (_) {
      setState(() => _loadingAddrs = false);
    }
  }

  void _parsePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('251') && digits.length >= 12) {
      final local = digits.substring(3);
      if (local.startsWith('9') && local.length == 9) {
        _carrierCode = '09';
        _phoneLocalCtrl.text = local.substring(1);
      } else if (local.startsWith('7') && local.length == 9) {
        _carrierCode = '07';
        _phoneLocalCtrl.text = local.substring(1);
      } else {
        _carrierCode = '09';
        _phoneLocalCtrl.text = '';
      }
    } else if (digits.startsWith('0') && digits.length == 10) {
      final carrier = digits.substring(0, 2);
      if (carrier == '09' || carrier == '07') {
        _carrierCode = carrier;
        _phoneLocalCtrl.text = digits.substring(2);
      } else {
        _carrierCode = '09';
        _phoneLocalCtrl.text = '';
      }
    } else {
      _carrierCode = '09';
      _phoneLocalCtrl.text = '';
    }
  }

  Future<void> _fetchRegions() async {
    setState(() => _loadingRegions = true);
    try {
      final res = await ApiClient.instance.get('/regions');
      final List raw = res.data is List ? res.data : (res.data['data'] ?? []);
      setState(() {
        _regions = raw.map((r) => {'id': r['id'], 'name': r['name']}).toList();
      });
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingRegions = false);
    }
  }

  Future<void> _fetchZones(int regionId, {int? preserveId}) async {
    setState(() { _zones = []; if (preserveId == null) { _zoneId = null; _woredaId = null; _woredas = []; } });
    try {
      final res = await ApiClient.instance.get('/regions/$regionId/zones');
      final List raw = res.data is List ? res.data : (res.data['data'] ?? []);
      setState(() {
        _zones = raw.map((z) => {'id': z['id'], 'name': z['name']}).toList();
        if (preserveId != null) _zoneId = preserveId;
      });
    } catch (_) {}
  }

  Future<void> _fetchWoredas(int zoneId, {int? preserveId}) async {
    setState(() { _woredas = []; if (preserveId == null) _woredaId = null; });
    try {
      final res = await ApiClient.instance.get('/zones/$zoneId/woredas');
      final List raw = res.data is List ? res.data : (res.data['data'] ?? []);
      setState(() {
        _woredas = raw.map((w) => {'id': w['id'], 'name': w['name']}).toList();
        if (preserveId != null) _woredaId = preserveId;
      });
    } catch (_) {}
  }

  Future<void> _fetchShipping(int addrId) async {
    setState(() { _loadingShipping = true; _shipError = null; });
    try {
      final opts = await CheckoutService.getShippingOptions(addrId);
      setState(() {
        _shippingOpts = opts;
        if (opts.isNotEmpty && _selectedShipping == null) {
          _selectedShipping = opts.first;
        }
      });
      if (_selectedShipping != null) {
        _fetchSummary();
      }
    } catch (e) {
      setState(() => _shipError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingShipping = false);
    }
  }

  Future<void> _fetchPayments() async {
    setState(() => _loadingPay = true);
    try {
      final gateways = await CheckoutService.getPaymentOptions();
      setState(() {
        _gateways = gateways;
        if (gateways.isNotEmpty && _selectedPay == null) {
          _selectedPay = gateways.firstWhereOrNull((g) => g.provider == 'telebirr') ?? gateways.first;
        }
      });
    } catch (e) {
      setState(() => _payError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingPay = false);
    }
  }

  Future<void> _fetchVendorNames() async {
    final cart = ref.read(cartProvider);
    if (cart == null || cart.items.isEmpty) return;
    final uniqueProductIds = cart.items.where((item) => item.productId != null).map((item) => item.productId!).toSet().toList();
    for (final productId in uniqueProductIds) {
      try {
        final res = await ApiClient.instance.get('/products/$productId');
        final vendorName = res.data?['vendor']?['business_name'] ?? res.data?['vendor']?['name'] ?? '';
        if (vendorName.isNotEmpty) setState(() { _vendorNames[productId] = vendorName; });
      } catch (_) {}
    }
  }

  Future<void> _fetchSummary() async {
    if (_selectedAddrId == null || _selectedShipping == null) return;
    setState(() => _loadingSummary = true);
    try {
      final summary = await CheckoutService.getSummary(
        addressId: _selectedAddrId!,
        partnerId: _selectedShipping!.partnerId,
        couponCode: _appliedCouponCode,
      );
      if (mounted) {
        setState(() {
          _summarySubtotal = summary.subtotal;
          _summaryShipping = summary.shipping;
          _summaryTotal = summary.total;
          _serviceFee = summary.serviceFee;
          _vat = summary.vat;
          _couponDiscount = summary.discount;
          _rawCarrierCost = summary.rawCarrierCost;
          _sellerSubsidy = summary.sellerSubsidy;
          _platformMarkup = summary.platformMarkup;
          _summaryAddress = summary.address;
          _summaryItems = summary.items;
          _deliveryDetails = summary.delivery;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _summarySubtotal = 0;
          _summaryShipping = 0;
          _summaryTotal = 0;
          _serviceFee = 0;
          _vat = 0;
          _couponDiscount = 0;
          _rawCarrierCost = 0;
          _sellerSubsidy = 0;
          _platformMarkup = 0;
          _summaryAddress = null;
          _summaryItems = [];
          _deliveryDetails = {};
        });
      }
    } finally {
      if (mounted) setState(() => _loadingSummary = false);
    }
  }

  Future<void> _applyCoupon() async {
    final l10n = AppLocalizations.of(context);
    final code = _couponCtrl.text.trim();
    if (code.isEmpty) {
      _showError(l10n.translate('checkout_error_empty_coupon'));
      return;
    }
    setState(() {
      _applyingCoupon = true;
      _couponError = null;
    });
    try {
      final res = await ApiClient.instance.post('/validate_coupon', data: {'coupon_code': code});
      final data = res.data as Map<String, dynamic>;
      if (data['valid'] == true) {
        setState(() {
          _appliedCouponCode = code;
          _couponError = null;
        });
        _fetchSummary();
      } else {
        setState(() {
          _appliedCouponCode = null;
          _couponError = data['error']?.toString() ?? 'Invalid coupon';
        });
      }
    } catch (e) {
      setState(() {
        _appliedCouponCode = null;
        _couponError = 'Failed to validate coupon';
      });
    } finally {
      if (mounted) setState(() => _applyingCoupon = false);
    }
  }

  Future<void> _placeOrder() async {
    final l10n = AppLocalizations.of(context);
    if (_selectedAddrId == null) {
      _showError('Please add a delivery address');
      return;
    }
    if (_loadingSummary || _summaryTotal <= 0) {
      _showError('Order summary not loaded. Please wait.');
      return;
    }
    if (!_validate()) return;

    setState(() => _placing = true);
    try {
      String? method = _selectedPay?.provider;
      if (method == 'cash_on_delivery' || method == 'cod') method = 'cash_on_delivery';

      final idempotencyKey = '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(999999)}';

      final payload = {
        'address_id': _selectedAddrId,
        'payment_method': method ?? 'cash_on_delivery',
        if (_selectedShipping?.partnerId != null)
          'partner_id': _selectedShipping!.partnerId,
        'coupon_code': _appliedCouponCode,
        'idempotency_key': idempotencyKey,
        'delivery_speed': _selectedShipping?.deliverySpeed ?? '0',
      };

      final response = await ApiClient.instance.post('/checkout', data: payload);
      final data = response.data;
      List<dynamic> success = data['successful'] ?? data['orders'] ?? [];
      List<dynamic> failed = data['failed'] ?? [];
      final consolidatedShip = _toDouble(data['consolidated_shipping']);
      if (success.isNotEmpty) {
        _orderId = (success[0]['id'] as num?)?.toInt();
        final redirect = data['redirect_url']?.toString();
        if (redirect != null && redirect.isNotEmpty) {
          if (!mounted) return;
          showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
          try { await launchUrl(Uri.parse(redirect), mode: LaunchMode.externalApplication); } catch (_) {}
          if (!mounted) return;
          Navigator.pop(context);
          showDialog(context: context, barrierDismissible: false, builder: (_) => _OrderPendingDialog(orderId: _orderId?.toString() ?? '', onBackToShop: () => Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false)));
          return;
        }
        if (!mounted) return;
        showDialog(context: context, barrierDismissible: false, builder: (_) => _OrderSuccessDialog(
          orderId: _orderId?.toString() ?? '', partialFailure: failed, consolidatedShipping: consolidatedShip,
          onTrackOrder: () { Navigator.pop(context); if (_orderId != null) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: _orderId!))); },
          onBackToShop: () => Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false),
        ));
      } else {
        _showError(l10n.translate('checkout_error_all_failed'));
      }
    } catch (e) {
      String msg = l10n.translate('checkout_error_failed');
      try {
        final ex = e as dynamic;
        if (ex.response?.data != null) {
          final d = ex.response!.data;
          msg = d['errors'] is List ? (d['errors'] as List).first.toString() : (d['error'] ?? d['message'] ?? msg);
        }
      } catch (_) {}
      _showError(msg);
    } finally { if (mounted) setState(() => _placing = false); }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 16)),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 80),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 3),
    ));
  }

  bool _validate() {
    if (_selectedPay == null) { _showError('Please select a payment method'); return false; }
    return true;
  }

  @override
  void dispose() {
    _phoneLocalCtrl.dispose(); _notesCtrl.dispose(); _couponCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authProvider);

    return authState.when(
      data: (user) {
        if (user == null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false),
          );
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          );
        }
        return _buildCheckout(l10n);
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (err, stack) => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Failed to load session\nPlease sign in again',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                child: const Text('Go to Login', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckout(AppLocalizations l10n) {
    final cart = ref.watch(cartProvider);
    final cartItems = cart?.items ?? [];

    // Determine which items to display
    final displayItems = _summaryItems.isNotEmpty ? _summaryItems : cartItems;

    return Scaffold(
      backgroundColor: Colors.white,
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
        iconTheme: const IconThemeData(color: Colors.white, size: 24),
        title: Text(l10n.translate('checkout_title'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildAddressSection(l10n),
                    const SizedBox(height: 2),
                    _buildDeliverySection(l10n),
                    const SizedBox(height: 2),
                    _buildPaymentSection(l10n),
                    const SizedBox(height: 2),
                    _buildOrderSummary(l10n, displayItems),
                    const SizedBox(height: 2),
                    _buildCouponSection(l10n),
                    const SizedBox(height: 70),
                  ],
                ),
              ),
            ),
          ),
          _buildBottomBar(l10n),
        ],
      ),
    );
  }

  // ═══════════ ADDRESS SECTION (compact) ═══════════
  Widget _buildAddressSection(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 110),
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: NetworkImage('https://images.unsplash.com/photo-1524661135-423995f22d0b?w=600&q=80'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(Colors.black45, BlendMode.darken),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_currentFullAddress.isEmpty) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openAddressSheet,
                  icon: const Icon(Icons.add, color: Colors.white, size: 20),
                  label: const Text(
                    'Add Delivery Address',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on, size: 24, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currentFullAddress,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        if (_phoneLocalCtrl.text.isNotEmpty)
                          Row(
                            children: [
                              const Icon(Icons.phone_android, size: 14, color: Colors.white70),
                              const SizedBox(width: 4),
                              Text(
                                '+251 $_carrierCode ${_phoneLocalCtrl.text}',
                                style: const TextStyle(fontSize: 12, color: Colors.white70),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _openAddressSheet,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.edit, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Delivery / Payment / Summary ──────────
  Widget _buildDeliverySection(AppLocalizations l10n) {
    return _buildSectionCard(
      title: l10n.translate('checkout_delivery_method'),
      icon: Icons.local_shipping,
      iconColor: AppColors.primary,
      child: _loadingShipping
          ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          : _shipError != null
              ? _errorRetry(l10n.translate('checkout_error_no_delivery'), () => _selectedAddrId != null ? _fetchShipping(_selectedAddrId!) : null)
              : _shippingOpts.isEmpty
                  ? _buildEmptyState(icon: Icons.local_shipping, message: 'No delivery options available', color: AppColors.primary)
                  : Column(children: _shippingOpts.map((opt) => _optionTile(
                        title: opt.deliveryLabel,
                        subtitle: '${opt.deliveryTimeLabel} · ETB ${_fmt(opt.charge)}',
                        selected: _selectedShipping == opt,
                        onTap: () {
                          setState(() => _selectedShipping = opt);
                          _fetchSummary();
                        },
                      )).toList()),
    );
  }

  Widget _buildPaymentSection(AppLocalizations l10n) {
    return _buildSectionCard(
      title: l10n.translate('checkout_payment_method'),
      icon: Icons.credit_card,
      iconColor: Colors.indigo,
      child: _loadingPay
          ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          : _payError != null
              ? _errorRetry(l10n.translate('checkout_error_no_payment'), _fetchPayments)
              : _gateways.isEmpty
                  ? _buildEmptyState(icon: Icons.credit_card, message: 'No payment methods available', color: Colors.indigo)
                  : Column(
                      children: _gateways.map((gw) {
                        final displayName = gw.name.replaceAll('Sandbox', '').trim();
                        return _optionTile(
                          title: displayName,
                          selected: _selectedPay == gw,
                          onTap: () => setState(() => _selectedPay = gw),
                          leading: gw.provider == 'telebirr' || gw.provider == 'chapa'
                              ? ClipRRect(
                                  borderRadius: BorderRadius.zero,
                                  child: Image.network(gw.provider == 'telebirr' ? telebirrLogoUrl : chapaLogoUrl, width: 28, height: 28, fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const SizedBox(width: 28, height: 28)))
                              : gw.provider == 'cash_on_delivery'
                                  ? const Padding(padding: EdgeInsets.only(right: 8), child: Text('💵', style: TextStyle(fontSize: 20)))
                                  : null,
                        );
                      }).toList(),
                    ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String message, required Color color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(icon, size: 44, color: color.withOpacity(0.4)),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Color iconColor, required Widget child}) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
            ]),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _optionTile({required String title, String? subtitle, required bool selected, required VoidCallback onTap, Widget? leading}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            border: Border.all(color: Colors.transparent, width: 1),
          ),
          child: Row(children: [
            if (leading != null) leading,
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87)),
              if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.black54))],
            ])),
            if (selected) Icon(Icons.check_circle, size: 16, color: Colors.blue.shade600),
          ]),
        ),
      ),
    );
  }

  // ── ORDER SUMMARY ──
  Widget _buildOrderSummary(AppLocalizations l10n, List items) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Icon(Icons.receipt_long, size: 20, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text(l10n.translate('checkout_order_summary'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
          ]),
        ),
        const SizedBox(height: 6),
        if (_summaryAddress != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _summaryAddress!.fullAddress.isNotEmpty
                      ? _summaryAddress!.fullAddress
                      : [
                          _summaryAddress!.street,
                          _summaryAddress!.subCity,
                          _summaryAddress!.woreda,
                          _summaryAddress!.city,
                        ].where((s) => s != null && s.isNotEmpty).join(', '),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                ),
                if (_summaryAddress!.landmark != null && _summaryAddress!.landmark!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Landmark: ${_summaryAddress!.landmark}', style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
                  ),
                if (_summaryAddress!.neighborhood != null && _summaryAddress!.neighborhood!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Neighborhood: ${_summaryAddress!.neighborhood}', style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
                  ),
                if (_summaryAddress!.phone != null && _summaryAddress!.phone!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Phone: ${_summaryAddress!.phone}', style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
                  ),
                if (_summaryAddress!.deliveryNotes != null && _summaryAddress!.deliveryNotes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('📝 ${_summaryAddress!.deliveryNotes}', style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontStyle: FontStyle.italic)),
                  ),
              ],
            ),
          )
        else if (_currentFullAddress.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(10),
            color: const Color(0xFFE8F5E9),
            child: Text(
              _currentFullAddress,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
        const SizedBox(height: 6),
        ...items.map((item) {
          if (item is CheckoutSummaryItem) {
            final price = item.price;
            final basePrice = item.basePrice;
            final qty = item.quantity;
            final lineTotal = item.lineTotal;
            final hasDiscount = item.hasDiscount;
            final vendorName = item.vendorName ?? '';
            final variantAttrs = item.variantAttributes;
            return _buildSummaryItem(
              imageUrl: item.imageUrl,
              title: item.title,
              vendorName: vendorName,
              variantAttrs: variantAttrs,
              price: price,
              basePrice: basePrice,
              qty: qty,
              lineTotal: lineTotal,
              hasDiscount: hasDiscount,
              discountTotal: item.discountTotal,
            );
          } else {
            // Fallback for cart item map
            final vendorName = _vendorNames[item.productId] ?? '';
            final price = _toDouble(item.price);
            final basePrice = _toDouble(item.basePrice ?? item.originalPrice ?? item.price);
            final qty = (item.quantity ?? 1) as int;
            final lineTotal = price * qty;
            final hasDiscount = basePrice > price;
            final discountTotal = (basePrice - price) * qty;
            final variantAttrs = item.variant ?? {};
            return _buildSummaryItem(
              imageUrl: item.image,
              title: item.title ?? '',
              vendorName: vendorName,
              variantAttrs: variantAttrs,
              price: price,
              basePrice: basePrice,
              qty: qty,
              lineTotal: lineTotal,
              hasDiscount: hasDiscount,
              discountTotal: discountTotal,
            );
          }
        }),
        const SizedBox(height: 6),
        const Divider(height: 1, color: Color(0xFFEEEEEE)),
        if (_loadingSummary)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (_rawCarrierCost > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3), child: _sumRow('Delivery (raw)', _fmt(_rawCarrierCost))),
          if (_sellerSubsidy > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3), child: _sumRow('Seller Delivery Subsidy', '-ETB ${_fmt(_sellerSubsidy)}', textColor: Colors.red)),
          if (_platformMarkup > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3), child: _sumRow('Platform Fee', _fmt(_platformMarkup))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3), child: _sumRow('Subtotal', _fmt(_summarySubtotal))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3), child: _sumRow('Final Delivery', _fmt(_summaryShipping))),
          if (_serviceFee > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3), child: _sumRow('Service Fee', _fmt(_serviceFee))),
          if (_vat > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3), child: _sumRow('VAT', _fmt(_vat))),
          if (_couponDiscount > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3), child: _sumRow('Coupon Discount', '-ETB ${_fmt(_couponDiscount)}', textColor: Colors.red)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('Total', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
                Text('ETB ${_fmt(_summaryTotal)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildSummaryItem({
    required String? imageUrl,
    required String title,
    required String vendorName,
    required Map<String, dynamic> variantAttrs,
    required double price,
    required double basePrice,
    required int qty,
    required double lineTotal,
    required bool hasDiscount,
    required double discountTotal,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.zero,
          child: Image.network(imageUrl ?? '', width: 48, height: 48, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                  width: 48, height: 48, color: Colors.grey.shade200,
                  child: const Icon(Icons.image, color: Colors.grey, size: 22))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (vendorName.isNotEmpty) Text(vendorName, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          if (variantAttrs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                variantAttrs.entries.map((e) => '${e.key}: ${e.value}').join(', '),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 3),
          Row(
            children: [
              Text('ETB ${_fmt(price)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              if (hasDiscount) ...[
                const SizedBox(width: 4),
                Text('ETB ${_fmt(basePrice)}', style: const TextStyle(fontSize: 12, color: Colors.grey, decoration: TextDecoration.lineThrough)),
              ],
              const SizedBox(width: 4),
              Text('× $qty', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
          if (hasDiscount) ...[
            const SizedBox(height: 2),
            Text(
              'Discount: -ETB ${_fmt(discountTotal)}',
              style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 2),
          Text('Total: ETB ${_fmt(lineTotal)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ])),
      ]),
    );
  }

  Widget _sumRow(String label, String amount, {Color textColor = Colors.black54}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: 13, color: textColor)),
      Text(amount, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textColor)),
    ]);
  }

  // ── MODERN COUPON SECTION ──
  Widget _buildCouponSection(AppLocalizations l10n) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Icon(Icons.local_offer, size: 20, color: Colors.pink),
            const SizedBox(width: 8),
            Text(l10n.translate('checkout_coupon_code'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
          ]),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _couponCtrl,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                    decoration: InputDecoration(
                      hintText: l10n.translate('checkout_coupon_hint'),
                      hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(4),
                  child: TextButton(
                    onPressed: _applyingCoupon ? null : _applyCoupon,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: _applyingCoupon
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(l10n.translate('checkout_apply'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_couponError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 16, right: 16),
            child: Text(_couponError!, style: const TextStyle(fontSize: 13, color: Colors.red)),
          ),
        if (_appliedCouponCode != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 16, right: 16),
            child: Row(children: [
              const Icon(Icons.check_circle, size: 14, color: AppColors.success),
              const SizedBox(width: 4),
              Text('Coupon applied: $_appliedCouponCode', style: const TextStyle(fontSize: 13, color: AppColors.success)),
            ]),
          ),
      ]),
    );
  }

  // ── BOTTOM BAR ──
  Widget _buildBottomBar(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: Colors.white,
      child: SafeArea(
        child: Row(children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.translate('checkout_total'), style: const TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 2),
                Text('ETB ${_fmt(_summaryTotal)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: (_placing || _loadingSummary || _summaryTotal <= 0) ? null : _placeOrder,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              elevation: 0,
            ),
            child: _placing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('Place Order', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }

  Widget _errorRetry(String msg, VoidCallback? onRetry) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [
      Text(msg, style: const TextStyle(color: Colors.grey, fontSize: 14)),
      if (onRetry != null) TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 16), label: const Text('Retry', style: TextStyle(fontSize: 14))),
    ]));
  }

  // ═══════════ ADDRESS BOTTOM SHEET ═══════════
  Future<void> _openAddressSheet() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (sheetContext) => _AddressSheet(
        regions: _regions,
        initialStreet: _structured['street'] ?? '',
        initialSubCity: _structured['sub_city'] ?? '',
        initialWoreda: _structured['woreda'] ?? '',
        initialCity: _structured['city'] ?? 'Addis Ababa',
        initialBusiness: _structured['landmark'] ?? '',
        initialCarrierCode: _carrierCode,
        initialPhone: _phoneLocalCtrl.text,
        initialNotes: _notesCtrl.text,
        initialLat: _manualLat,
        initialLng: _manualLng,
        onRegionChanged: (int regionId) => _fetchZones(regionId),
        onZoneChanged: (int zoneId) => _fetchWoredas(zoneId),
      ),
    );

    if (result != null && mounted) {
      try {
        final localPhone = result['phone'] as String? ?? '';
        final carrierCode = result['carrier_code'] as String? ?? '09';
        final fullPhone = '+251$carrierCode$localPhone';
        final payload = {
          'region_id': result['region_id'] ?? 14,
          'address_line': result['address_line'],
          'phone': fullPhone,
          'delivery_notes': result['notes'] ?? '',
          'is_default': false,
          'latitude': result['latitude'],
          'longitude': result['longitude'],
          'sub_city': result['sub_city'],
          'street': result['street'],
          'city': result['city'],
          'woreda_text': result['woreda_text'],
          'landmark': result['landmark'],
          'neighborhood': result['neighborhood'] ?? '',
          'source': result['source'] ?? 'auto',
        };
        final res = await ApiClient.instance.post('/addresses', data: payload);
        final newId = (res.data['id'] as num?)?.toInt();
        if (newId == null) { _showError('Failed to save address'); return; }

        setState(() {
          _selectedAddrId = newId;
          _currentFullAddress = result['address_line'] as String;
          _structured = {
            'city': result['city'],
            'sub_city': result['sub_city'],
            'woreda': result['woreda_text'],
            'street': result['street'],
            'landmark': result['landmark'],
            'neighborhood': result['neighborhood'],
          };
          _manualLat = result['latitude'];
          _manualLng = result['longitude'];
          _carrierCode = carrierCode;
          _phoneLocalCtrl.text = localPhone;
          _notesCtrl.text = result['notes'] ?? '';
        });
        _fetchShipping(newId);
      } catch (e) {
        _showError('Could not save address');
      }
    }
  }
}

// ═══════════ ADDRESS BOTTOM SHEET WIDGET ═══════════
class _AddressSheet extends StatefulWidget {
  final List<Map<String, dynamic>> regions;
  final String initialStreet, initialSubCity, initialWoreda, initialCity, initialBusiness;
  final String initialCarrierCode, initialPhone, initialNotes;
  final double? initialLat, initialLng;
  final ValueChanged<int> onRegionChanged;
  final ValueChanged<int> onZoneChanged;

  const _AddressSheet({
    required this.regions,
    required this.initialStreet, required this.initialSubCity, required this.initialWoreda, required this.initialCity, required this.initialBusiness,
    required this.initialCarrierCode, required this.initialPhone, required this.initialNotes,
    this.initialLat, this.initialLng,
    required this.onRegionChanged, required this.onZoneChanged,
  });

  @override
  State<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<_AddressSheet> {
  final _searchCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _subCityCtrl = TextEditingController();
  final _woredaCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _businessCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _carrierCode = '09';
  final _phoneFocusNode = FocusNode();
  bool _phoneValid = true;

  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;
  Timer? _debounce;
  bool _isValidating = false;
  Map<String, dynamic>? _geocodeResult;
  Map<String, dynamic> _structured = {};
  double? _manualLat, _manualLng;
  bool _detecting = false;
  String? _detectError;

  @override
  void initState() {
    super.initState();
    _streetCtrl.text = widget.initialStreet;
    _subCityCtrl.text = widget.initialSubCity;
    _woredaCtrl.text = widget.initialWoreda;
    _cityCtrl.text = widget.initialCity;
    _businessCtrl.text = widget.initialBusiness;
    _carrierCode = widget.initialCarrierCode;
    _phoneCtrl.text = widget.initialPhone;
    _notesCtrl.text = widget.initialNotes;
    _manualLat = widget.initialLat;
    _manualLng = widget.initialLng;

    _phoneValid = _phoneCtrl.text.length == 8;
  }

  @override
  void dispose() {
    _searchCtrl.dispose(); _streetCtrl.dispose(); _subCityCtrl.dispose(); _woredaCtrl.dispose();
    _cityCtrl.dispose(); _businessCtrl.dispose(); _phoneCtrl.dispose(); _notesCtrl.dispose();
    _phoneFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  bool _validatePhone() {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    return digits.length == 8;
  }

  void _onPhoneChanged(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 8) {
      _phoneCtrl.text = digits.substring(0, 8);
      _phoneCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _phoneCtrl.text.length));
    } else {
      _phoneCtrl.text = digits;
      _phoneCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _phoneCtrl.text.length));
    }
    setState(() {
      _phoneValid = _validatePhone();
    });
  }

  Future<void> _verifyAddress() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() { _isValidating = true; _detectError = null; });
    try {
      final data = await ApiClient.validatePlace(query);
      final struct = (data['structured'] as Map<String, dynamic>?) ?? {};
      if (struct.isNotEmpty && data['lat'] != null) {
        _geocodeResult = data;
        _structured = struct;
        _manualLat = _toDouble(data['lat']);
        _manualLng = _toDouble(data['lng']);
        _streetCtrl.text = struct['street'] ?? '';
        _subCityCtrl.text = struct['sub_city'] ?? '';
        _woredaCtrl.text = struct['woreda'] ?? '';
        _cityCtrl.text = struct['city'] ?? 'Addis Ababa';
        _businessCtrl.text = struct['landmark'] ?? '';
      } else {
        setState(() { _detectError = 'Address not found'; });
      }
    } catch (_) {
      setState(() { _detectError = 'Verification failed'; });
    } finally {
      if (mounted) setState(() => _isValidating = false);
    }
  }

  void _fetchSuggestions(String val) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (val.trim().isEmpty) {
      setState(() { _suggestions = []; _showSuggestions = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final data = await ApiClient.suggestAddress(val);
        final list = (data['suggestions'] as List?)?.map((s) => Map<String, dynamic>.from(s)).toList() ?? [];
        if (mounted) setState(() { _suggestions = list; _showSuggestions = true; });
      } catch (_) {}
    });
  }

  void _selectSuggestion(Map<String, dynamic> s) {
    _searchCtrl.text = s['label'] ?? '';
    setState(() => _showSuggestions = false);
    _verifyAddress();
  }

  Future<void> _detectLocation() async {
    setState(() { _detectError = null; _detecting = true; });
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() { _detectError = 'Location permission denied'; _detecting = false; });
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() { _detectError = 'Location permission permanently denied'; _detecting = false; });
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      ).timeout(const Duration(seconds: 5));
      final geoRes = await ApiClient.reverseGeocode(pos.latitude, pos.longitude);
      final address = geoRes['address'] ?? '';
      final struct = (geoRes['structured'] as Map<String, dynamic>?) ?? {};
      _streetCtrl.text = struct['street'] ?? '';
      _subCityCtrl.text = struct['sub_city'] ?? '';
      _woredaCtrl.text = struct['woreda'] ?? '';
      _cityCtrl.text = struct['city'] ?? 'Addis Ababa';
      _businessCtrl.text = struct['landmark'] ?? '';
      _manualLat = pos.latitude;
      _manualLng = pos.longitude;
      _structured = struct;
      if (address.isNotEmpty) _searchCtrl.text = address;
    } on TimeoutException {
      setState(() { _detectError = 'GPS timeout'; });
    } catch (e) {
      setState(() { _detectError = 'Could not detect location'; });
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  void _confirmAddress() {
    if (!_phoneValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid Ethiopian phone number (8 digits after the carrier code)', style: TextStyle(fontSize: 15))),
      );
      return;
    }

    final addrLine = [_streetCtrl.text.trim(), _subCityCtrl.text.trim(), _woredaCtrl.text.trim(), _cityCtrl.text.trim()]
        .where((s) => s.isNotEmpty)
        .join(', ');
    final data = {
      'address_line': addrLine,
      'latitude': _manualLat,
      'longitude': _manualLng,
      'sub_city': _subCityCtrl.text.trim(),
      'street': _streetCtrl.text.trim(),
      'city': _cityCtrl.text.trim(),
      'woreda_text': _woredaCtrl.text.trim(),
      'landmark': _businessCtrl.text.trim(),
      'neighborhood': _structured['neighborhood'],
      'source': _geocodeResult != null ? 'auto' : 'manual',
      'phone': _phoneCtrl.text.trim(),
      'notes': _notesCtrl.text.trim(),
      'carrier_code': _carrierCode,
      'region_id': 14,
    };
    Navigator.pop(context, data);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.location_on, size: 24, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            const Text('Add Delivery Address', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 20),
          _buildFilledField(
            _searchCtrl,
            'Search address…',
            hint: true,
            onChanged: _fetchSuggestions,
            onSubmitted: (_) => _verifyAddress(),
          ),
          if (_showSuggestions && _suggestions.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              margin: const EdgeInsets.only(top: 8),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  title: Text(_suggestions[i]['label'] ?? '', style: const TextStyle(fontSize: 15)),
                  onTap: () => _selectSuggestion(_suggestions[i]),
                ),
              ),
            ),
          const SizedBox(height: 20),
          _buildFilledField(_streetCtrl, 'Street / Road'),
          const SizedBox(height: 16),
          _buildFilledField(_subCityCtrl, 'Sub-City / Area'),
          const SizedBox(height: 16),
          _buildFilledField(_woredaCtrl, 'Woreda'),
          const SizedBox(height: 16),
          _buildFilledField(_cityCtrl, 'City'),
          const SizedBox(height: 16),
          _buildFilledField(_businessCtrl, 'Nearby Landmark'),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _detecting ? null : _detectLocation,
              icon: _detecting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.my_location, size: 20),
              label: const Text('Use my current location', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
              ),
            ),
          ),
          if (_detectError != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_detectError!, style: const TextStyle(color: Colors.red, fontSize: 15)),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🇪🇹', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 4),
                    const Text('+251', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    DropdownButton<String>(
                      value: _carrierCode,
                      underline: const SizedBox(),
                      style: const TextStyle(fontSize: 15, color: Colors.black87),
                      items: const [
                        DropdownMenuItem(value: '09', child: Text('09')),
                        DropdownMenuItem(value: '07', child: Text('07')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _carrierCode = v);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _phoneCtrl,
                  focusNode: _phoneFocusNode,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  buildCounter: (context, {required int currentLength, required bool isFocused, required int? maxLength}) => null,
                  onChanged: _onPhoneChanged,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'XXXX XXXX',
                    hintStyle: const TextStyle(fontSize: 16),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Colors.black87, width: 1.5),
                    ),
                    errorText: _phoneValid ? null : 'Enter 8 digits',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildFilledField(_notesCtrl, 'Delivery notes', maxLines: 2),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _confirmAddress,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black87,
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Confirm Address', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildFilledField(
    TextEditingController ctrl,
    String label, {
    int maxLines = 1,
    bool hint = false,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        labelText: hint ? null : label,
        hintText: hint ? label : null,
        labelStyle: const TextStyle(fontSize: 16),
        hintStyle: const TextStyle(fontSize: 16),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Colors.black87, width: 1.5),
        ),
      ),
    );
  }
}

// ── DIALOGS ─────────────────────────────────
class _OrderSuccessDialog extends StatelessWidget {
  final String orderId; final List<dynamic>? partialFailure; final double consolidatedShipping;
  final VoidCallback onTrackOrder; final VoidCallback onBackToShop;
  const _OrderSuccessDialog({required this.orderId, this.partialFailure, required this.consolidatedShipping, required this.onTrackOrder, required this.onBackToShop});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context); final textTheme = Theme.of(context).textTheme;
    final hasPartial = partialFailure != null && partialFailure!.isNotEmpty;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 24, offset: const Offset(0, 10))]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 80, height: 80, decoration: BoxDecoration(
            gradient: LinearGradient(colors: [hasPartial ? const Color(0xFFFFA726) : const Color(0xFF4CAF50), hasPartial ? const Color(0xFFFFCC02) : const Color(0xFF81C784)]),
            shape: BoxShape.circle, boxShadow: [BoxShadow(color: (hasPartial ? AppColors.warning : AppColors.success).withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))]),
            child: Icon(hasPartial ? Icons.warning_rounded : Icons.check_rounded, color: Colors.white, size: 44)),
          const SizedBox(height: 16),
          Text(hasPartial ? l10n.translate('checkout_order_partial') : l10n.translate('checkout_order_placed'), style: textTheme.headlineMedium?.copyWith(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(hasPartial ? l10n.translate('checkout_order_partial_detail').replaceAll('{id}', orderId) : l10n.translate('checkout_order_confirmed').replaceAll('{id}', orderId), textAlign: TextAlign.center, style: textTheme.bodySmall?.copyWith(fontSize: 15, color: AppColors.textMuted)),
          if (consolidatedShipping > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Shipping: ETB ${_fmt(consolidatedShipping)}', style: textTheme.bodySmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w600))),
          if (hasPartial) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Failed items:', style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFFE65100))),
                const SizedBox(height: 4),
                ...partialFailure!.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    const Icon(Icons.error_outline, size: 16, color: Color(0xFFE65100)),
                    const SizedBox(width: 6),
                    Expanded(child: Text('${f['vendor'] ?? ''} - ${f['error'] ?? ''}', style: const TextStyle(fontSize: 14, color: Color(0xFFE65100)))),
                  ]),
                )).toList(),
              ]),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: onTrackOrder, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(l10n.translate('checkout_track_order'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton(onPressed: onBackToShop, style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(l10n.translate('checkout_back_to_shop'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)))),
        ]),
      ),
    );
  }
}

class _OrderPendingDialog extends StatelessWidget {
  final String orderId; final VoidCallback onBackToShop;
  const _OrderPendingDialog({required this.orderId, required this.onBackToShop});
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 24, offset: const Offset(0, 10))]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 80, height: 80, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFA726), Color(0xFFFFCC02)]), shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppColors.warning.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))]), child: const Icon(Icons.hourglass_empty, color: Colors.white, size: 44)),
          const SizedBox(height: 16), const Text('Payment Pending', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)), const SizedBox(height: 8),
          Text('Please complete your payment in Telebirr. Your order #${orderId} will be processed once the payment is confirmed.', textAlign: TextAlign.center, style: textTheme.bodySmall?.copyWith(fontSize: 15, color: AppColors.textMuted)),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: OutlinedButton(onPressed: onBackToShop, style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Back to Shop', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)))),
        ]),
      ),
    );
  }
}