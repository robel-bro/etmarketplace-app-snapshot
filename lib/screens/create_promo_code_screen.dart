// lib/screens/create_promo_code_screen.dart
import 'package:flutter/material.dart';

// ------------------------------------------------------------
// 🎨 MAX‑CONTRAST DESIGN SYSTEM
// ------------------------------------------------------------
class AppTheme {
  static const Color primaryOrange = Color(0xFFFF4400);
  static const Color strongRed = Color(0xFFEF4444);
  static const Color premiumBlack = Color(0xFF000000);
  static const Color whiteBackground = Color(0xFFFFFFFF);
  static const Color cardWhite = Color(0xFFFFFFFF);
  static const Color subtleGrey = Color(0xFF555555);
  static const Color dividerColor = Color(0xFFE0E0E0);
  static const Color lightGrey = Color(0xFFF2F2F2);
}

class CreatePromoCodeScreen extends StatefulWidget {
  const CreatePromoCodeScreen({Key? key}) : super(key: key);
  @override
  State<CreatePromoCodeScreen> createState() => _CreatePromoCodeScreenState();
}

class _CreatePromoCodeScreenState extends State<CreatePromoCodeScreen> {
  final _formKey = GlobalKey<FormState>();
  String _code = '', _discountValue = '', _minOrder = '', _usageLimit = '';
  String _discountType = 'percentage'; // 'percentage' or 'fixed'
  DateTime? _startDate, _endDate;

  Future<void> _pickDate(bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primaryOrange,
            onPrimary: Colors.white,
            surface: AppTheme.cardWhite,
            onSurface: AppTheme.premiumBlack,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(_startDate!)) {
            _endDate = _startDate!.add(const Duration(days: 7));
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.whiteBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.whiteBackground,
        elevation: 0,
        title: const Text('Create Promo Code',
            style: TextStyle(
                color: AppTheme.premiumBlack,
                fontWeight: FontWeight.w700,
                fontSize: 20)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.premiumBlack),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppTheme.dividerColor, height: 1),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _sectionLabel('Promo Details'),
            const SizedBox(height: 12),

            // Code
            _buildTextFormField(
              label: 'Promo Code',
              hint: 'e.g. SUMMER20',
              validator: (v) => v!.isEmpty ? 'Required' : null,
              onSaved: (v) => _code = v ?? '',
            ),
            const SizedBox(height: 16),

            // Discount Type
            _buildDropdownFormField<String>(
              label: 'Discount Type',
              value: _discountType,
              items: const [
                DropdownMenuItem(
                    value: 'percentage', child: Text('Percentage (%)')),
                DropdownMenuItem(
                    value: 'fixed', child: Text('Fixed Amount (ETB)')),
              ],
              onChanged: (v) => setState(() => _discountType = v!),
            ),
            const SizedBox(height: 16),

            // Discount Value
            _buildTextFormField(
              label: _discountType == 'percentage'
                  ? 'Discount (%)'
                  : 'Discount (ETB)',
              hint: _discountType == 'percentage' ? '10' : '50',
              keyboardType: TextInputType.number,
              validator: (v) => v!.isEmpty ? 'Required' : null,
              onSaved: (v) => _discountValue = v ?? '',
            ),
            const SizedBox(height: 16),

            // Minimum Order Amount
            _buildTextFormField(
              label: 'Minimum Order (ETB)',
              hint: '0',
              keyboardType: TextInputType.number,
              initialValue: '0',
              onSaved: (v) => _minOrder = v ?? '',
            ),
            const SizedBox(height: 16),

            // Usage Limit
            _buildTextFormField(
              label: 'Usage Limit',
              hint: 'e.g. 100',
              keyboardType: TextInputType.number,
              onSaved: (v) => _usageLimit = v ?? '',
            ),
            const SizedBox(height: 20),

            // Validity period
            _sectionLabel('Validity Period'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildDateField(
                    label: 'Start Date',
                    date: _startDate,
                    onTap: () => _pickDate(true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDateField(
                    label: 'End Date',
                    date: _endDate,
                    onTap: () => _pickDate(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Submit
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    _formKey.currentState!.save();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Promo code created!'),
                          backgroundColor: AppTheme.premiumBlack),
                    );
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                  shadowColor:
                      AppTheme.primaryOrange.withOpacity(0.3),
                ),
                child: const Text('Create Promo Code',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppTheme.premiumBlack,
      ),
    );
  }

  Widget _buildTextFormField({
    required String label,
    String? hint,
    TextInputType? keyboardType,
    FormFieldSetter<String>? onSaved,
    FormFieldValidator<String>? validator,
    String? initialValue,
  }) {
    return TextFormField(
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(
            color: AppTheme.premiumBlack,
            fontSize: 15,
            fontWeight: FontWeight.w600),
        hintStyle: const TextStyle(color: AppTheme.subtleGrey, fontSize: 14),
        filled: true,
        fillColor: AppTheme.cardWhite,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppTheme.dividerColor, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppTheme.dividerColor, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppTheme.primaryOrange, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppTheme.strongRed, width: 1.5),
        ),
      ),
      keyboardType: keyboardType,
      onSaved: onSaved,
      validator: validator,
      initialValue: initialValue,
      style: const TextStyle(color: AppTheme.premiumBlack, fontSize: 15),
    );
  }

  Widget _buildDropdownFormField<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
            color: AppTheme.premiumBlack,
            fontSize: 15,
            fontWeight: FontWeight.w600),
        filled: true,
        fillColor: AppTheme.cardWhite,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppTheme.dividerColor, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppTheme.dividerColor, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppTheme.primaryOrange, width: 2),
        ),
      ),
      icon: const Icon(Icons.arrow_drop_down_rounded,
          color: AppTheme.premiumBlack),
      style: const TextStyle(color: AppTheme.premiumBlack, fontSize: 15),
      dropdownColor: AppTheme.cardWhite,
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
              color: AppTheme.premiumBlack,
              fontSize: 15,
              fontWeight: FontWeight.w600),
          filled: true,
          fillColor: AppTheme.cardWhite,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: AppTheme.dividerColor, width: 1.2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: AppTheme.dividerColor, width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: AppTheme.primaryOrange, width: 2),
          ),
          suffixIcon: const Icon(Icons.calendar_today,
              color: AppTheme.premiumBlack, size: 20),
        ),
        child: Text(
          date != null
              ? '${date.day}/${date.month}/${date.year}'
              : 'Select date',
          style: TextStyle(
            color: date != null ? AppTheme.premiumBlack : AppTheme.subtleGrey,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}