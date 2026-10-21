class Review {
  final int id;
  final int rating;
  final String? title;
  final String comment;
  final String userName;
  final String createdAt;

  Review({
    required this.id,
    required this.rating,
    this.title,
    required this.comment,
    required this.userName,
    required this.createdAt,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as int? ?? 0,
      rating: json['rating'] as int? ?? 0,
      title: json['title'] as String?,
      comment: json['comment'] as String? ?? '',
      userName: json['user']?['name'] ?? 'User',
      createdAt: json['created_at'] ?? '',
    );
  }
}