// 📁 lib/screens/seller/settings_screen.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../api/client.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

class SellerSettingsScreen extends ConsumerStatefulWidget {
  const SellerSettingsScreen({Key? key}) : super(key: key);
  @override
  ConsumerState<SellerSettingsScreen> createState() => _SellerSettingsScreenState();
}

class _SellerSettingsScreenState extends ConsumerState<SellerSettingsScreen> {
  final _picker = ImagePicker();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _nationalIdCtrl = TextEditingController();
  final _tinCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _accountNumCtrl = TextEditingController();
  final _accountNameCtrl = TextEditingController();
  final _telebirrCtrl = TextEditingController();

  String? _existingLogoUrl;
  String? _existingBannerUrl;
  String? _licenseUrl;
  XFile? _newLogo;
  XFile? _newBanner;

  bool _emailOrders = true;
  bool _emailPayouts = true;
  bool _smsAlerts = false;

  bool _isLoading = true;
  bool _isSavingProfile = false;
  bool _isSavingPayout = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final l10n = AppLocalizations.of(context);
    try {
      final authUser = ref.read(authProvider).value;
      final vendorRes = await ApiClient.instance.get('/api/v1/vendors/me');
      final vendorData = vendorRes.data as Map<String, dynamic>;

      if (mounted) {
        setState(() {
          _nameCtrl.text = vendorData['business_name'] ?? '';
          _phoneCtrl.text = authUser?.phone ?? vendorData['phone'] ?? '';
          _descCtrl.text = vendorData['description'] ?? '';
          _nationalIdCtrl.text = vendorData['national_id'] ?? '';
          _tinCtrl.text = vendorData['tin'] ?? '';
          _locationCtrl.text = vendorData['business_address'] ?? '';
          _bankNameCtrl.text = vendorData['bank_name'] ?? '';
          _accountNumCtrl.text = vendorData['account_number'] ?? '';
          _accountNameCtrl.text = vendorData['account_name'] ?? '';
          _telebirrCtrl.text = vendorData['telebirr_number'] ?? '';
          _existingLogoUrl = vendorData['logo_url'];
          _existingBannerUrl = vendorData['banner_url'];
          _licenseUrl = vendorData['license_document_url'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = l10n.translate('failed_load_settings');
        });
      }
    }
  }

