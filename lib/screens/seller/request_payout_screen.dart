// 📁 lib/screens/seller/request_payout_screen.dart
import 'package:flutter/material.dart';
import '../../api/client.dart';
import '../../theme/app_theme.dart';

class RequestPayoutScreen extends StatefulWidget {
  final double maxAmount;
  const RequestPayoutScreen({Key? key, required this.maxAmount}) : super(key: key);

  @override
  State<RequestPayoutScreen> createState() => _RequestPayoutScreenState();
}

class _RequestPayoutScreenState extends State<RequestPayoutScreen> {
  final _amountCtrl = TextEditingController();
  final _periodStartCtrl = TextEditingController();
  final _periodEndCtrl = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      _showSnack('Please enter a valid amount', AppColors.error);
      return;
    }
    if (amount > widget.maxAmount) {
      _showSnack('Amount exceeds available balance', AppColors.error);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ApiClient.instance.post('/seller/payouts', data: {
        'amount': amount,
        'period_start': _periodStartCtrl.text,
        'period_end': _periodEndCtrl.text,
      });
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Request failed. Please try again.', AppColors.error);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _periodStartCtrl.dispose();
    _periodEndCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: Text('Request Payout', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Available Balance Card
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(AppShapes.radiusMd),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  'Available Balance',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                Text(
                  'ETB ${widget.maxAmount.toStringAsFixed(2)}',
                  style: textTheme.headlineMedium?.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You can request any amount up to this balance',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Amount Field
          _buildSectionLabel('Amount (ETB) *', textTheme),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
            decoration: _inputDecoration('0.00', textTheme),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Period Fields (optional)
          _buildSectionLabel('Period (optional)', textTheme),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _periodStartCtrl,
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
                  decoration: _inputDecoration('Start date (YYYY-MM-DD)', textTheme),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _periodEndCtrl,
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
                  decoration: _inputDecoration('End date (YYYY-MM-DD)', textTheme),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Submit Button
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: AppComponentStyles.primaryButton.copyWith(
              padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 16)),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Submit Request',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text, TextTheme textTheme) {
    return Text(
      text,
      style: textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, TextTheme textTheme) {
    return InputDecoration(
      hintText: hint,
      hintStyle: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
      filled: true,
      fillColor: AppColors.hoverState,
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
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }
}