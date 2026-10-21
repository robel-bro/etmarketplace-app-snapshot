import 'package:flutter/foundation.dart';
import '../api/client.dart';
import '../models/review.dart';

class ReviewService {
  static Future<List<Review>> getProductReviews(int productId) async {
    final response = await ApiClient.instance.get('/products/$productId/reviews');
    return (response.data as List).map((j) => Review.fromJson(j)).toList();
  }

  static Future<List<Review>> getVendorReviews(int vendorId) async {
    final response = await ApiClient.instance.get('/vendors/$vendorId/reviews');
    return (response.data as List).map((j) => Review.fromJson(j)).toList();
  }

  static Future<List<Review>> getPackageReviews(int packageId) async {
    final response = await ApiClient.instance.get('/packages/$packageId/reviews');
    return (response.data as List).map((j) => Review.fromJson(j)).toList();
  }

  static Future<void> submitReview({
    int? productId,
    int? vendorId,
    int? packageId,
    required int rating,
    String? title,
    required String comment,
  }) async {
    final data = <String, dynamic>{
      'rating': rating,
      'comment': comment,
    };
    if (productId != null) data['product_id'] = productId;
    if (vendorId != null) data['vendor_id'] = vendorId;
    if (packageId != null) {
      data['reviewable_type'] = 'Package';
      data['reviewable_id'] = packageId;
    }
    if (title != null) data['title'] = title;

    await ApiClient.instance.post('/reviews', data: {'review': data});
  }
}