class Collection {
  final int id;
  final String name;
  final String? description;
  final String? image;
  final List<int>? productIds;

  Collection({
    required this.id,
    required this.name,
    this.description,
    this.image,
    this.productIds,
  });

  factory Collection.fromJson(Map<String, dynamic> json) {
    return Collection(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      image: json['image'] as String?,
      productIds: json['product_ids'] != null ? List<int>.from(json['product_ids']) : null,
    );
  }
}