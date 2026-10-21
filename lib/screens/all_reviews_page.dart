import 'package:flutter/material.dart';
import '../models/review.dart';
import '../services/review_service.dart';
import '../theme/app_theme.dart';

class AllReviewsPage extends StatefulWidget {
  final int? productId;
  final int? vendorId;
  final int? packageId;

  const AllReviewsPage({
    super.key,
    this.productId,
    this.vendorId,
    this.packageId,
  });

  @override
  State<AllReviewsPage> createState() => _AllReviewsPageState();
}

class _AllReviewsPageState extends State<AllReviewsPage> {
  List<Review> _allReviews = [];
  bool _isLoading = true;
  String? _error;

  int? _starFilter;
  String _sortBy = 'recent';

  @override
  void initState() {
    super.initState();
    _fetchReviews();
  }

  Future<void> _fetchReviews() async {
    setState(() { _isLoading = true; _error = null; });
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
      if (mounted) setState(() { _allReviews = reviews; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
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
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('All Reviews',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 17)),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.textMuted)))
              : Column(
                  children: [
                    // Summary + distribution (same as in‑line widget)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Average
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                                  children: List.generate(5, (i) => Icon(
                                    i < _averageRating.round() ? Icons.star : Icons.star_border,
                                    color: Colors.amber,
                                    size: 14,
                                  )),
                                ),
                                const SizedBox(height: 4),
                                Text('${_allReviews.length} reviews',
                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Distribution bars
                          Expanded(
                            child: Column(
                              children: List.generate(5, (index) {
                                final star = 5 - index;
                                final count = _distribution[star] ?? 0;
                                final percentage = _allReviews.isNotEmpty
                                    ? (count / _allReviews.length * 100)
                                    : 0.0;
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
                                          child: Text('$star ★',
                                              textAlign: TextAlign.right,
                                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
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
                                          child: Text('$count',
                                              textAlign: TextAlign.right,
                                              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
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
                    ),
                    if (_starFilter != null)
                      TextButton(
                        onPressed: () => setState(() => _starFilter = null),
                        child: const Text('Show all reviews', style: TextStyle(fontSize: 12)),
                      ),
                    // Sort bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.filter_list, size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            _starFilter != null ? '${_starFilter} star reviews' : 'All reviews',
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                          ),
                          Text(
                            ' (${_filteredSorted.length})',
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                          ),
                          const Spacer(),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _sortBy,
                              isDense: true,
                              style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                              items: const [
                                DropdownMenuItem(value: 'recent', child: Text('Most Recent')),
                                DropdownMenuItem(value: 'highest', child: Text('Highest Rated')),
                              ],
                              onChanged: (v) => setState(() => _sortBy = v!),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Full list of review cards (compact, no title)
                    Expanded(
                      child: _filteredSorted.isEmpty
                          ? const Center(child: Text('No reviews yet.', style: TextStyle(color: AppColors.textMuted)))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: _filteredSorted.length,
                              itemBuilder: (_, i) => _buildReviewCard(_filteredSorted[i]),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildReviewCard(Review review) {
    final userInitial = review.userName.isNotEmpty ? review.userName[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            child: Text(userInitial,
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(review.userName,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(width: 8),
                    ...List.generate(5, (i) => Icon(
                      i < review.rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 12,
                    )),
                    const Spacer(),
                    Text(review.createdAt,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(review.comment,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}