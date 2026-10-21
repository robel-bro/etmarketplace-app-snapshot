import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import '../models/category.dart';

// Mock Categories
final mockCategories = [
  Category(id: 1, name: 'Electronics', image: 'https://picsum.photos/200?random=1'),
  Category(id: 2, name: 'Fashion', image: 'https://picsum.photos/200?random=2'),
  Category(id: 3, name: 'Home & Garden', image: 'https://picsum.photos/200?random=3'),
  Category(id: 4, name: 'Toys & Hobbies', image: 'https://picsum.photos/200?random=4'),
  Category(id: 5, name: 'Sports', image: 'https://picsum.photos/200?random=5'),
  Category(id: 6, name: 'Beauty', image: 'https://picsum.photos/200?random=6'),
  Category(id: 7, name: 'Automotive', image: 'https://picsum.photos/200?random=7'),
  Category(id: 8, name: 'Jewelry', image: 'https://picsum.photos/200?random=8'),
];

// Mock Banners
final mockBanners = [
  {'image_url': 'https://picsum.photos/800/300?random=10'},
  {'image_url': 'https://picsum.photos/800/300?random=11'},
  {'image_url': 'https://picsum.photos/800/300?random=12'},
];

// Enhanced Mock Products with full details (AliExpress‑style)
final mockTrendingProducts = [
  Product(
    id: 1,
    title: 'Wireless Bluetooth Earbuds TWS with Charging Case',
    price: 1299.99,
    originalPrice: 2499.99,
    imageUrl: 'https://picsum.photos/300/300?random=100',
    images: [
      'https://picsum.photos/400/400?random=100',
      'https://picsum.photos/400/400?random=101',
      'https://picsum.photos/400/400?random=102',
    ],
    rating: 4.5,
    reviewsCount: 1284,
    soldCount: 2300,
    freeShipping: true,
    description: 'High-quality wireless earbuds with crystal clear sound and long battery life. Features touch controls and noise cancellation.',
    colors: ['White', 'Black', 'Blue'],
    sizes: [],
    specifications: {
      'Brand': 'SoundCore',
      'Connectivity': 'Bluetooth 5.0',
      'Battery Life': 'Up to 24 hours',
      'Water Resistance': 'IPX5',
    },
    shippingInfo: 'ETB 450.00 · Delivery: 3-5 days',
    taxInfo: 'Tax included',
  ),
  Product(
    id: 2,
    title: 'Men\'s Casual Slim Fit T‑Shirt Cotton Summer',
    price: 499.99,
    originalPrice: 899.99,
    imageUrl: 'https://picsum.photos/300/300?random=101',
    images: [
      'https://picsum.photos/400/400?random=103',
      'https://picsum.photos/400/400?random=104',
      'https://picsum.photos/400/400?random=105',
    ],
    rating: 4.2,
    reviewsCount: 567,
    soldCount: 980,
    freeShipping: true,
    description: 'Comfortable cotton t-shirt perfect for summer. Slim fit design with round neck and short sleeves.',
    colors: ['Black', 'White', 'Navy', 'Gray'],
    sizes: ['S', 'M', 'L', 'XL', '2XL'],
    specifications: {
      'Material': '100% Cotton',
      'Fit': 'Slim',
      'Sleeve': 'Short Sleeve',
      'Neck': 'Round Neck',
    },
    shippingInfo: 'ETB 250.00 · Delivery: 2-4 days',
    taxInfo: 'Additional taxes may apply',
  ),
  Product(
    id: 3,
    title: 'Smart Watch Fitness Tracker Heart Rate Monitor',
    price: 1899.99,
    originalPrice: 3299.99,
    imageUrl: 'https://picsum.photos/300/300?random=102',
    images: [
      'https://picsum.photos/400/400?random=106',
      'https://picsum.photos/400/400?random=107',
      'https://picsum.photos/400/400?random=108',
    ],
    rating: 4.7,
    reviewsCount: 2356,
    soldCount: 4100,
    freeShipping: false,
    description: 'Advanced smart watch with heart rate monitoring, GPS tracking, and multiple sport modes. 1.4" AMOLED display.',
    colors: ['Black', 'Silver', 'Gold'],
    sizes: ['38mm', '42mm'],
    specifications: {
      'Display': '1.4" AMOLED',
      'Battery': 'Up to 7 days',
      'Water Resistance': '5 ATM',
      'Sensors': 'Heart Rate, GPS, Accelerometer',
    },
    shippingInfo: 'ETB 650.00 · Delivery: 4-6 days',
    taxInfo: 'Tax excluded, add at checkout if applicable',
  ),
  Product(
    id: 4,
    title: 'Portable Mini USB Humidifier with LED Night Light',
    price: 349.99,
    originalPrice: 699.99,
    imageUrl: 'https://picsum.photos/300/300?random=103',
    images: [
      'https://picsum.photos/400/400?random=109',
      'https://picsum.photos/400/400?random=110',
      'https://picsum.photos/400/400?random=111',
    ],
    rating: 4.0,
    reviewsCount: 342,
    soldCount: 520,
    freeShipping: true,
    description: 'Compact humidifier with color-changing LED light. Perfect for home, office, or travel. Ultra-quiet operation.',
    colors: ['White', 'Pink', 'Blue'],
    sizes: [],
    specifications: {
      'Capacity': '300ml',
      'Runtime': 'Up to 8 hours',
      'Noise Level': '< 30dB',
      'Power': 'USB powered',
    },
    shippingInfo: 'ETB 180.00 · Delivery: 3-5 days',
    taxInfo: 'Tax included',
  ),
  Product(
    id: 5,
    title: 'Stainless Steel Vacuum Insulated Water Bottle 500ml',
    price: 749.99,
    originalPrice: 1199.99,
    imageUrl: 'https://picsum.photos/300/300?random=104',
    images: [
      'https://picsum.photos/400/400?random=112',
      'https://picsum.photos/400/400?random=113',
      'https://picsum.photos/400/400?random=114',
    ],
    rating: 4.8,
    reviewsCount: 892,
    soldCount: 1500,
    freeShipping: false,
    description: 'Double-wall vacuum insulated bottle keeps drinks hot for 12 hours or cold for 24 hours. BPA-free stainless steel.',
    colors: ['Black', 'Silver', 'Red', 'Blue'],
    sizes: ['350ml', '500ml', '750ml'],
    specifications: {
      'Material': '18/8 Stainless Steel',
      'Insulation': 'Double-wall vacuum',
      'Hot Retention': '12 hours',
      'Cold Retention': '24 hours',
    },
    shippingInfo: 'ETB 320.00 · Delivery: 3-6 days',
    taxInfo: 'Additional taxes may apply',
  ),
];

// Providers that return mock data (to be replaced with real API later)
final categoriesProvider = Provider<List<Category>>((ref) => mockCategories);

final bannersProvider = Provider<List<Map<String, dynamic>>>((ref) => mockBanners);

final trendingProductsProvider = FutureProvider<List<Product>>((ref) async {
  // Simulate network delay
  await Future.delayed(const Duration(milliseconds: 800));
  return mockTrendingProducts;
});

// Additional provider for single product detail (matches productProvider in detail screen)
final productDetailProvider = FutureProvider.family<Product, int>((ref, productId) async {
  await Future.delayed(const Duration(milliseconds: 500));
  final product = mockTrendingProducts.firstWhere((p) => p.id == productId);
  return product;
});