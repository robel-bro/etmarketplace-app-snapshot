// lib/screens/seller_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../api/client.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'main_screen.dart';
import 'seller_dashboard_screen.dart';

class SellerSetupScreen extends ConsumerStatefulWidget {
  final bool isBulkSupplier;
  const SellerSetupScreen({Key? key, this.isBulkSupplier = false}) : super(key: key);

  @override
  ConsumerState<SellerSetupScreen> createState() => _SellerSetupScreenState();
}

class _SellerSetupScreenState extends ConsumerState<SellerSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nationalIdCtrl = TextEditingController();
  final _shopNameCtrl = TextEditingController();
  final _subRegionCtrl = TextEditingController();
  final _lowestCtrl = TextEditingController();

  final _telebirrCtrl = TextEditingController();
  String _telebirrLocalPart = '';

  XFile? _tinCertificateFile;   // ★ TIN certificate (replaces TIN number)
  XFile? _licenseFile;
  bool _isLoading = true;
  String? _error;
  late bool _isBulkSupplier;
  bool _submitted = false;
  bool _agreedToTerms = false;

  String? _selectedRegion;
  String? _vendorStatus;
  String? _rejectionReason;

  bool _showTerms = false;
  bool _showPrivacy = false;

  double? _commissionRate;

  static final _faydaRegex = RegExp(r'^\d{10,12}$');
  static final _phoneRegex = RegExp(r'^\+251[79]\d{8}$');

  @override
  void initState() {
    super.initState();
    _isBulkSupplier = widget.isBulkSupplier;
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    try {
      final response = await ApiClient.instance.get('/api/v1/vendors/me');
      final data = response.data;
      if (data != null && data is Map) {
        setState(() {
          _vendorStatus = data['status'];
          _rejectionReason = data['rejection_reason'];
        });
      } else {
        setState(() => _vendorStatus = null);
      }
    } catch (_) {
      setState(() => _vendorStatus = null);
    }

    try {
      final settingsRes = await ApiClient.instance.get('/admin/settings');
      final comm = settingsRes.data?['commission'];
      if (comm != null) {
        setState(() => _commissionRate = (comm['defaultCommission'] ?? 0).toDouble());
      }
    } catch (_) {
      setState(() => _commissionRate = null);
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickTinCertificate() async {
    final ImagePicker picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200);
    if (file != null) setState(() => _tinCertificateFile = file);
  }

  Future<void> _pickLicense() async {
    final ImagePicker picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200);
    if (file != null) setState(() => _licenseFile = file);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // TIN certificate is mandatory
    if (_tinCertificateFile == null) {
      setState(() => _error = 'TIN certificate is required.');
      return;
    }

    // Business license mandatory only for bulk suppliers
    if (_isBulkSupplier && _licenseFile == null) {
      setState(() => _error = 'Business license is required for bulk suppliers.');
      return;
    }

    if (_selectedRegion == null) {
      setState(() => _error = 'Please select a region.');
      return;
    }

    final fullPhone = '+251$_telebirrLocalPart';
    if (!_phoneRegex.hasMatch(fullPhone)) {
      setState(() => _error = 'Enter a valid Ethiopian phone number.');
      return;
    }

    if (!_agreedToTerms) {
      setState(() => _error = 'You must agree to the Seller Agreement and policies.');
      return;
    }

    final location = '$_selectedRegion, $_subLabel: ${_subRegionCtrl.text.trim()}, $_lowestLabel: ${_lowestCtrl.text.trim()}';

    setState(() { _isLoading = true; _error = null; });

    try {
      final formData = FormData.fromMap({
        'vendor[national_id]': _nationalIdCtrl.text.trim(),
        'vendor[business_name]': _shopNameCtrl.text.trim(),
        'vendor[business_address]': location,
        'vendor[is_bulk_supplier]': _isBulkSupplier.toString(),
        'vendor[telebirr_number]': fullPhone,
        if (_tinCertificateFile != null)
          'vendor[tin_certificate]': await MultipartFile.fromFile(_tinCertificateFile!.path),
        if (_licenseFile != null)
          'vendor[business_license]': await MultipartFile.fromFile(_licenseFile!.path),
      });

      await ApiClient.instance.post('/api/seller_verification', data: formData);

      setState(() {
        _submitted = true;
        _vendorStatus = 'pending';
      });

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainScreen()), (route) => false);
        }
      });
    } on DioException catch (e) {
      String message = 'Failed to save. Please try again.';
      if (e.response != null && e.response?.data != null) {
        final data = e.response!.data;
        if (data is Map) {
          message = data['error'] ?? data['message'] ?? message;
        }
      }
      setState(() => _error = message);
    } catch (e) {
      setState(() => _error = 'Failed to save. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showFullLegalModal(String title, String key) async {
    String content = '';
    try {
      final res = await ApiClient.instance.get('/legal/$key');
      content = res.data?['body'] ?? 'Could not load the document.';
    } catch (_) {
      content = 'Could not load the document.';
    }
    if (!mounted) return;
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          backgroundColor: AppColors.cardBackground,
          leading: IconButton(
            icon: const Icon(Icons.close, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Html(
            data: content,
            style: {
              'body': Style(fontSize: FontSize(14), color: AppColors.textPrimary, lineHeight: LineHeight(1.5), margin: Margins.zero),
              'h2': Style(fontSize: FontSize(16), fontWeight: FontWeight.w600, color: AppColors.textPrimary, margin: Margins.only(top: 16, bottom: 6), padding: HtmlPaddings.only(bottom: 6), border: Border(bottom: BorderSide(color: AppColors.borderLight, width: 1))),
              'p': Style(margin: Margins.only(bottom: 10)),
              'ul': Style(margin: Margins.only(bottom: 10)),
              'li': Style(margin: Margins.only(bottom: 2)),
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nationalIdCtrl.dispose(); _shopNameCtrl.dispose(); _subRegionCtrl.dispose();
    _lowestCtrl.dispose(); _telebirrCtrl.dispose();
    super.dispose();
  }

  String get _subLabel =>
      (_selectedRegion == 'Addis Ababa' || _selectedRegion == 'Dire Dawa') ? 'Sub‑city' : 'Zone';
  String get _lowestLabel => 'Woreda';

  // ──────────────────────────────────────────────────────────────────────────────
  //  UI – full screen with illustration
  // ──────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final illustrationSize = (screenHeight * 0.15).clamp(100.0, 150.0);

    Widget content;
    if (_isLoading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_submitted || _vendorStatus == 'pending') {
      content = _buildStatusView(
        icon: Icons.hourglass_bottom,
        iconColor: Colors.orange.shade500,
        title: 'Application Under Review',
        subtitle: 'Your seller application is being reviewed. We\'ll notify you once a decision is made.',
        primaryAction: ElevatedButton(
          onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainScreen()), (route) => false),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('Go to Home', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      );
    } else if (_vendorStatus == 'approved') {
      content = _buildStatusView(
        icon: Icons.check_circle,
        iconColor: Colors.green.shade600,
        title: 'Application Approved!',
        subtitle: 'You can now start selling on ET Marketplace.',
        primaryAction: ElevatedButton(
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SellerDashboardScreen())),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('Go to Dashboard', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        secondaryAction: TextButton(
          onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainScreen()), (route) => false),
          child: const Text('Home', style: TextStyle(color: Colors.grey)),
        ),
      );
    } else if (_vendorStatus == 'rejected') {
      content = _buildStatusView(
        icon: Icons.cancel,
        iconColor: Colors.red.shade500,
        title: 'Application Rejected',
        subtitle: _rejectionReason != null ? 'Reason: $_rejectionReason' : '',
        primaryAction: ElevatedButton(
          onPressed: () { setState(() { _vendorStatus = null; _rejectionReason = null; }); },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('Re‑apply', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      );
    } else {
      content = _buildForm();
    }

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainScreen()), (route) => false),
                    borderRadius: BorderRadius.circular(16),
                    splashColor: AppColors.primary.withOpacity(0.1),
                    highlightColor: AppColors.primary.withOpacity(0.05),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.borderLight.withOpacity(0.8), width: 1),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                      ),
                      child: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary, size: 22),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: illustrationSize + 20,
              child: Center(
                child: SvgPicture.asset(
                  'assets/images/welcome_slide6.svg',
                  width: illustrationSize,
                  height: illustrationSize,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Set Up Your Shop', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF1F2937))),
            const SizedBox(height: 4),
            Text('We need a few more details to get your shop ready.', style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusView({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget primaryAction,
    Widget? secondaryAction,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 48, color: iconColor),
          ),
          const SizedBox(height: 24),
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
          const SizedBox(height: 12),
          if (subtitle.isNotEmpty)
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          const SizedBox(height: 24),
          primaryAction,
          if (secondaryAction != null) ...[const SizedBox(height: 12), secondaryAction],
          const Spacer(flex: 3),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_commissionRate != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.percent, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Platform Commission: $_commissionRate% per order.',
                      style: TextStyle(fontSize: 14, color: Colors.blue.shade800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Fayda ID
          _sectionLabel('Fayda ID (National ID) *'), const SizedBox(height: 8),
          _buildTextField(controller: _nationalIdCtrl, hint: 'e.g. 1234567890', prefixIcon: Icons.credit_card, keyboardType: TextInputType.number, maxLength: 12, validator: (v) { if (v == null || v.isEmpty) return 'Required'; if (!_faydaRegex.hasMatch(v)) return 'Must be 10‑12 digits'; return null; }),
          const SizedBox(height: 4), Text('10‑12 digits (no letters)', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)), const SizedBox(height: 20),

          // Shop Name
          _sectionLabel('Shop Name *'), const SizedBox(height: 8),
          _buildTextField(controller: _shopNameCtrl, hint: 'Your shop name', prefixIcon: Icons.store, validator: (v) => (v == null || v.isEmpty) ? 'Required' : null), const SizedBox(height: 20),

          // Location
          _sectionLabel('Location *'), const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedRegion,
            decoration: InputDecoration(
              hintText: 'Select Region',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFF4400), width: 2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              filled: true, fillColor: Colors.white,
            ),
            items: const [
              DropdownMenuItem(value: 'Addis Ababa', child: Text('Addis Ababa')),
              DropdownMenuItem(value: 'Dire Dawa', child: Text('Dire Dawa')),
              DropdownMenuItem(value: 'Mekelle', child: Text('Mekelle')),
              DropdownMenuItem(value: 'Bahir Dar', child: Text('Bahir Dar')),
              DropdownMenuItem(value: 'Hawassa', child: Text('Hawassa')),
            ],
            onChanged: (v) => setState(() { _selectedRegion = v; _subRegionCtrl.clear(); _lowestCtrl.clear(); }),
            validator: (v) => v == null ? 'Required' : null,
          ),
          if (_selectedRegion != null) ...[
            const SizedBox(height: 12),
            _buildTextField(controller: _subRegionCtrl, hint: _subLabel, prefixIcon: Icons.location_city, validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
            const SizedBox(height: 12),
            _buildTextField(controller: _lowestCtrl, hint: _lowestLabel, prefixIcon: Icons.map, validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
          ],
          const SizedBox(height: 20),

          // ★ Bulk Supplier Card – moved up, visually prominent
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isBulkSupplier ? AppColors.primary.withOpacity(0.05) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isBulkSupplier ? AppColors.primary : Colors.grey.shade300,
                width: _isBulkSupplier ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: _isBulkSupplier ? AppColors.primary : Colors.grey.shade600, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Bulk / Wholesale Supplier', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))),
                      const SizedBox(height: 4),
                      Text(
                        'Check this if you sell large quantities to businesses or resellers. Bulk suppliers may qualify for special commissions and shipping options.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isBulkSupplier,
                  onChanged: (val) => setState(() => _isBulkSupplier = val),
                  activeColor: AppColors.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // TIN Certificate (replaces TIN number)
          _sectionLabel('TIN Certificate *'), const SizedBox(height: 8),
          _buildUploadCard(
            title: 'Upload TIN Certificate',
            subtitle: 'A clear photo or scan of your Tax Identification Number certificate.',
            icon: Icons.article_outlined,
            file: _tinCertificateFile,
            onTap: _pickTinCertificate,
          ),
          const SizedBox(height: 20),

          // Business License (optional, mandatory for bulk)
          _sectionLabel('Business License ${_isBulkSupplier ? '*' : '(optional)'}'), const SizedBox(height: 8),
          _buildUploadCard(
            title: _isBulkSupplier ? 'Upload Business License' : 'Upload Business License (optional)',
            subtitle: _isBulkSupplier
                ? 'Required for bulk/wholesale sellers.'
                : 'Upload if you have one (optional for regular sellers).',
            icon: Icons.description_outlined,
            file: _licenseFile,
            onTap: _pickLicense,
          ),
          const SizedBox(height: 24),

          // Telebirr
          _buildSectionCard(
            title: 'Payout Details',
            subtitle: 'Add your Telebirr number to receive your earnings.',
            icon: Icons.account_balance_wallet_outlined,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: Colors.grey.shade300)),
                        color: Colors.grey.shade50,
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
                      ),
                      child: Row(
                        children: const [
                          Text('🇪🇹', style: TextStyle(fontSize: 18)),
                          SizedBox(width: 4),
                          Text('+251', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: _telebirrCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 9,
                        decoration: const InputDecoration(
                          hintText: '9XX XXX XXX',
                          counterText: '',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(9),
                        ],
                        onChanged: (value) {
                          _telebirrLocalPart = value;
                        },
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          final full = '+251$v';
                          if (!_phoneRegex.hasMatch(full)) return 'Enter a valid Ethiopian number';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text('Ethio Telecom (9XX) or Safaricom (7XX) – 9 digits', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ]),
          ),
          const SizedBox(height: 20),

          // Legal accordions
          _buildLegalAccordion(
            title: 'Seller Agreement & Terms',
            icon: Icons.article_outlined,
            expanded: _showTerms,
            onToggle: () => setState(() => _showTerms = !_showTerms),
            summary: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ET Marketplace connects buyers with independent sellers. You are responsible for quality, legality, and tax obligations.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _showFullLegalModal('Seller Agreement & Terms', 'terms'),
                  child: Text(
                    'Read full Terms →',
                    style: TextStyle(color: const Color(0xFFFF4400), fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildLegalAccordion(
            title: 'Privacy Policy',
            icon: Icons.lock_outline,
            expanded: _showPrivacy,
            onToggle: () => setState(() => _showPrivacy = !_showPrivacy),
            summary: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'We collect phone number, full name, location, shop details, business license.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _showFullLegalModal('Privacy Policy', 'privacy'),
                  child: Text(
                    'Read full Privacy Policy →',
                    style: TextStyle(color: const Color(0xFFFF4400), fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Agreement checkbox
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: CheckboxListTile(
              value: _agreedToTerms,
              onChanged: (val) => setState(() => _agreedToTerms = val ?? false),
              activeColor: const Color(0xFFFF4400),
              title: const Text(
                'I have read and agree to the Seller Agreement, Terms, and Privacy Policy. I understand ET Marketplace is an intermediary and I am responsible for my own tax and legal obligations.',
                style: TextStyle(fontSize: 13),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),

          if (_error != null) ...[const SizedBox(height: 16), Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)), child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 14)))],
          const SizedBox(height: 32),
          SizedBox(height: 52, child: ElevatedButton(onPressed: _isLoading ? null : _submit, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4400), foregroundColor: Colors.white, elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: _isLoading ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Submit for Review', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
          const SizedBox(height: 12),
          TextButton(onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainScreen()), (route) => false), child: const Text('Cancel & go back', style: TextStyle(color: Colors.grey))),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Reusable helpers ────────────────────────────────────────────────────────
  Widget _sectionLabel(String text) => Padding(padding: const EdgeInsets.only(left: 4), child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))));

  Widget _buildTextField({required TextEditingController controller, String? hint, IconData? prefixIcon, TextInputType? keyboardType, int? maxLength, String? Function(String?)? validator}) {
    return TextFormField(controller: controller, keyboardType: keyboardType, maxLength: maxLength, decoration: InputDecoration(hintText: hint, prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: const Color(0xFFFF4400), size: 20) : null, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFF4400), width: 2)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), filled: true, fillColor: Colors.white), validator: validator);
  }

  Widget _buildUploadCard({required String title, required String subtitle, required IconData icon, required XFile? file, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.orange.shade300, width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: Colors.orange.shade50,
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_upload_outlined, color: Colors.orange.shade700, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(file != null ? file!.name : title, style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.w600, fontSize: 14), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required String subtitle, required IconData icon, required Widget child}) {
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: const Color(0xFFFF4400), size: 20)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1F2937))), const SizedBox(height: 2), Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade600))])),]),
      const SizedBox(height: 14), child,
    ]));
  }

  Widget _buildLegalAccordion({
    required String title,
    required IconData icon,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget summary,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: const Color(0xFFFF4400)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.grey),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: summary,
            ),
            crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}