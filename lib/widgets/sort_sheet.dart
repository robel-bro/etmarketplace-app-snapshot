// 📁 lib/widgets/sort_sheet.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SortSheet extends StatelessWidget {
  final String? selectedSort;
  final ValueChanged<String> onSortSelected;

  const SortSheet({
    Key? key,
    required this.selectedSort,
    required this.onSortSelected,
  }) : super(key: key);

  static const Map<String, String> sortOptions = {
    'popularity': 'Popularity',
    'price_asc': 'Price: Low to High',
    'price_desc': 'Price: High to Low',
    'newest': 'Newest First',
    'trending': 'Trending',
    'best_sellers': 'Best Sellers',
    'rating': 'Highest Rated',
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Sort By',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            // Options – flat list, no borders, no shadows
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: sortOptions.entries.map((entry) {
                  final value = entry.key;
                  final label = entry.value;
                  final isSelected = selectedSort == value;
                  return InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      onSortSelected(value);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary.withOpacity(0.06) : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            label,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected ? AppColors.primary : AppColors.textPrimary,
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check, size: 18, color: AppColors.primary),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}