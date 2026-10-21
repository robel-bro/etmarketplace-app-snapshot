// lib/widgets/search_bar.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/client.dart';
import '../screens/search_screen.dart';
import '../screens/product_detail_screen.dart';
import '../screens/package_detail_screen.dart';

class RotatingSearchBar extends ConsumerStatefulWidget {
  const RotatingSearchBar({Key? key}) : super(key: key);

  @override
  ConsumerState<RotatingSearchBar> createState() => _RotatingSearchBarState();
}

class _RotatingSearchBarState extends ConsumerState<RotatingSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<String> _hints = ['Search products...'];
  int _currentIndex = 0;
  Timer? _hintTimer;
  Timer? _suggestionTimer;
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _fetchPopularSearches();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _controller.text.isEmpty) {
        _fetchLiveSuggestions('');
      } else {
        setState(() => _showSuggestions = false);
      }
    });
  }

  Future<void> _fetchPopularSearches() async {
    try {
      final response = await ApiClient.instance.get('/api/v1/popular_searches');
      final List data = response.data is List ? response.data : [];
      final queries = <String>[];
      for (final item in data) {
        if (item is Map && item['query'] != null) {
          queries.add(item['query'].toString());
        }
      }
      if (queries.isNotEmpty && mounted) {
        setState(() => _hints = queries);
        _startRotation();
      }
    } catch (_) {}
  }

  void _startRotation() {
    _hintTimer?.cancel();
    if (_hints.length <= 1) return;
    _hintTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % _hints.length;
      });
    });
  }

  Future<void> _fetchLiveSuggestions(String query) async {
    if (query.trim().length < 2 && query.isNotEmpty) {
      setState(() { _suggestions = []; _showSuggestions = false; });
      return;
    }
    try {
      final res = await ApiClient.instance.get(
        '/api/v1/suggestions',
        queryParameters: {'q': query},
      );
      final data = res.data;
      List<Map<String, dynamic>> items = [];
      for (final p in (data['products'] as List? ?? [])) {
        items.add({'type': 'product', 'id': p['id'], 'title': p['title'], 'image_url': p['image_url'], 'price': p['price']});
      }
      for (final pkg in (data['packages'] as List? ?? [])) {
        items.add({'type': 'package', 'id': pkg['id'], 'name': pkg['name'], 'image_url': pkg['image_url'], 'price': pkg['price']});
      }
      for (final cat in (data['categories'] as List? ?? [])) {
        items.add({'type': 'category', 'id': cat['id'], 'name': cat['name']});
      }
      for (final brand in (data['brands'] as List? ?? [])) {
        items.add({'type': 'brand', 'name': brand['name']});
      }
      for (final pop in (data['popular_searches'] as List? ?? [])) {
        items.add({'type': 'popular', 'query': pop['query']});
      }

      setState(() {
        _suggestions = items;
        _showSuggestions = items.isNotEmpty && _focusNode.hasFocus;
      });
    } catch (_) {
      setState(() { _suggestions = []; _showSuggestions = false; });
    }
  }

  void _onSearchSubmitted(String query) {
    if (query.trim().isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchScreen(),
      ),
    );
  }

  void _onSuggestionTap(Map<String, dynamic> suggestion) {
    setState(() => _showSuggestions = false);
    final type = suggestion['type'] as String?;
    if (type == 'product') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(productId: suggestion['id'] as int),
        ),
      );
    } else if (type == 'package') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PackageDetailScreen(packageId: suggestion['id'] as int),
        ),
      );
    } else if (type == 'category') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SearchScreen(),
        ),
      );
    } else if (type == 'brand' || type == 'popular') {
      final text = suggestion['name'] ?? suggestion['query'] ?? '';
      _controller.text = text;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: text.length),
      );
      _onSearchSubmitted(text);
    }
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _suggestionTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hint = _hints.isEmpty ? 'Search products...' : _hints[_currentIndex];

    // ★ Always 40px, always compact
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SearchScreen()),
        );
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.search_rounded, size: 18, color: Color(0xFFFF4400)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.0,
                  fontFamily: 'Inter',
                  color: Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}