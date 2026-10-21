import 'package:flutter/material.dart';
import '../models/review.dart';
import '../services/review_service.dart';
import '../theme/app_theme.dart';

class ReviewListWidget extends StatefulWidget {
  final int? productId;
  final int? vendorId;
  final int? packageId;

  const ReviewListWidget({
    super.key,
    this.productId,
    this.vendorId,
    this.packageId,
  });

  @override
  State<ReviewListWidget> createState() => _ReviewListWidgetState();
}

class _ReviewListWidgetState extends State<ReviewListWidget> {
  List<Review> _allReviews = [];
  bool _isLoading = true;
  String? _error;

  int? _starFilter; // null = all
  String _sortBy = 'recent'; // 'recent' or 'highest'

  @override
  void initState() {
    super.initState();
    _fetchReviews();
  }

  Future<void> _fetchReviews() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      List<Review> reviews;
      if (widget.productId != null) {
        reviews = await ReviewService.getProductReviews(widget.productId!);
      } else if (widget.vendorId != null) {
        reviews = await ReviewService.getVendorReviews(widget.vendorId!);
      } else if (widget.packageId != null) {
        reviews = await ReviewService.getPackageReviews(widget.packageId!);
      } else {
        reviews = [];
      }
      if (mounted) {
        setState(() {
          _allReviews = reviews;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<Review> get _filteredSorted {
    var list = _allReviews.toList();
    if (_starFilter != null) {
      list = list.where((r) => r.rating.round() == _starFilter).toList();
    }
    if (_sortBy == 'highest') {
      list.sort((a, b) => b.rating.compareTo(a.rating));
    } else {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return list;
  }

  List<Review> get _visibleReviews => _filteredSorted.take(5).toList();

  double get _averageRating {
    if (_allReviews.isEmpty) return 0;
    return _allReviews.fold(0.0, (sum, r) => sum + r.rating) / _allReviews.length;
  }

  Map<int, int> get _distribution {
    final map = <int, int>{5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    for (final r in _allReviews) {
      final star = r.rating.round().clamp(1, 5);
      map[star] = (map[star] ?? 0) + 1;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Text(_error!, style: const TextStyle(color: AppColors.textMuted, fontSize: 14));
    }

    final totalAll = _allReviews.length;
    final filteredTotal = _filteredSorted.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Rating Summary + Distribution
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Average
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    _averageRating.toStringAsFixed(1),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < _averageRating.round() ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$totalAll reviews',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Distribution bars with tap filter
            Expanded(
              child: Column(
                children: List.generate(5, (index) {
                  final star = 5 - index;
                  final count = _distribution[star] ?? 0;
                  final percentage = totalAll > 0 ? (count / totalAll * 100) : 0.0;
                  final isSelected = _starFilter == star;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _starFilter = isSelected ? null : star;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text(
                              '$star ★',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: percentage / 100,
                                backgroundColor: Colors.grey.shade200,
                                color: isSelected ? AppColors.primary : Colors.amber,
                                minHeight: 6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 24,
                            child: Text(
                              '$count',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
        if (_starFilter != null)
          TextButton(
            onPressed: () => setState(() => _starFilter = null),
            child: const Text('Show all reviews', style: TextStyle(fontSize: 13)),
          ),
        const SizedBox(height: 8),
        // Sort bar
        Row(
          children: [
            const Icon(Icons.filter_list, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Text(
              _starFilter != null ? '${_starFilter} star reviews' : 'All reviews',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            Text(
              ' ($filteredTotal)',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const Spacer(),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _sortBy,
                isDense: true,
                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                items: const [
                  DropdownMenuItem(value: 'recent', child: Text('Most Recent')),
                  DropdownMenuItem(value: 'highest', child: Text('Highest Rated')),
                ],
                onChanged: (v) => setState(() => _sortBy = v!),
              ),
            ),
          ],
        ),
        const Divider(),
        // Review cards (first 5)
        if (_visibleReviews.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No reviews yet.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
          )
        else
          ..._visibleReviews.map((review) => _buildReviewCard(review)),
        // View all button
        if (totalAll > 5)
          Center(
            child: TextButton(
              onPressed: () => _showAllReviewsModal(context),
              child: Text(
                'View all $totalAll reviews →',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildReviewCard(Review review) {
    final userInitial = review.userName.isNotEmpty ? review.userName[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            child: Text(
              userInitial,
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      review.userName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    ...List.generate(
                      5,
                      (i) => Icon(
                        i < review.rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 14,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      review.createdAt,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  review.comment,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAllReviewsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AllReviewsSheet(
        reviews: _allReviews,
        averageRating: _averageRating,
        distribution: _distribution,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────
// All Reviews Bottom Sheet (full list)
class _AllReviewsSheet extends StatelessWidget {
  final List<Review> reviews;
  final double averageRating;
  final Map<int, int> distribution;
  const _AllReviewsSheet({
    required this.reviews,
    required this.averageRating,
    required this.distribution,
  });

  @override
  Widget build(BuildContext context) {
    final totalAll = reviews.length;
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'All Reviews ($totalAll)',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  averageRating.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: List.generate(
                        5,
                        (i) => Icon(
                          i < averageRating.round() ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 16,
                        ),
                      ),
                    ),
                    Text(
                      '$totalAll reviews',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: reviews.length,
              itemBuilder: (_, i) => _buildReviewCard(reviews[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(Review review) {
    final userInitial = review.userName.isNotEmpty ? review.userName[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            child: Text(
              userInitial,
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  review.userName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Row(
                  children: List.generate(
                    5,
                    (i) => Icon(
                      i < review.rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  review.comment,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  review.createdAt,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}