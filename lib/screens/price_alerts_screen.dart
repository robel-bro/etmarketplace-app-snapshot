// lib/screens/price_alerts_screen.dart
import 'package:flutter/material.dart';
import '../api/client.dart';
import '../utils/format_utils.dart';
import 'product_detail_screen.dart';

class PriceAlertsScreen extends StatefulWidget {
  const PriceAlertsScreen({Key? key}) : super(key: key);
  @override
  State<PriceAlertsScreen> createState() => _PriceAlertsScreenState();
}

class _PriceAlertsScreenState extends State<PriceAlertsScreen> {
  List<Map<String, dynamic>> _alerts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAlerts();
  }

  Future<void> _fetchAlerts() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.instance.get('/price_alerts');
      final List data = res.data is List ? res.data : (res.data['data'] ?? []);
      setState(() {
        _alerts = data.cast<Map<String, dynamic>>();
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteAlert(int alertId) async {
    try {
      await ApiClient.instance.delete('/price_alerts/$alertId');
      _fetchAlerts();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('My Price Alerts'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _alerts.isEmpty
              ? const Center(
                  child: Text('No active price alerts.',
                      style: TextStyle(fontSize: 16, color: Colors.grey)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _alerts.length,
                  itemBuilder: (context, index) {
                    final alert = _alerts[index];
                    final product = alert['product'] as Map<String, dynamic>?;
                    final productName = product?['title'] ?? 'Unknown product';
                    final currentPrice = product?['price'];
                    final targetPrice = alert['target_price'];
                    final imageUrl = (product?['image_urls'] as List?)?.firstOrNull ?? '';

                    return Dismissible(
                      key: Key('${alert['id']}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Colors.red.shade100,
                        child: const Icon(Icons.delete_outline, color: Colors.red),
                      ),
                      onDismissed: (_) => _deleteAlert(alert['id']),
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              imageUrl,
                              width: 48, height: 48, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 48, height: 48, color: Colors.grey.shade200,
                                child: const Icon(Icons.image, size: 20, color: Colors.grey),
                              ),
                            ),
                          ),
                          title: Text(productName),
                          subtitle: Text(
                            'Target: ETB $targetPrice\nCurrent: ${currentPrice != null ? 'ETB $currentPrice' : 'N/A'}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteAlert(alert['id']),
                          ),
                          onTap: () {
                            final productId = alert['product_id'];
                            if (productId != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProductDetailScreen(productId: productId),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}