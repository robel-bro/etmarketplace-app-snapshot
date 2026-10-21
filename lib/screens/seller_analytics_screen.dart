// 📁 lib/screens/seller_analytics_screen.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../api/client.dart';
import '../theme/app_theme.dart';

class SellerAnalyticsScreen extends StatefulWidget {
  const SellerAnalyticsScreen({Key? key}) : super(key: key);

  @override
  State<SellerAnalyticsScreen> createState() => _SellerAnalyticsScreenState();
}

class _SellerAnalyticsScreenState extends State<SellerAnalyticsScreen> {
  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  String? _error;
  String _selectedTimeframe = 'month';

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.get('/seller/stats');
      setState(() {
        _stats = res.data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Analytics',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
      ),
      body: Container(
        color: AppColors.pageBackground,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null
                ? Center(child: Text('Error: $_error', style: TextStyle(color: AppColors.error, fontSize: 16)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Timeframe pills
                        Row(
                          children: ['day', 'week', 'month', 'year'].map((t) {
                            final active = _selectedTimeframe == t;
                            return GestureDetector(
                              onTap: () => setState(() => _selectedTimeframe = t),
                              child: Container(
                                margin: const EdgeInsets.only(right: AppSpacing.sm),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                decoration: BoxDecoration(
                                  color: active ? AppColors.primary : AppColors.cardBackground,
                                  borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                                  border: Border.all(
                                      color: active ? AppColors.primary : AppColors.borderLight),
                                  boxShadow: active
                                      ? [
                                          BoxShadow(
                                            color: AppColors.primary.withOpacity(0.2),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          )
                                        ]
                                      : null,
                                ),
                                child: Text(
                                  t[0].toUpperCase() + t.substring(1),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: active ? Colors.white : AppColors.textMuted,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Key Metrics
                        Row(
                          children: [
                            Expanded(
                              child: _metricCard('Total Orders',
                                  _stats?['total_orders']?.toString() ?? '0', Icons.shopping_bag_outlined, textTheme),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _metricCard(
                                  'Total Earnings',
                                  'ETB ${_toDouble(_stats?['total_earnings']).toStringAsFixed(0)}',
                                  Icons.attach_money, textTheme),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: _metricCard(
                                  'Avg Order',
                                  'ETB ${_toDouble(_stats?['average_order_value']).toStringAsFixed(2)}',
                                  Icons.trending_up, textTheme),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _metricCard('Available', 'ETB 0', Icons.account_balance_wallet, textTheme),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Revenue Chart
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.cardBackground,
                            borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Monthly Revenue',
                                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                              const SizedBox(height: AppSpacing.xs),
                              Text('Track your revenue over time',
                                  style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                              const SizedBox(height: AppSpacing.md),
                              SizedBox(height: 220, child: _buildRevenueChart()),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Recent Orders
                        if (_stats?['recent_orders'] != null &&
                            (_stats!['recent_orders'] as List).isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.cardBackground,
                              borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Recent Orders',
                                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                const SizedBox(height: AppSpacing.md),
                                ...(_stats!['recent_orders'] as List).map<Widget>((order) {
                                  final o = order as Map<String, dynamic>;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.md),
                                    decoration: BoxDecoration(
                                      color: AppColors.hoverState,
                                      borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('#${o['id']}',
                                            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                        Text(
                                            o['created_at']?.toString().substring(0, 10) ?? '',
                                            style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                                        Text(
                                            'ETB ${o['total']?.toString() ?? '0'}',
                                            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.primary)),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _metricCard(String title, String value, IconData icon, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueChart() {
    final revenueByMonth = _stats?['revenue_by_month'] as Map<String, dynamic>? ?? {};

    if (revenueByMonth.isEmpty) {
      return Center(
        child: Text(
          'No revenue data yet',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
        ),
      );
    }

    final entries = revenueByMonth.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final spots = entries.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), _toDouble(e.value.value));
    }).toList();

    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final niceMaxY = ((maxY / 500).ceil() * 500).toDouble() + 500.0;

    return BarChart(
      BarChartData(
        barGroups: spots.map((spot) {
          return BarChartGroupData(
            x: spot.x.toInt(),
            barRods: [
              BarChartRodData(
                toY: spot.y,
                color: AppColors.primary,
                width: 24,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ],
          );
        }).toList(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: AppColors.borderLight, strokeWidth: 0.8),
        ),
        titlesData: FlTitlesData(
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx >= 0 && idx < entries.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      entries[idx].key,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) {
                return Text(
                  'ETB ${value.toInt()}',
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: niceMaxY,
      ),
    );
  }
}