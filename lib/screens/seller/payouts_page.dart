// 📁 lib/screens/seller/payouts_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../api/client.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'request_payout_screen.dart';

class SellerPayoutsScreen extends ConsumerStatefulWidget {
  const SellerPayoutsScreen({Key? key}) : super(key: key);
  @override
  ConsumerState<SellerPayoutsScreen> createState() => _SellerPayoutsScreenState();
}

class _SellerPayoutsScreenState extends ConsumerState<SellerPayoutsScreen> {
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _payouts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchPayouts());
  }

  Future<void> _fetchPayouts() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.get('/seller/payouts');
      final data = res.data;

      setState(() {
        _summary = data['summary'] as Map<String, dynamic>? ?? {};
        final payoutsRaw = data['payouts'];
        if (payoutsRaw is List) {
          _payouts = payoutsRaw.cast<Map<String, dynamic>>();
        } else {
          _payouts = [];
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = l10n.translate('failed_load_payouts');
      });
    }
  }

  Future<void> _requestPayout() async {
    final l10n = AppLocalizations.of(context);
    final available = (_summary?['available'] ?? 0).toDouble();
    if (available <= 0) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RequestPayoutScreen(maxAmount: available),
      ),
    );

    if (result == true) {
      _fetchPayouts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('payout_requested_success')),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        title: Text(
          l10n.translate('payouts_title'),
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: false,
      ),
      body: _buildBody(l10n, textTheme),
    );
  }

  Widget _buildBody(AppLocalizations l10n, TextTheme textTheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: textTheme.bodyLarge?.copyWith(color: AppColors.error)));
    }

    final available = (_summary?['available'] ?? 0).toDouble();
    final totalEarned = (_summary?['total_earned'] ?? 0).toDouble();
    final pending = (_summary?['pending'] ?? 0).toDouble();
    final paid = (_summary?['paid'] ?? 0).toDouble();
    final held = (_summary?['held'] ?? 0).toDouble();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Balance Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryActive],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppShapes.radiusMd),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  l10n.translate('available_balance'),
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ETB ${available.toStringAsFixed(2)}',
                  style: textTheme.headlineMedium?.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: available > 0 ? _requestPayout : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      l10n.translate('request_payout'),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Summary chips
          Row(
            children: [
              Expanded(
                child: _buildChip(
                  l10n.translate('total_earned'),
                  totalEarned,
                  PhosphorIcons.money(PhosphorIconsStyle.regular),
                  AppColors.primary,
                  textTheme,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _buildChip(
                  l10n.translate('pending'),
                  pending,
                  PhosphorIcons.clock(PhosphorIconsStyle.regular),
                  AppColors.warning,
                  textTheme,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _buildChip(
                  l10n.translate('paid'),
                  paid,
                  PhosphorIcons.checkCircle(PhosphorIconsStyle.regular),
                  AppColors.success,
                  textTheme,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _buildChip(
                  l10n.translate('held'),
                  held,
                  PhosphorIcons.lock(PhosphorIconsStyle.regular),
                  AppColors.textSecondary,
                  textTheme,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // Payout History
          Row(
            children: [
              Text(
                l10n.translate('payout_history'),
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                l10n.translate('payouts_count').replaceAll('{count}', _payouts.length.toString()),
                style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          if (_payouts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Center(
                child: Text(
                  l10n.translate('no_payouts_yet'),
                  style: textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
                ),
              ),
            )
          else
            ...(_payouts.map((p) => _buildPayoutRow(p, textTheme, l10n))),
        ],
      ),
    );
  }

  Widget _buildChip(
    String label,
    double amount,
    IconData icon,
    Color color,
    TextTheme textTheme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppShapes.radiusSm),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'ETB ${amount.toStringAsFixed(2)}',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayoutRow(Map<String, dynamic> payout, TextTheme textTheme, AppLocalizations l10n) {
    final date = payout['date'] ?? '';
    final amount = (payout['amount'] ?? 0).toDouble();
    final status = payout['status'] ?? 'pending';
    final isPaid = status == 'paid';
    final isRejected = status == 'rejected';
    final isNegative = amount < 0;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isNegative
                  ? AppColors.error.withOpacity(0.1)
                  : isPaid
                      ? AppColors.success.withOpacity(0.1)
                      : isRejected
                          ? AppColors.error.withOpacity(0.1)
                          : AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppShapes.radiusSm),
            ),
            child: Icon(
              isNegative
                  ? PhosphorIcons.warningCircle(PhosphorIconsStyle.regular)
                  : isPaid
                      ? PhosphorIcons.checkCircle(PhosphorIconsStyle.regular)
                      : isRejected
                          ? PhosphorIcons.xCircle(PhosphorIconsStyle.regular)
                          : PhosphorIcons.hourglass(PhosphorIconsStyle.regular),
              color: isNegative
                  ? AppColors.error
                  : isPaid
                      ? AppColors.success
                      : isRejected
                          ? AppColors.error
                          : AppColors.warning,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isPaid
                            ? AppColors.success.withOpacity(0.1)
                            : isRejected
                                ? AppColors.error.withOpacity(0.1)
                                : AppColors.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isPaid
                              ? AppColors.success
                              : isRejected
                                  ? AppColors.error
                                  : AppColors.warning,
                        ),
                      ),
                    ),
                    if (isNegative) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                        ),
                        child: const Text(
                          'PENALTY',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Text(
            '${isNegative ? "- " : ""}ETB ${amount.abs().toStringAsFixed(2)}',
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isNegative ? AppColors.error : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}