  Future<void> _saveStoreProfile() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _isSavingProfile = true);
    try {
      // 1. Save phone to user profile
      await ApiClient.instance.patch('/api/v1/profile', data: {
        'user[phone]': _phoneCtrl.text.trim(),
      });

      // 2. Save vendor profile
      final vendorFields = <String, dynamic>{
        'vendor[business_name]': _nameCtrl.text.trim(),
        'vendor[description]': _descCtrl.text.trim(),
      };
      if (_newLogo != null) {
        final bytes = await _newLogo!.readAsBytes();
        vendorFields['vendor[logo]'] =
            MultipartFile.fromBytes(bytes, filename: _newLogo!.name);
      }
      if (_newBanner != null) {
        final bytes = await _newBanner!.readAsBytes();
        vendorFields['vendor[banner]'] =
            MultipartFile.fromBytes(bytes, filename: _newBanner!.name);
      }
      await ApiClient.instance.put('/api/v1/vendors/me', data: FormData.fromMap(vendorFields));

      await _loadData();
      _showSnack(l10n.translate('store_profile_saved'));
    } catch (e) {
      _showSnack(
        l10n.translate('save_failed').replaceAll('{section}', l10n.translate('store_profile')),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<void> _savePayoutMethods() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _isSavingPayout = true);
    try {
      await ApiClient.instance.put('/api/v1/vendors/me', data: {
        'vendor': {
          'bank_name': _bankNameCtrl.text.trim(),
          'account_number': _accountNumCtrl.text.trim(),
          'account_name': _accountNameCtrl.text.trim(),
          'telebirr_number': _telebirrCtrl.text.trim(),
        }
      });
      _showSnack(l10n.translate('payout_methods_saved'));
    } catch (e) {
      _showSnack(
        l10n.translate('save_failed').replaceAll('{section}', l10n.translate('payout_methods')),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSavingPayout = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
      ),
    );
  }

  Future<void> _pickLogo() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 600);
    if (file != null) setState(() => _newLogo = file);
  }

  Future<void> _pickBanner() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1200);
    if (file != null) setState(() => _newBanner = file);
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _descCtrl.dispose();
    _nationalIdCtrl.dispose(); _tinCtrl.dispose(); _locationCtrl.dispose();
    _bankNameCtrl.dispose(); _accountNumCtrl.dispose(); _accountNameCtrl.dispose();
    _telebirrCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    if (_error != null)
      return Scaffold(
        body: Center(child: Text(_error!, style: textTheme.bodyLarge?.copyWith(color: AppColors.error))),
      );

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: Text(l10n.translate('settings_title'), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, 40),
        children: [
          // Store Profile
          _buildSectionCard(
            title: l10n.translate('store_profile'),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _pickLogo,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage: _newLogo != null
                              ? (kIsWeb ? NetworkImage(_newLogo!.path) : FileImage(File(_newLogo!.path)) as ImageProvider)
                              : (_existingLogoUrl != null && _existingLogoUrl!.isNotEmpty ? NetworkImage(_existingLogoUrl!) : null),
                          child: (_newLogo == null && (_existingLogoUrl == null || _existingLogoUrl!.isEmpty))
                              ? const Icon(Icons.store, size: 30, color: AppColors.textMuted)
                              : null,
                        ),
                        Positioned(
                          bottom: 0, right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: _buildField(controller: _nameCtrl, label: l10n.translate('store_name_label'), hint: l10n.translate('store_name_hint'), textTheme: textTheme)),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _buildLabel(l10n.translate('store_banner_label'), textTheme),
              const SizedBox(height: AppSpacing.xs),
              GestureDetector(
                onTap: _pickBanner,
                child: Container(
                  height: 130,
                  decoration: BoxDecoration(
                    color: AppColors.hoverState,
                    borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: _newBanner != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                          child: kIsWeb
                              ? Image.network(_newBanner!.path, fit: BoxFit.cover, width: double.infinity)
                              : Image.file(File(_newBanner!.path), fit: BoxFit.cover, width: double.infinity),
                        )
                      : _existingBannerUrl != null && _existingBannerUrl!.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                              child: Image.network(_existingBannerUrl!, fit: BoxFit.cover, width: double.infinity),
                            )
                          : Center(child: Text(l10n.translate('upload_banner_hint'), style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted))),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _buildField(controller: _phoneCtrl, label: l10n.translate('phone_label'), hint: l10n.translate('phone_hint'), keyboardType: TextInputType.phone, textTheme: textTheme),
              const SizedBox(height: AppSpacing.md),
              _buildField(controller: _descCtrl, label: l10n.translate('description_label'), hint: l10n.translate('description_hint'), maxLines: 3, textTheme: textTheme),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: _isSavingProfile ? null : _saveStoreProfile,
                  style: AppComponentStyles.primaryButton,
                  child: _isSavingProfile
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(l10n.translate('save_changes'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Identity (one‑time)
          _buildSectionCard(
            title: l10n.translate('seller_identity'),
            children: [
              _buildField(
                controller: _nationalIdCtrl,
                label: l10n.translate('national_id_label'),
                hint: l10n.translate('national_id_hint'),
                readOnly: _nationalIdCtrl.text.isNotEmpty,
                textTheme: textTheme,
              ),
              const SizedBox(height: AppSpacing.md),
              _buildField(
                controller: _tinCtrl,
                label: l10n.translate('tin_label'),
                hint: l10n.translate('tin_hint'),
                readOnly: _tinCtrl.text.isNotEmpty,
                textTheme: textTheme,
              ),
              const SizedBox(height: AppSpacing.md),
              _buildField(
                controller: _locationCtrl,
                label: l10n.translate('location_label'),
                hint: l10n.translate('location_hint'),
                readOnly: _locationCtrl.text.isNotEmpty,
                textTheme: textTheme,
              ),
              if (_licenseUrl != null && _licenseUrl!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _buildLabel(l10n.translate('business_license_label'), textTheme),
                const SizedBox(height: AppSpacing.xs),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                  child: Image.network(_licenseUrl!, fit: BoxFit.cover, height: 120, width: double.infinity),
                ),
                const SizedBox(height: 4),
                Text(l10n.translate('license_on_file'), style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Payout Methods
          _buildSectionCard(
            title: l10n.translate('payout_methods'),
            children: [
              _buildField(controller: _bankNameCtrl, label: l10n.translate('bank_name_label'), hint: l10n.translate('bank_name_hint'), textTheme: textTheme),
              const SizedBox(height: AppSpacing.md),
              _buildField(controller: _accountNumCtrl, label: l10n.translate('account_number_label'), hint: l10n.translate('account_number_hint'), textTheme: textTheme),
              const SizedBox(height: AppSpacing.md),
              _buildField(controller: _accountNameCtrl, label: l10n.translate('account_holder_label'), hint: l10n.translate('account_holder_hint'), textTheme: textTheme),
              const SizedBox(height: AppSpacing.md),
              _buildField(controller: _telebirrCtrl, label: l10n.translate('telebirr_label'), hint: l10n.translate('telebirr_hint'), keyboardType: TextInputType.phone, textTheme: textTheme),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: _isSavingPayout ? null : _savePayoutMethods,
                  style: AppComponentStyles.primaryButton,
                  child: _isSavingPayout
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(l10n.translate('save_payout_methods'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Notification Preferences
          _buildSectionCard(
            title: l10n.translate('notifications'),
            children: [
              _buildCheckbox(l10n.translate('email_order_notification'), _emailOrders, (v) => setState(() => _emailOrders = v!), textTheme),
              const SizedBox(height: AppSpacing.xs),
              _buildCheckbox(l10n.translate('email_payout_notification'), _emailPayouts, (v) => setState(() => _emailPayouts = v!), textTheme),
              const SizedBox(height: AppSpacing.xs),
              _buildCheckbox(l10n.translate('sms_alert_notification'), _smsAlerts, (v) => setState(() => _smsAlerts = v!), textTheme),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () => _showSnack(l10n.translate('preferences_saved')),
                  style: AppComponentStyles.primaryButton,
                  child: Text(l10n.translate('save_preferences'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.md),
          ...children,
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    bool readOnly = false,
    required TextTheme textTheme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          readOnly: readOnly,
          enabled: !readOnly,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            filled: true,
            fillColor: readOnly ? Colors.grey.shade100 : AppColors.hoverState,
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppShapes.radiusSm),
              borderSide: const BorderSide(color: AppColors.borderLight),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppShapes.radiusSm),
              borderSide: const BorderSide(color: AppColors.borderLight),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppShapes.radiusSm),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
          style: textTheme.bodyMedium?.copyWith(color: readOnly ? AppColors.textMuted : AppColors.textPrimary),
        ),
      ],
    );
  }

  Widget _buildLabel(String text, TextTheme textTheme) {
    return Text(text, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary));
  }

  Widget _buildCheckbox(String title, bool value, ValueChanged<bool?> onChanged, TextTheme textTheme) {
    return CheckboxListTile(
      title: Text(title, style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
      value: value,
      onChanged: onChanged,
      activeColor: AppColors.primary,
      checkColor: Colors.white,
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
    );
  }
}