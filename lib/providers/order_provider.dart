import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/client.dart';
import '../models/order.dart';

final ordersProvider = FutureProvider<List<Order>>((ref) async {
  final token = await ApiClient.getToken();
  if (token == null || token.isEmpty) {
    return [];
  }
  final response = await ApiClient.instance.get('/orders');
  final List data = response.data;
  return data.map((json) => Order.fromJson(json)).toList();
});

final orderProvider = FutureProvider.family<Order, int>((ref, orderId) async {
  final token = await ApiClient.getToken();
  if (token == null || token.isEmpty) {
    throw Exception('Not authenticated');
  }
  final response = await ApiClient.instance.get('/orders/$orderId');
  return Order.fromJson(response.data);
});