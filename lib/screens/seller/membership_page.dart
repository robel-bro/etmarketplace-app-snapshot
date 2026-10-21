// 📁 lib/screens/seller/membership_page.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api/client.dart';
import '../../theme/app_theme.dart';

class MembershipPage extends StatefulWidget {
  const MembershipPage({Key? key}) : super(key: key);
  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  List<Map<String, dynamic>> _plans = [];
  Map<String, dynamic>? _vendorData;
  bool _isLoading = true;
  String? _error;
  String _billingCycle = 'monthly';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/api/v1/membership_plans'),
        ApiClient.instance.get('/api/v1/vendors/me'),
      ]);

      final plansRes = results[0];
      final vendorRes = results[1];

      final List rawPlans =
          plansRes.data is List ? plansRes.data : (plansRes.data['data'] ?? []);
      final plans = rawPlans.map((p) => Map<String, dynamic>.from(p)).toList();

      setState(() {
        _plans = plans;
        _vendorData = vendorRes.data is Map ? vendorRes.data as Map<String, dynamic>? : null;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to load plans.';
      });
    }
  }

  Future<void> _subscribe(int planId) async {
    try {
      final res = await ApiClient.instance.post('/vendor_subscription', data: {
        'membership_plan_id': planId,
        'payment_method': 'telebirr',
        'billing_cycle': _billingCycle,
      });
      if (res.data['redirect_url'] != null) {
        final url = res.data['redirect_url'];
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Redirect to Payment'),
                content: SelectableText(url),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                ],
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Subscription successful!'),
              backgroundColor: AppColors.primary,
            ),
          );
          _fetchData();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subscription failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Map<String, dynamic> _tierConfig(String name) {
    final tierKey = name.toLowerCase();
    const config = {
      'free': {'glyph': '🏪', 'pill': 'Starter', 'bar': Color(0xFFD1D5DB)},
      'silver': {'glyph': '🥈', 'pill': 'Silver', 'bar': Color(0xFF94A3B8)},
      'gold': {'glyph': '🏆', 'pill': 'Gold', 'bar': Color(0xFFF59E0B)},
      'platinum': {'glyph': '💎', 'pill': 'Platinum', 'bar': Color(0xFF7C3AED)},
    };
    return config[tierKey] ?? config['free']!;
  }

  // ── Current plan banner (inside the list) ──
  Widget _buildCurrentPlanBanner(TextTheme textTheme) {
    final plan = _vendorData!['membership_plan'];
    final expires = _vendorData!['membership_expires_at'];
    final commission = _vendorData!['commission_rate'] ??
        plan['commission_rate'] ??
        '?';
    final featured = _vendorData!['featured'] == true;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusMd)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Text('Your current plan',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 4),
            Text(
              plan['name']?.toString().capitalize() ?? '',
              style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            if (expires != null)
              Text(
                'Expires ${DateTime.parse(expires).toLocal().toString().substring(0, 10)}',
                style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            Text(
              'Commission rate: $commission%',
              style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            if (featured)
              Text('⭐ Your store is featured',
                  style: textTheme.bodySmall?.copyWith(color: Colors.amber.shade700)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('Membership Plans'),
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: _buildBody(textTheme),
    );
  }

  Widget _buildBody(TextTheme textTheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: textTheme.bodyLarge?.copyWith(color: AppColors.textMuted)),
      );
    }
    return Column(
      children: [
        // Billing toggle
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Row(
                  children: [
                    _buildToggleButton('monthly', 'Monthly'),
                    _buildToggleButton('yearly', 'Yearly (Save 20%)'),
                  ],
                ),
              ),
            ],
          ),
        ),
        // List: current plan banner (if any) + plan cards
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            itemCount: (_vendorData?.containsKey('membership_plan') == true ? 1 : 0) + _plans.length,
            itemBuilder: (context, index) {
              // First item is the banner if vendor has a plan
              if (_vendorData != null && _vendorData!['membership_plan'] != null && index == 0) {
                return _buildCurrentPlanBanner(textTheme);
              }
              // Plan cards follow
              final planIndex = (_vendorData?.containsKey('membership_plan') == true ? index - 1 : index);
              return _buildPlanCard(_plans[planIndex], textTheme);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildToggleButton(String value, String label) {
    final selected = _billingCycle == value;
    return GestureDetector(
      onTap: () => setState(() => _billingCycle = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppShapes.radiusSm),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan, TextTheme textTheme) {
    final name = plan['name'] ?? '';
    final tier = _tierConfig(name);
    final glyph = tier['glyph'] as String;
    final pill = tier['pill'] as String;
    final barColor = tier['bar'] as Color;

    final monthlyPrice = (plan['price'] ?? 0).toDouble();
    final yearlyPriceVal = plan['yearly_price'];
    double yearlyPrice = 0;
    if (yearlyPriceVal != null && yearlyPriceVal != 0) {
      yearlyPrice = yearlyPriceVal.toDouble();
    } else {
      yearlyPrice = (monthlyPrice * 12 * 0.8).roundToDouble();
    }
    final price = _billingCycle == 'yearly' ? yearlyPrice : monthlyPrice;
    final isFree = price == 0;
    final periodLabel = _billingCycle == 'yearly' ? '/year' : '/month';
    final savePercent = _billingCycle == 'yearly' && !isFree
        ? (((monthlyPrice * 12 - yearlyPrice) / (monthlyPrice * 12)) * 100).round()
        : 0;

    final commissionRate = plan['commission_rate']?.toString() ?? '?';
    final featuredIncluded = plan['featured_included'] == true;
    final featuredDurationDays = plan['featured_duration_days'];
    final sponsoredSlots = plan['sponsored_product_limit'] ?? 0;
    final analytics = plan['analytics_access'] == true;
    final priority = plan['priority_support'] == true;
    final features = (plan['features'] as List?)?.map((f) => f.toString()).toList() ?? [];

    List<Map<String, String>> perks = [];
    perks.add({'label': '$commissionRate% commission', 'included': 'true'});
    if (featuredIncluded) {
      String dur = featuredDurationDays != null ? ' for $featuredDurationDays days' : '';
      perks.add({'label': 'Featured seller$dur', 'included': 'true', 'highlight': 'true'});
    }
    if (sponsoredSlots > 0) {
      perks.add({'label': '$sponsoredSlots sponsored product slots', 'included': 'true', 'highlight': 'true'});
    }
    if (analytics) {
      perks.add({'label': 'Advanced analytics', 'included': 'true'});
    }
    if (priority) {
      perks.add({'label': 'Priority support', 'included': 'true'});
    }
    for (var feat in features) {
      perks.add({'label': feat, 'included': 'true'});
    }

    final tagline = plan['description'] ?? '';

    // Determine if this is the vendor's current plan
    final isCurrent = _vendorData != null &&
        _vendorData!['membership_plan'] != null &&
        _vendorData!['membership_plan']['id'] == plan['id'];

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusMd)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 6, color: barColor),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                Text(glyph, style: const TextStyle(fontSize: 40)),
                const SizedBox(height: 8),
                Text(name,
                    style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(tagline,
                    style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.pageBackground,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(pill,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1)),
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: AppColors.borderLight),
                const SizedBox(height: 16),
                // Price – grounded, compact
                isFree
                    ? Text('Free',
                        style: textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800, color: AppColors.textPrimary))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('ETB',
                              style: textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                  fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(price.toStringAsFixed(0),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                  fontSize: 28)),
                          const SizedBox(width: 6),
                          Text(periodLabel,
                              style: textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary, fontSize: 13)),
                        ],
                      ),
                // ★ Yearly saving badge
                if (_billingCycle == 'yearly' && savePercent > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF34D399), Color(0xFF059669)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
                          const SizedBox(width: 6),
                          Text('Save $savePercent%',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                ...perks.map((perk) {
                  final highlight = perk['highlight'] == 'true';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      perk['label']!,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  );
                }).toList(),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isCurrent ? null : () => _subscribe(plan['id']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCurrent ? Colors.grey.shade300 : AppColors.primary,
                      foregroundColor: isCurrent ? Colors.grey.shade600 : Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      isCurrent
                          ? 'Current Plan'
                          : (isFree ? 'Get started' : 'Upgrade to $name'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() => '${this[0].toUpperCase()}${substring(1)}';
}