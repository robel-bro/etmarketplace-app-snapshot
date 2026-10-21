import 'package:intl/intl.dart';

class FormatUtils {
  static final NumberFormat _currency = NumberFormat('#,##0.00', 'en_US');

  /// Formats any numeric value (int, double, String) into "ETB 1,800.00"
  static String price(dynamic value) {
    if (value == null) return 'ETB 0.00';
    double amount = 0.0;
    if (value is String) {
      amount = double.tryParse(value) ?? 0.0;
    } else if (value is num) {
      amount = value.toDouble();
    }
    return 'ETB ${_currency.format(amount)}';
  }
}