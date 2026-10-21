// lib/api/filter_options_service.dart
import '../api/client.dart';

class FilterOptionsService {
  static Future<Map<String, dynamic>> fetchFilterOptions({
    Map<String, String>? context,
    Map<String, dynamic>? currentFilters,
  }) async {
    final params = <String, dynamic>{};
    if (context != null) params.addAll(context);
    if (currentFilters != null) params.addAll(currentFilters);

    // Remove empty/null values
    params.removeWhere((key, value) =>
        value == null ||
        (value is String && value.isEmpty) ||
        (value is List && value.isEmpty));

    // Determine the correct endpoint based on the resource type.
    // The 'type' key is only used for routing; it is removed from the query params
    // before the actual request is sent.
    final isPackage = params.remove('type') == 'package';
    final endpoint = isPackage ? '/packages/filter_options' : '/products/filter_options';

    final response = await ApiClient.instance.get(
      endpoint,
      queryParameters: params.isNotEmpty ? params : null,
    );

    final data = response.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    } else {
      throw Exception('Unexpected response format');
    }
  }
}