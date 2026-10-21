// lib/models/filter_params.dart

class FilterParams {
  List<int> categoryIds;
  List<String> brands;
  double? priceMin;
  double? priceMax;
  double? ratingMin;
  List<String> deliveryOptions;
  Map<String, List<String>> dynamicAttributes;

  FilterParams({
    List<int>? categoryIds,
    List<String>? brands,
    this.priceMin,
    this.priceMax,
    this.ratingMin,
    List<String>? deliveryOptions,
    Map<String, List<String>>? dynamicAttributes,
  })  : categoryIds = categoryIds ?? [],
        brands = brands ?? [],
        deliveryOptions = deliveryOptions ?? [],
        dynamicAttributes = dynamicAttributes ?? {};

  /// Creates a deep copy (used by the filter sheet for local state)
  FilterParams copyWith({
    List<int>? categoryIds,
    List<String>? brands,
    double? priceMin,
    double? priceMax,
    double? ratingMin,
    List<String>? deliveryOptions,
    Map<String, List<String>>? dynamicAttributes,
  }) {
    return FilterParams(
      categoryIds: categoryIds ?? List.from(this.categoryIds),
      brands: brands ?? List.from(this.brands),
      priceMin: priceMin ?? this.priceMin,
      priceMax: priceMax ?? this.priceMax,
      ratingMin: ratingMin ?? this.ratingMin,
      deliveryOptions: deliveryOptions ?? List.from(this.deliveryOptions),
      dynamicAttributes:
          dynamicAttributes ?? Map.from(this.dynamicAttributes),
    );
  }

  /// Returns a map ready for API query parameters
  Map<String, dynamic> toQueryParams() {
    final map = <String, dynamic>{};
    if (categoryIds.isNotEmpty) {
      map['category'] = categoryIds.map((e) => e.toString()).join(',');
    }
    if (brands.isNotEmpty) map['brand'] = brands.join(',');
    if (priceMin != null) map['price_min'] = priceMin.toString();
    if (priceMax != null) map['price_max'] = priceMax.toString();
    if (ratingMin != null) map['rating'] = ratingMin.toString();
    if (deliveryOptions.isNotEmpty) {
      map['delivery'] = deliveryOptions.join(',');
    }
    for (final entry in dynamicAttributes.entries) {
      if (entry.value.isNotEmpty) {
        map[entry.key] = entry.value.join(',');
      }
    }
    return map;
  }

  bool get hasActiveFilters =>
      categoryIds.isNotEmpty ||
      brands.isNotEmpty ||
      priceMin != null ||
      priceMax != null ||
      ratingMin != null ||
      deliveryOptions.isNotEmpty ||
      dynamicAttributes.values.any((l) => l.isNotEmpty);
}