class Category {
  final int id;
  final String name;
  final String? image;
  final int? parentId;
  final List<Category> children;

  Category({
    required this.id,
    required this.name,
    this.image,
    this.parentId,
    this.children = const [],
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return Category(
      id: parseInt(json['id']),
      name: json['name']?.toString() ?? '',
      image: json['image_url']?.toString() ?? json['image']?.toString(),
      parentId: json['parent_id'] != null ? parseInt(json['parent_id']) : null,
      children: json['children'] != null
          ? (json['children'] as List).map((c) => Category.fromJson(c)).toList()
          : [],
    );
  }
}