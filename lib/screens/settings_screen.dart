// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';   // ← AppColors, AppSpacing, etc.
import 'legal_page_viewer.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _pushEnabled = true;
  bool _emailEnabled = false;
  bool _smsEnabled = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final authState = ref.watch(authProvider);
    final user = authState.valueOrNull;
    final currentLocale = ref.watch(localeProvider) ?? const Locale('en');

    final String currentLanguageLabel;
    switch (currentLocale.languageCode) {
      case 'am':
        currentLanguageLabel = l10n.translate('amharic');
        break;
      case 'om':
        currentLanguageLabel = l10n.translate('oromo');
        break;
      case 'ti':
        currentLanguageLabel = l10n.translate('tigrinya');
        break;
      default:
        currentLanguageLabel = l10n.translate('english');
    }

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0.5,
        title: Text(
          l10n.translate('settings'),
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          // ── Language ────────────────────────────
          _buildSectionHeader(l10n.translate('language')),
          _buildMenuCard([
            ListTile(
              leading: Icon(PhosphorIcons.translate(PhosphorIconsStyle.regular),
                  color: AppColors.textPrimary.withOpacity(0.65), size: 20),
              title: Text(l10n.translate('settings_language'),
                  style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      fontSize: 14)),
              subtitle: Text(currentLanguageLabel,
                  style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted, fontSize: 12)),
              trailing: Icon(PhosphorIcons.caretRight(PhosphorIconsStyle.regular),
                  color: Colors.grey.shade400, size: 18),
              onTap: _showLanguagePicker,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
              minLeadingWidth: 24,
              dense: true,
              visualDensity: VisualDensity.compact,
            ),
          ]),

          const SizedBox(height: 20),

          // ── Notifications ──────────────────────
          _buildSectionHeader(l10n.translate('notifications')),
          _buildMenuCard([
            SwitchListTile(
              secondary: Icon(PhosphorIcons.bellRinging(PhosphorIconsStyle.regular),
                  color: AppColors.textPrimary.withOpacity(0.65), size: 20),
              title: Text(l10n.translate('push_notifications'),
                  style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      fontSize: 14)),
              value: _pushEnabled,
              onChanged: (val) => setState(() => _pushEnabled = val),
              activeColor: AppColors.primary,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            if (user?.email != null && user!.email!.isNotEmpty)
              SwitchListTile(
                secondary: Icon(PhosphorIcons.envelope(PhosphorIconsStyle.regular),
                    color: AppColors.textPrimary.withOpacity(0.65), size: 20),
                title: Text(l10n.translate('email_notifications'),
                    style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        fontSize: 14)),
                value: _emailEnabled,
                onChanged: (val) => setState(() => _emailEnabled = val),
                activeColor: AppColors.primary,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            SwitchListTile(
              secondary: Icon(PhosphorIcons.chatCenteredText(PhosphorIconsStyle.regular),
                  color: AppColors.textPrimary.withOpacity(0.65), size: 20),
              title: Text(l10n.translate('sms_notifications'),
                  style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      fontSize: 14)),
              value: _smsEnabled,
              onChanged: (val) => setState(() => _smsEnabled = val),
              activeColor: AppColors.primary,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ]),

          const SizedBox(height: 20),

          // ── Legal & Policies ──────────────────
          _buildSectionHeader(l10n.translate('legal_policies')),
          _buildMenuCard([
            _buildLegalItem(l10n.translate('terms_of_service'), 'terms'),
            _buildLegalItem(l10n.translate('privacy_policy'), 'privacy'),
            _buildLegalItem(l10n.translate('cookie_policy'), 'cookies'),
            _buildLegalItem(l10n.translate('buyer_protection'), 'buyer-protection'),
            _buildLegalItem(l10n.translate('ip_policy'), 'ip-policy'),
            _buildLegalItem(l10n.translate('shipping_delivery'), 'shipping-returns'),
          ]),

          const SizedBox(height: 40),

          // ── Logout ────────────────────────────
          if (user != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon(PhosphorIcons.signOut(PhosphorIconsStyle.regular), size: 18),
                label: Text(l10n.translate('logout')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  await ref.read(authProvider.notifier).logout();
                  if (mounted) {
                    Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildMenuCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildLegalItem(String title, String keyName) {
    return ListTile(
      leading: Icon(PhosphorIcons.article(PhosphorIconsStyle.regular),
          color: AppColors.textPrimary.withOpacity(0.65), size: 20),
      title: Text(title,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              fontSize: 14)),
      trailing: Icon(PhosphorIcons.caretRight(PhosphorIconsStyle.regular),
          color: Colors.grey.shade400, size: 18),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => LegalPageViewer(keyName: keyName))),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      minLeadingWidth: 24,
      dense: true,
      visualDensity: VisualDensity.compact,
    );
  }

  void _showLanguagePicker() {
    final l10n = AppLocalizations.of(context);
    final currentLocale = ref.read(localeProvider) ?? const Locale('en');

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.translate('choose_language'),
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              RadioListTile<Locale>(
                title: Text(l10n.translate('english')),
                value: const Locale('en'),
                groupValue: currentLocale,
                onChanged: (locale) {
                  if (locale != null) {
                    ref.read(localeProvider.notifier).setLocale(locale);
                    Navigator.pop(ctx);
                  }
                },
              ),
              RadioListTile<Locale>(
                title: Text(l10n.translate('amharic')),
                value: const Locale('am'),
                groupValue: currentLocale,
                onChanged: (locale) {
                  if (locale != null) {
                    ref.read(localeProvider.notifier).setLocale(locale);
                    Navigator.pop(ctx);
                  }
                },
              ),
              RadioListTile<Locale>(
                title: Text(l10n.translate('oromo')),
                value: const Locale('om'),
                groupValue: currentLocale,
                onChanged: (locale) {
                  if (locale != null) {
                    ref.read(localeProvider.notifier).setLocale(locale);
                    Navigator.pop(ctx);
                  }
                },
              ),
              RadioListTile<Locale>(
                title: Text(l10n.translate('tigrinya')),
                value: const Locale('ti'),
                groupValue: currentLocale,
                onChanged: (locale) {
                  if (locale != null) {
                    ref.read(localeProvider.notifier).setLocale(locale);
                    Navigator.pop(ctx);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}