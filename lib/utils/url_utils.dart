// 📁 lib/utils/url_utils.dart
import '../api/client.dart';

String resolveUrl(String rawUrl) {
  if (rawUrl.isEmpty) return 'https://placehold.co/600x400?text=No+Image';
  if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) return rawUrl;
  final base = ApiClient.instance.dio.options.baseUrl;
  final cleanBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final cleanPath = rawUrl.startsWith('/') ? rawUrl : '/$rawUrl';
  return '$cleanBase$cleanPath';
}