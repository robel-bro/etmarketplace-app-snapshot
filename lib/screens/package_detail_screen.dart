// lib/screens/package_detail_screen.dart (hardened – weight/dimensions per item, safe features handling)
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import '../api/client.dart';
import '../models/package.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../providers/wishlist_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/package_card.dart';
import '../l10n/app_localizations.dart';
import 'cart_screen.dart';
import 'wishlist_screen.dart';
import 'search_screen.dart';
import '../widgets/review_list_widget.dart';
import 'all_reviews_page.dart';

// ─── Helpers ─────────────────────────────────────────
String formatPrice(dynamic value) {
  final amount = double.tryParse(value?.toString() ?? '') ?? 0.0;
  final parts = amount.toStringAsFixed(2).split('.');
  final integerPart = parts[0];
  final decimalPart = parts[1];
  final buffer = StringBuffer();
  for (int i = 0; i < integerPart.length; i++) {
    if (i > 0 && (integerPart.length - i) % 3 == 0) buffer.write(',');
    buffer.write(integerPart[i]);
  }
  return '${buffer.toString()}.$decimalPart';
}

double parsePrice(dynamic value) =>
    double.tryParse(value?.toString() ?? '') ?? 0.0;

// Safe list conversion
List<T> safeList<T>(dynamic value) {
  if (value == null) return [];
  if (value is List) return value.cast<T>();
  if (value is String) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) return decoded.cast<T>();
    } catch (_) {}
  }
  return [];
}

// Safe string list conversion (for features, etc.)
List<String> safeStringList(dynamic value) {
  if (value == null) return [];
  if (value is List) return value.map((e) => e.toString()).toList();
  if (value is String) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
  }
  return [];
}

Map<String, dynamic> safeMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return {};
}

// ─── Animated delivery label ─────────
class _AnimatedDeliveryLabel extends StatefulWidget {
  final String label;
  final Color textColor;
  final double fontSize;
  final FontWeight fontWeight;
  const _AnimatedDeliveryLabel({
    required this.label,
    this.textColor = Colors.white,
    this.fontSize = 12,
    this.fontWeight = FontWeight.w700,
  });
  @override
  State<_AnimatedDeliveryLabel> createState() => _AnimatedDeliveryLabelState();
}

class _AnimatedDeliveryLabelState extends State<_AnimatedDeliveryLabel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _animation;
  bool _needsAnimation = false;
  double _textWidth = 0, _containerWidth = 0;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 6));
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final textStyle = TextStyle(
        color: widget.textColor,
        fontSize: widget.fontSize,
        fontWeight: widget.fontWeight);
    final painter = TextPainter(
        text: TextSpan(text: widget.label, style: textStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr)
      ..layout();
    final containerWidth =
        (context.findRenderObject() as RenderBox?)?.size.width ??
            double.infinity;
    final textWidth = painter.width;
    if (textWidth > containerWidth) {
      setState(() {
        _needsAnimation = true;
        _textWidth = textWidth;
        _containerWidth = containerWidth;
      });
      _animation = Tween<Offset>(
              begin: Offset(containerWidth / textWidth, 0),
              end: const Offset(-1.0, 0))
          .animate(_controller)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _controller.reset();
            _controller.forward();
          }
        });
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsAnimation) {
      return Text(widget.label,
          style: TextStyle(
              color: widget.textColor,
              fontSize: widget.fontSize,
              fontWeight: widget.fontWeight));
    }
    return ClipRect(
      child: SizedBox(
        height: 20,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SlideTransition(
            position: _animation,
            child: Text(widget.label,
                style: TextStyle(
                    color: widget.textColor,
                    fontSize: widget.fontSize,
                    fontWeight: widget.fontWeight)),
          ),
        ),
      ),
    );
  }
}

// ─── Media item helper ────────────────────────────
class _MediaItem {
  final String url;
  final String type;
  const _MediaItem({required this.url, required this.type});
}

// ─── Main screen ─────────────────────────────────────
class PackageDetailScreen extends ConsumerStatefulWidget {
  final int packageId;
  const PackageDetailScreen({Key? key, required this.packageId})
      : super(key: key);
  @override
  ConsumerState<PackageDetailScreen> createState() =>
      _PackageDetailScreenState();
}

class _PackageDetailScreenState extends ConsumerState<PackageDetailScreen>
    with TickerProviderStateMixin {
  Package? _package;
  bool _isLoading = true;
  String? _error;

  int? get _stock {
    if (_package == null) return null;
    if (_package!.bulkEnabled && _package!.stock == null) return null;
    return _package!.availableStock ?? _package!.stock ?? 0;
  }
  bool get _outOfStock {
    if (_package == null) return true;
    if (_package!.bulkEnabled && _package!.stock == null) return false;
    return _stock != null && _stock! <= 0;
  }
  bool get _isUnlimited => _stock == null;
  int get _maxQuantity => _isUnlimited ? 999 : _stock!;

  int _quantity = 1;

  void _incrementQuantity() {
    if (_quantity < _maxQuantity && !_shopClosed && !_outOfStock) {
      setState(() => _quantity++);
    }
  }

  void _decrementQuantity() {
    if (_quantity > 1 && !_shopClosed && !_outOfStock) {
      setState(() => _quantity--);
    }
  }

  List<_MediaItem> _mediaItems = [];
  int _selectedMediaIndex = 0;
  bool _fullscreenOpen = false;
  int _fullscreenIndex = 0;
  List<String> _fullscreenImages = [];
  PageController? _fullscreenPageController;

  Map<String, dynamic>? _zoomedProductData;
  List<String> _zoomedProductImages = [];
  PageController? _productZoomPageController;
  bool _showProductZoom = false;

  final List<String> _tabs = ['Overview', 'Description', 'Reviews', 'Similar'];
  late TabController _tabController;
  late AnimationController _searchBarFadeController;
  late Animation<double> _searchBarFadeAnimation;
  late Animation<double> _imageIconsFadeAnimation;
  final ScrollController _scrollController = ScrollController();

  static const double _searchBarStartFade = 30.0;
  static const double _searchBarFullFade = 100.0;
  static const double _imageHeight = 420.0;
  static const double _tabsAppearThreshold = 250.0;

  bool _isProgrammaticScroll = false;
  String _selectedTab = 'Overview';
  bool _showTabs = false;

  bool _isInCart = false;
  bool _isCartActionInProgress = false;

  List<Package> _similarPackages = [];
  bool _isLoadingSimilar = false;

  String? _vendorLogoUrl;

  int _reviewRefreshCounter = 0;

  final PageController _carouselPageController = PageController();

  Map<String, dynamic>? _vendorDetails;
  String? _deliveryEstimateText;

  String? _shippingEstimateText;
  bool _isShippingEstimateLoading = false;

  bool _shopClosed = false;
  DateTime? _reopenAt;

  VideoPlayerController? _activeVideoController;
  int? _activeVideoIndex;
  bool _videoInitialized = false;

  bool _showSkipOverlay = false;
  bool _skipForward = true;
  Timer? _skipOverlayTimer;
  bool _longPressActive = false;
  double _normalSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _fetchPackage();
    _setupAnimations();
  }

  void _setupAnimations() {
    _searchBarFadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
    _searchBarFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _searchBarFadeController, curve: Curves.easeOut));
    _imageIconsFadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(
            parent: _searchBarFadeController, curve: Curves.easeOut));
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);
  }

  Future<void> _fetchPackage() async {
    try {
      final res = await ApiClient.instance.get('/packages/${widget.packageId}');
      final data = res.data;
      if (mounted) {
        setState(() {
          _package = Package.fromJson(data);
          _quantity = 1;
          _isLoading = false;
          _buildMediaItems();
          _selectedMediaIndex = 0;
        });
        _fetchSimilarPackages();
        if (_package?.vendor != null) {
          final vendorId = _package!.vendor!['id'];
          if (vendorId != null) {
            _fetchVendorLogo(vendorId);
            _loadVendorDetails(vendorId);
          }
        }
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
    }
  }

  void _buildMediaItems() {
    _mediaItems = [];
    final pkg = _package!;
    for (final url in pkg.videoUrls) {
      _mediaItems.add(_MediaItem(url: _makeAbsoluteUrl(url), type: 'video'));
    }
    for (final url in pkg.imageUrls) {
      _mediaItems.add(_MediaItem(url: url, type: 'image'));
    }
    if (_mediaItems.isEmpty) {
      _mediaItems.add(_MediaItem(
          url: 'https://placehold.co/600x400?text=No+Image', type: 'image'));
    }
  }

  String _makeAbsoluteUrl(String relativeOrUrl) {
    if (relativeOrUrl.startsWith('http://') || relativeOrUrl.startsWith('https://')) {
      return relativeOrUrl;
    }
    final base = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:3000';
    final cleanBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final cleanPath = relativeOrUrl.startsWith('/') ? relativeOrUrl : '/$relativeOrUrl';
    return '$cleanBase$cleanPath';
  }

  Future<void> _fetchVendorLogo(int vendorId) async {
    try {
      final res = await ApiClient.instance.get('/api/v1/vendors/$vendorId');
      final vendor = res.data;
      if (vendor is Map && vendor['logo_url'] != null) {
        setState(() => _vendorLogoUrl = vendor['logo_url'].toString());
      }
    } catch (_) {}
    _fetchShippingEstimate(vendorId);
  }

  Future<void> _loadVendorDetails(int vendorId) async {
    try {
      final res = await ApiClient.instance.get('/api/v1/vendors/$vendorId');
      if (mounted) {
        final data = res.data as Map<String, dynamic>;
        setState(() {
          _vendorDetails = data;
          _shopClosed = !(data['accepting_orders'] == true);
          if (data['reopen_at'] != null) {
            _reopenAt = DateTime.tryParse(data['reopen_at'].toString());
          } else {
            _reopenAt = null;
          }
        });
        _calculateDeliveryEstimate();
      }
    } catch (_) {
      if (mounted && _package != null && _package!.vendor != null) {
        final v = _package!.vendor!;
        setState(() {
          _shopClosed = !(v['accepting_orders'] == true);
          if (v['reopen_at'] != null) {
            _reopenAt = DateTime.tryParse(v['reopen_at'].toString());
          } else {
            _reopenAt = null;
          }
        });
      }
    }
  }

  Future<void> _calculateDeliveryEstimate() async {
    final sellerLat = _vendorDetails?['latitude']?.toDouble();
    final sellerLng = _vendorDetails?['longitude']?.toDouble();
    double? buyerLat, buyerLng;
    try {
      final res = await ApiClient.instance.get('/addresses');
      final List addresses = res.data is List ? res.data : [];
      if (addresses.isNotEmpty) {
        final addr = addresses.first;
        buyerLat = addr['latitude']?.toDouble();
        buyerLng = addr['longitude']?.toDouble();
      }
    } catch (_) {}
    if (sellerLat != null && sellerLng != null && buyerLat != null && buyerLng != null) {
      final distance = _haversine(sellerLat, sellerLng, buyerLat, buyerLng);
      if (distance < 1) {
        _deliveryEstimateText = 'Less than 1 km away · ~10‑15 min';
      } else {
        final minutes = (distance / 30 * 60).round();
        _deliveryEstimateText =
            '~${distance.toStringAsFixed(1)} km · ~$minutes min by motorcycle';
      }
    } else if (_vendorDetails != null && _vendorDetails!['delivery_days'] != null) {
      _deliveryEstimateText =
          'Estimated ${_vendorDetails!['delivery_days']} business days';
    } else {
      _deliveryEstimateText = 'Delivery estimate not available';
    }
    setState(() {});
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) *
            sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  Future<void> _fetchShippingEstimate(int vendorId) async {
    final user = ref.read(authProvider);
    if (user == null) return;

    setState(() => _isShippingEstimateLoading = true);
    try {
      final addrRes = await ApiClient.instance.get('/addresses');
      final List addresses = addrRes.data is List ? addrRes.data : [];
      final defaultAddr = addresses.cast<Map<String,dynamic>?>().firstWhere(
            (a) => a?['is_default'] == true,
            orElse: () => null,
          );
      if (defaultAddr == null) return;

      final estimateRes = await ApiClient.instance.get('/shipping_estimate', queryParameters: {
        'vendor_id': vendorId,
        'address_id': defaultAddr['id'],
      });
      final options = estimateRes.data['options'] as List? ?? [];
      if (options.isNotEmpty) {
        final fastest = options.first;
        setState(() {
          _shippingEstimateText =
              'Est. delivery: ${fastest['partner_name']} – ${fastest['estimated_days']} day(s)';
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isShippingEstimateLoading = false);
    }
  }

  // ─── Inline video helpers ──
  void _initializeVideo(int index, String url) {
    _disposeVideoPlayer();
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _activeVideoController = controller;
    _activeVideoIndex = index;
    _videoInitialized = false;
    _normalSpeed = 1.0;
    controller.addListener(() {
      if (!mounted) return;
      final value = controller.value;
      if (value.hasError) {
        _disposeVideoPlayer();
        return;
      }
      if (!_videoInitialized && value.isInitialized) {
        setState(() => _videoInitialized = true);
        controller.play();
      } else if (value.isPlaying || value.isBuffering) {
        setState(() {});
      }
    });
    controller.initialize().then((_) {
      if (mounted) {
        setState(() => _videoInitialized = true);
        controller.play();
      }
    }).catchError((_) {
      if (mounted) _disposeVideoPlayer();
    });
  }

  void _disposeVideoPlayer() {
    _activeVideoController?.removeListener(() {});
    _activeVideoController?.dispose();
    _activeVideoController = null;
    _activeVideoIndex = null;
    _videoInitialized = false;
    _longPressActive = false;
    setState(() {});
  }

  void _togglePlayPause() {
    if (_activeVideoController == null) return;
    setState(() {
      if (_activeVideoController!.value.isPlaying) {
        _activeVideoController!.pause();
      } else {
        _activeVideoController!.play();
      }
    });
  }

  void _seekRelative(int seconds) {
    if (_activeVideoController != null && _activeVideoController!.value.isInitialized) {
      final newPos = _activeVideoController!.value.position + Duration(seconds: seconds);
      final target = newPos < Duration.zero
          ? Duration.zero
          : newPos > _activeVideoController!.value.duration
              ? _activeVideoController!.value.duration
              : newPos;
      _activeVideoController!.seekTo(target);
    }
  }

  void _startLongPress() {
    if (_activeVideoController != null && _activeVideoController!.value.isPlaying) {
      setState(() => _longPressActive = true);
      _activeVideoController!.setPlaybackSpeed(2.0);
    }
  }

  void _endLongPress() {
    if (_activeVideoController != null && _longPressActive) {
      _activeVideoController!.setPlaybackSpeed(_normalSpeed);
      setState(() => _longPressActive = false);
    }
  }

  void _triggerSkipOverlay(bool forward) {
    setState(() {
      _skipForward = forward;
      _showSkipOverlay = true;
    });
    _skipOverlayTimer?.cancel();
    _skipOverlayTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showSkipOverlay = false);
    });
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours),
        minutes = twoDigits(d.inMinutes.remainder(60)),
        seconds = twoDigits(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  Widget _buildInlineVideoControls() {
    if (_activeVideoController == null) return const SizedBox.shrink();
    final video = _activeVideoController!.value;

    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter, end: Alignment.topCenter,
            colors: [Colors.black.withOpacity(0.8), Colors.transparent],
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_mediaItems.length > 1)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                child: Text('${_selectedMediaIndex + 1}/${_mediaItems.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
            Text(_formatDuration(video.position), style: const TextStyle(color: Colors.white, fontSize: 11)),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: Colors.white30,
                  thumbColor: AppColors.primary,
                  overlayColor: AppColors.primary.withOpacity(0.3),
                ),
                child: Slider(
                  value: video.position.inMilliseconds.clamp(0, video.duration.inMilliseconds).toDouble(),
                  max: video.duration.inMilliseconds.toDouble().clamp(1.0, double.infinity),
                  onChanged: (v) { _activeVideoController?.seekTo(Duration(milliseconds: v.toInt())); },
                ),
              ),
            ),
            Text(_formatDuration(video.duration), style: const TextStyle(color: Colors.white, fontSize: 11)),
            const SizedBox(width: 4),
            IconButton(
              padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              icon: const Icon(Icons.fullscreen, color: Colors.white, size: 24),
              onPressed: () async {
                if (_activeVideoController == null) return;
                final url = _mediaItems[_activeVideoIndex!].url;
                final position = _activeVideoController!.value.position;
                _disposeVideoPlayer();
                if (!mounted) return;
                await Navigator.push(context, MaterialPageRoute(builder: (_) => _FullVideoPlayerScreen(url: url)));
                if (mounted) {
                  _initializeVideoAtPosition(index: _activeVideoIndex!, url: url, position: position);
                }
              },
            ),
            Consumer(builder: (_, ref, __) {
              final wishlist = ref.watch(wishlistProvider);
              final isWishlisted = wishlist.any((item) => item.productId == widget.packageId);
              return IconButton(
                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                icon: Icon(
                  isWishlisted ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isWishlisted ? AppColors.error : Colors.white,
                  size: 22,
                ),
                onPressed: () async {
                  final notifier = ref.read(wishlistProvider.notifier);
                  if (isWishlisted) {
                    await notifier.removeItem(widget.packageId);
                  } else {
                    final prod = _packageToProduct(_package!);
                    await notifier.addItem(prod);
                  }
                  setState(() {});
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _initializeVideoAtPosition({
    required int index,
    required String url,
    required Duration position,
  }) {
    _disposeVideoPlayer();
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _activeVideoController = controller;
    _activeVideoIndex = index;
    _videoInitialized = false;
    _normalSpeed = 1.0;
    controller.addListener(() {
      if (!mounted) return;
      final value = controller.value;
      if (value.hasError) {
        _disposeVideoPlayer();
        return;
      }
      if (!_videoInitialized && value.isInitialized) {
        setState(() => _videoInitialized = true);
        controller.seekTo(position);
        controller.play();
      }
    });
    controller.initialize().then((_) {
      if (mounted) {
        setState(() => _videoInitialized = true);
        controller.seekTo(position);
        controller.play();
      }
    }).catchError((_) {
      if (mounted) _disposeVideoPlayer();
    });
  }

  // ── Carousel ───────────────
  Widget _buildCarousel() {
    if (_mediaItems.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: _imageHeight,
          child: Stack(children: [
            PageView.builder(
              controller: _carouselPageController,
              physics: _activeVideoController != null
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              onPageChanged: (index) {
                setState(() => _selectedMediaIndex = index);
                if (_activeVideoIndex != null && _activeVideoIndex != index) {
                  _disposeVideoPlayer();
                }
              },
              itemCount: _mediaItems.length,
              itemBuilder: (context, index) {
                final item = _mediaItems[index];
                if (item.type == 'image') {
                  return GestureDetector(
                    onTap: () => _openFullscreenImages(
                      _mediaItems.where((m) => m.type == 'image').map((m) => m.url).toList(),
                      _mediaItems.where((m) => m.type == 'image').toList().indexOf(item),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: item.url, fit: BoxFit.cover, width: double.infinity,
                      placeholder: (_, __) => Shimmer.fromColors(
                          baseColor: Colors.grey.shade200,
                          highlightColor: Colors.grey.shade100,
                          child: Container(color: Colors.white)),
                      errorWidget: (_, __, ___) => Container(
                          color: Colors.grey.shade100,
                          child: Icon(Icons.broken_image, color: AppColors.textMuted)),
                    ),
                  );
                } else {
                  final isPlaying = _activeVideoIndex == index && _activeVideoController != null;
                  if (isPlaying && _videoInitialized) {
                    return Stack(fit: StackFit.expand, children: [
                      Positioned.fill(
                        child: AspectRatio(
                          aspectRatio: _activeVideoController!.value.aspectRatio,
                          child: VideoPlayer(_activeVideoController!),
                        ),
                      ),
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _togglePlayPause,
                          onDoubleTapDown: (details) {
                            final halfWidth = (context.size?.width ?? 0) / 2;
                            final tapX = details.localPosition.dx;
                            if (tapX < halfWidth) {
                              _seekRelative(-10);
                              _triggerSkipOverlay(false);
                            } else {
                              _seekRelative(10);
                              _triggerSkipOverlay(true);
                            }
                          },
                          onLongPressStart: (_) => _startLongPress(),
                          onLongPressEnd: (_) => _endLongPress(),
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                      _buildInlineVideoControls(),
                      if (_showSkipOverlay)
                        Align(
                          alignment: _skipForward ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 24),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(_skipForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                                  color: Colors.white, size: 32),
                              const SizedBox(width: 6),
                              const Text('10 s', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                            ]),
                          ),
                        ),
                    ]);
                  } else if (isPlaying && !_videoInitialized) {
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  } else {
                    return GestureDetector(
                      onTap: () => _initializeVideo(index, item.url),
                      child: Container(
                        color: Colors.black,
                        child: Stack(fit: StackFit.expand, children: [
                          if (_package!.imageUrls.isNotEmpty)
                            CachedNetworkImage(imageUrl: _package!.imageUrls.first, fit: BoxFit.cover),
                          Center(
                            child: Container(
                              width: 64, height: 64,
                              decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9), shape: BoxShape.circle),
                              child: const Icon(Icons.play_arrow, size: 40, color: AppColors.primary),
                            ),
                          ),
                        ]),
                      ),
                    );
                  }
                }
              },
            ),
            if (_activeVideoController == null)
              Positioned(
                bottom: 12, right: AppSpacing.xs,
                child: FadeTransition(
                  opacity: _imageIconsFadeAnimation,
                  child: Consumer(builder: (_, ref, __) {
                    final wishlist = ref.watch(wishlistProvider);
                    final isWishlisted = wishlist.any((item) => item.productId == widget.packageId);
                    return _TransparentIcon(
                      icon: isWishlisted ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      onTap: () {
                        final notifier = ref.read(wishlistProvider.notifier);
                        if (isWishlisted) {
                          notifier.removeItem(widget.packageId);
                        } else {
                          final prod = _packageToProduct(_package!);
                          notifier.addItem(prod);
                        }
                        setState(() {});
                      },
                      iconColor: isWishlisted ? AppColors.error : Colors.white,
                    );
                  }),
                ),
              ),
            if (_activeVideoController == null && _mediaItems.length > 1)
              Positioned(
                bottom: 12, left: AppSpacing.xs,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                  child: Text('${_selectedMediaIndex + 1}/${_mediaItems.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
          ]),
        ),
        if (_mediaItems.length > 1)
          Container(
            height: 60, margin: const EdgeInsets.only(top: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              itemCount: _mediaItems.length,
              itemBuilder: (ctx, i) {
                final item = _mediaItems[i];
                final isSelected = i == _selectedMediaIndex;
                return GestureDetector(
                  onTap: () {
                    _carouselPageController.animateToPage(i,
                        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                    if (_activeVideoIndex != null && _activeVideoIndex != i) _disposeVideoPlayer();
                  },
                  child: Container(
                    width: 56, height: 56, margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.borderLight,
                          width: isSelected ? 2 : 1),
                      borderRadius: BorderRadius.circular(AppShapes.radiusSm),
                    ),
                    child: Stack(fit: StackFit.expand, children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppShapes.radiusSm - 1),
                        child: item.type == 'video'
                            ? (_package!.imageUrls.isNotEmpty
                                ? CachedNetworkImage(imageUrl: _package!.imageUrls.first, fit: BoxFit.cover)
                                : Container(color: Colors.grey.shade300))
                            : CachedNetworkImage(imageUrl: item.url, fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(color: Colors.grey.shade200)),
                      ),
                      if (item.type == 'video')
                        Center(
                          child: Container(
                            width: 20, height: 20,
                            decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.play_arrow, size: 14, color: Colors.white),
                          ),
                        ),
                    ]),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    final newTab = _tabs[_tabController.index];
    if (_selectedTab != newTab) {
      setState(() => _selectedTab = newTab);
      _scrollToTabSection(_tabController.index);
    }
  }

  void _scrollToTabSection(int index) async {
    final offset = index * 500.0;
    _isProgrammaticScroll = true;
    await _scrollController.animateTo(offset,
        duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    _isProgrammaticScroll = false;
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    double opacity = 0.0;
    if (offset > _searchBarStartFade) {
      opacity = ((offset - _searchBarStartFade) / (_searchBarFullFade - _searchBarStartFade))
          .clamp(0.0, 1.0);
    }
    _searchBarFadeController.value = opacity;
    final showTabs = offset >= _tabsAppearThreshold;
    if (showTabs != _showTabs) setState(() => _showTabs = showTabs);
  }

  @override
  void dispose() {
    _activeVideoController?.removeListener(() {});
    _activeVideoController?.dispose();
    _fullscreenPageController?.dispose();
    _productZoomPageController?.dispose();
    _carouselPageController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchBarFadeController.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _syncCartState() {
    if (!mounted) return;
    final cart = ref.read(cartProvider);
    final inCart = cart?.items.any((item) =>
        item.productId == widget.packageId ||
        item.packageId == widget.packageId) ?? false;
    if (mounted && _isInCart != inCart) setState(() => _isInCart = inCart);
  }

  bool get _isWishlisted =>
      ref.read(wishlistProvider).any((item) => item.productId == widget.packageId);

  Future<void> _toggleCart() async {
    if (_isCartActionInProgress || _shopClosed || _outOfStock) return;
    setState(() => _isCartActionInProgress = true);
    try {
      final notifier = ref.read(cartProvider.notifier);
      if (_isInCart) {
        await notifier.removeItem(widget.packageId);
        if (mounted) setState(() => _isInCart = false);
      } else {
        final prod = _packageToProduct(_package!);
        await notifier.addItem(prod, quantity: _quantity);
        if (mounted) setState(() => _isInCart = true);
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _isCartActionInProgress = false);
    }
  }

  Product _packageToProduct(Package pkg) {
    return Product(
      id: pkg.id,
      title: pkg.name,
      price: pkg.price,
      imageUrl: pkg.imageUrls.isNotEmpty ? pkg.imageUrls.first : '',
      images: pkg.imageUrls,
      rating: pkg.rating ?? 0.0,
      reviewsCount: pkg.reviewsCount ?? 0,
      soldCount: 0,
      freeShipping: pkg.freeDelivery || pkg.shippingType == 'free',
      originalPrice: pkg.originalPrice,
      effectivePrice: pkg.price,
      videoUrls: pkg.videoUrls,
      stock: pkg.stock,
      availableStock: pkg.availableStock,
      sellerPaysShipping: pkg.sellerPaysShipping,
      shippingSubsidyType: pkg.shippingSubsidyType,
      shippingSubsidyValue: pkg.shippingSubsidyValue,
      isPackage: true,
      freeDelivery: pkg.freeDelivery,
      deliveryLabel: pkg.deliveryLabel,
    );
  }

  Product _itemToProduct(Map<String, dynamic> item) {
    final itemImages = safeList<String>(item['image_urls']);
    return Product(
      id: item['id'] ?? widget.packageId,
      title: item['title'] ?? '',
      price: parsePrice(item['price']),
      imageUrl: itemImages.isNotEmpty ? itemImages.first : '',
      images: itemImages,
      rating: 0.0,
      reviewsCount: 0,
      soldCount: 0,
      freeShipping: false,
      effectivePrice: parsePrice(item['effective_price'] ?? item['price']),
      videoUrls: safeList<String>(item['video_urls']),
    );
  }

  void _openFullscreenImages(List<String> images, int startIndex) {
    _fullscreenImages = images;
    _fullscreenIndex = startIndex;
    _fullscreenPageController?.dispose();
    _fullscreenPageController = PageController(initialPage: startIndex);
    setState(() => _fullscreenOpen = true);
  }

  void _closeFullscreen() {
    _fullscreenPageController?.dispose();
    _fullscreenPageController = null;
    setState(() => _fullscreenOpen = false);
  }

  void _openProductZoom(Map<String, dynamic> item) {
    final images = safeList<String>(item['image_urls']);
    if (images.isEmpty) return;
    _zoomedProductData = item;
    _zoomedProductImages = images;
    _productZoomPageController?.dispose();
    _productZoomPageController = PageController(initialPage: 0);
    setState(() => _showProductZoom = true);
  }

  void _closeProductZoom() {
    _productZoomPageController?.dispose();
    _productZoomPageController = null;
    _zoomedProductData = null;
    _zoomedProductImages = [];
    setState(() => _showProductZoom = false);
  }

  String _getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Future<void> _reportViolation() async {
    final l10n = AppLocalizations.of(context);
    final reasonController = TextEditingController();
    String selectedReason = 'Counterfeit';
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          decoration: const BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text(l10n.translate('package_report_title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(l10n.translate('package_report_subtitle'),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedReason,
              decoration: InputDecoration(labelText: l10n.translate('package_report_reason'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
              items: const [
                DropdownMenuItem(value: 'Counterfeit', child: Text('Counterfeit')),
                DropdownMenuItem(value: 'Inappropriate', child: Text('Inappropriate')),
                DropdownMenuItem(value: 'Misleading', child: Text('Misleading')),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: (val) => setSheetState(() => selectedReason = val!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController, maxLines: 3,
              decoration: InputDecoration(labelText: l10n.translate('package_report_comment'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text(l10n.translate('package_report_submit'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
    if (result == true) {
      try {
        await ApiClient.instance.post('/packages/${widget.packageId}/reports', data: {
          'report': {'reason': selectedReason, 'comment': reasonController.text.trim()}
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l10n.translate('package_report_success')), backgroundColor: AppColors.textPrimary));
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l10n.translate('package_report_fail')), backgroundColor: AppColors.error));
      }
    }
  }

  // ★ SIMILAR PACKAGES: fetch by category if available
  Future<void> _fetchSimilarPackages() async {
    if (_isLoadingSimilar) return;
    setState(() => _isLoadingSimilar = true);
    try {
      int? categoryId;
      if (_package?.categories != null && _package!.categories!.isNotEmpty) {
        final firstCategory = _package!.categories!.first;
        if (firstCategory is Map) {
          categoryId = firstCategory['id'] is int
              ? firstCategory['id']
              : int.tryParse(firstCategory['id']?.toString() ?? '');
        }
      }

      final query = categoryId != null ? {'category': categoryId.toString(), 'limit': '6'} : {'limit': '6'};
      final res = await ApiClient.instance.get('/packages', queryParameters: query);
      final List data = res.data is List ? res.data : (res.data['data'] ?? []);
      final packages = data.map((json) => Package.fromJson(json)).toList();
      packages.removeWhere((p) => p.id == widget.packageId);
      if (mounted) setState(() {
        _similarPackages = packages;
        _isLoadingSimilar = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingSimilar = false);
    }
  }

  // ★ UPDATED: compact item card with inline description & dimensions/weight
  Widget _buildCompactItemCard(Map<String, dynamic> item) {
    final itemImages = safeList<String>(item['image_urls']);
    final imageUrl = itemImages.isNotEmpty
        ? itemImages.first
        : 'https://placehold.co/400x400?text=No+Image';
    final itemPrice = parsePrice(item['effective_price'] ?? item['price']);
    final variantAttrs = safeMap(item['variant_attributes']);
    final productAttrs = safeMap(item['product_attributes']);
    final description = item['description']?.toString() ?? '';

    // Weight & dimensions
    final weightKg = item['weight_kg'];
    final lengthCm = item['length_cm'];
    final widthCm = item['width_cm'];
    final heightCm = item['height_cm'];
    final hasDimensions = weightKg != null || lengthCm != null || widthCm != null || heightCm != null;

    return GestureDetector(
      onTap: () => _openProductZoom(item),
      child: Container(
        padding: const EdgeInsets.all(8),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppShapes.radiusSm),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.image,
                          size: 30, color: AppColors.textMuted),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['title'] ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (variantAttrs.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: variantAttrs.entries.map((entry) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${entry.key}: ${entry.value}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.purple,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        'ETB ${formatPrice(itemPrice)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Inline description
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.textMuted,
                ),
              ),
            ],

            // Optional key specs
            if (productAttrs.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: productAttrs.entries
                    .take(4)
                    .map((entry) {
                  return Text(
                    '${entry.key.replaceAll('_', ' ')}: ${entry.value}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  );
                }).toList(),
              ),
            ],

            // Dimensions & Weight
            if (hasDimensions) ...[
              const SizedBox(height: 8),
              _buildDimensionsSection(item),
            ],
          ],
        ),
      ),
    );
  }

  // ★ Dimensions & weight section for a package item
  Widget _buildDimensionsSection(Map<String, dynamic> item) {
    final weightKg = item['weight_kg'];
    final lengthCm = item['length_cm'];
    final widthCm = item['width_cm'];
    final heightCm = item['height_cm'];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.straighten, size: 14, color: AppColors.textMuted),
              SizedBox(width: 4),
              Text(
                'Dimensions & Weight',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (weightKg != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.monitor_weight_outlined, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text('$weightKg kg', style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                  ],
                ),
              if (lengthCm != null)
                Text('Length: $lengthCm cm', style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
              if (widthCm != null)
                Text('Width: $widthCm cm', style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
              if (heightCm != null)
                Text('Height: $heightCm cm', style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStarsRow(double rating, int reviewCount) {
    final fullStars = rating.floor();
    final halfStar = (rating - fullStars) >= 0.5;
    final emptyStars = 5 - fullStars - (halfStar ? 1 : 0);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ...List.generate(fullStars, (_) => const Icon(Icons.star_rounded, color: AppColors.starGold, size: 14)),
      if (halfStar) const Icon(Icons.star_half_rounded, color: AppColors.starGold, size: 14),
      ...List.generate(emptyStars, (_) => const Icon(Icons.star_outline_rounded, color: AppColors.starGold, size: 14)),
      const SizedBox(width: 4),
      Text(rating.toStringAsFixed(1),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textPrimary)),
      const SizedBox(width: 2),
      Text('($reviewCount reviews)',
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
    ]);
  }

  Widget _buildSoldCount(int sold) => sold <= 0
      ? const SizedBox.shrink()
      : Text(' · $sold sold',
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted));

  Widget _buildRatingRow(double r, int rc, int s) =>
      Row(children: [_buildStarsRow(r, rc), _buildSoldCount(s)]);

  // ★ Price block with stock display removed (kept only near quantity selector)
  Widget _buildPriceBlock() {
    final l10n = AppLocalizations.of(context);
    final pkg = _package!;
    final price = pkg.price, originalPrice = pkg.originalPrice, discount = pkg.discountPercentage;

    final showDeliveryBadge = pkg.freeDelivery || (pkg.deliveryLabel != null && pkg.deliveryLabel!.isNotEmpty && pkg.deliveryLabel!.toLowerCase() != 'paid delivery');
    String deliveryLabel = '';
    if (pkg.deliveryLabel != null && pkg.deliveryLabel!.isNotEmpty) {
      deliveryLabel = pkg.deliveryLabel!;
    } else if (pkg.freeDelivery) {
      deliveryLabel = l10n.translate('package_free_delivery');
    } else if (pkg.sellerPaysShipping && pkg.shippingSubsidyType == 'percent' && pkg.shippingSubsidyValue != null) {
      deliveryLabel = l10n.translate('package_discount_delivery')
          .replaceAll('{discount}', pkg.shippingSubsidyValue!.round().toString());
    } else if (pkg.shippingType == 'free') {
      deliveryLabel = l10n.translate('package_free_delivery');
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        border: showDeliveryBadge ? Border.all(color: const Color(0xFFFF7A00), width: 1.5) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDeliveryBadge)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFF7A00), Color(0xFFD84315)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Row(children: [
                const Icon(Icons.local_shipping, size: 14, color: Colors.white),
                const SizedBox(width: 6),
                Expanded(
                  child: _AnimatedDeliveryLabel(
                    label: deliveryLabel,
                    textColor: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        child: Text(
                          'ETB ${formatPrice(price)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (discount > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            l10n.translate('package_save_amount')
                                .replaceAll('{amount}', formatPrice((originalPrice ?? price) - price))
                                .replaceAll('{discount}', discount.toString()),
                            style: const TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ]),
                  ),
                ]),
                if (originalPrice != null && originalPrice > price)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'ETB ${formatPrice(originalPrice)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        decoration: TextDecoration.lineThrough,
                        color: AppColors.textMuted,
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

  Widget _buildShopClosedBanner() {
    final l10n = AppLocalizations.of(context);
    if (!_shopClosed) return const SizedBox.shrink();
    final vendorName = _package?.vendor?['business_name'] ?? 'This shop';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade300),
        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.storefront, color: Colors.amber[800], size: 18),
          const SizedBox(width: 8),
          Text(l10n.translate('package_not_accepting_orders').replaceAll('{name}', vendorName),
              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.amber[900], fontSize: 13)),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _reopenAt != null
                ? l10n.translate('package_expected_reopen').replaceAll('{date}', _reopenAt!.toLocal().toString().substring(0, 16))
                : l10n.translate('package_please_check_back'),
            style: TextStyle(color: Colors.amber[800], fontSize: 12),
          ),
        ),
      ]),
    );
  }

  void _sharePackage() {
    final l10n = AppLocalizations.of(context);
    final productLink = 'https://yourapp.com/package/${widget.packageId}';
    Share.share(l10n.translate('package_share_subject').replaceAll('{link}', productLink), subject: _package?.name ?? 'Package');
  }

  List<Widget> _buildLocalisedTabs(AppLocalizations l10n) {
    final labels = [
      l10n.translate('tab_overview'),
      l10n.translate('tab_description'),
      l10n.translate('tab_reviews'),
      l10n.translate('tab_similar'),
    ];
    return labels.map((label) => Tab(child: Text(label))).toList();
  }

  String _localisedSelectedTab(AppLocalizations l10n) {
    switch (_selectedTab) {
      case 'Overview':     return l10n.translate('tab_overview');
      case 'Description':  return l10n.translate('tab_description');
      case 'Reviews':      return l10n.translate('tab_reviews');
      case 'Similar':      return l10n.translate('tab_similar');
      default:             return _selectedTab;
    }
  }

  Widget _buildVendorCard() {
    final pkg = _package!;
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primary.withOpacity(0.1),
              backgroundImage: (_vendorLogoUrl != null && _vendorLogoUrl!.isNotEmpty)
                  ? CachedNetworkImageProvider(_vendorLogoUrl!)
                  : null,
              child: (_vendorLogoUrl == null || _vendorLogoUrl!.isEmpty)
                  ? Text(
                      (pkg.vendor!['business_name']?.toString() ?? 'S').substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 20))
                  : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pkg.vendor!['business_name'] ?? '',
                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(l10n.translate('package_official_store'),
                  style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
            ])),
            TextButton(
              onPressed: () {
                final vendorId = pkg.vendor!['id'];
                if (vendorId != null)
                  Navigator.pushNamed(context, '/shop', arguments: vendorId.toString());
              },
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppShapes.radiusSm))),
              child: Text(l10n.translate('package_visit_shop'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          if (_isShippingEstimateLoading)
            Text(l10n.translate('package_calculating_delivery'),
                style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted))
          else if (_shippingEstimateText != null)
            Text(_shippingEstimateText!,
                style: textTheme.bodySmall?.copyWith(
                    color: Colors.green.shade700, fontWeight: FontWeight.w500))
          else if (ref.read(authProvider) != null)
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/profile/addresses'),
              child: Text(l10n.translate('package_add_delivery_address'),
                  style: textTheme.bodySmall?.copyWith(color: AppColors.primary)),
            )
          else
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/login'),
              child: Text(l10n.translate('package_login_to_see_delivery'),
                  style: textTheme.bodySmall?.copyWith(color: AppColors.primary)),
            ),
        ]),
      ),
    );
  }

  Widget _buildItemsInPackageCard() {
    final l10n = AppLocalizations.of(context);
    final pkg = _package!;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.translate('package_items_in_package'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.sm),
        ...pkg.products!.map((item) => _buildCompactItemCard(item)),
      ]),
    );
  }

  Widget _buildDeliveryAndReturnPolicyRow() {
    final textTheme = Theme.of(context).textTheme;
    final showDelivery = _deliveryEstimateText != null;
    final showReturnPolicy = _vendorDetails != null &&
        _vendorDetails!['return_policy'] != null &&
        _vendorDetails!['return_policy'].toString().trim().isNotEmpty &&
        _vendorDetails!['return_policy'].toString().trim().toLowerCase() !=
            'we accept returns within 14 days of delivery.';

    return Row(children: [
      if (showDelivery)
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(AppShapes.radiusMd)),
            child: Row(children: [
              const Icon(Icons.local_shipping_outlined, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(_deliveryEstimateText!,
                  style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
            ]),
          ),
        ),
      if (showDelivery && showReturnPolicy) const SizedBox(width: AppSpacing.xs),
      if (showReturnPolicy)
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(AppShapes.radiusMd)),
            child: Row(children: [
              const Icon(Icons.assignment_return, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(_vendorDetails!['return_policy'],
                  style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted))),
            ]),
          ),
        ),
    ]);
  }

  Widget _buildSimilarPackagesSection() {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, AppSpacing.sm, 0, AppSpacing.xs),
          child: Text(l10n.translate('package_similar_packages'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
        if (_isLoadingSimilar)
          const Padding(
              padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
        else
          MasonryGridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2, mainAxisSpacing: 4, crossAxisSpacing: 4,
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
            itemCount: _similarPackages.length,
            itemBuilder: (ctx, index) {
              final sp = _similarPackages[index];
              return GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => PackageDetailScreen(packageId: sp.id))),
                child: _SimilarPackageCard(package: sp),
              );
            },
          ),
      ]),
    );
  }

  Widget _buildQuantitySelector() {
    final l10n = AppLocalizations.of(context);
    final maxQty = _maxQuantity;
    final bool outOfStock = _outOfStock;
    final bool shopClosed = _shopClosed;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            l10n.translate('package_qty'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(AppShapes.radiusSm),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: (shopClosed || outOfStock || _quantity <= 1) ? null : _decrementQuantity,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.remove, size: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '$_quantity',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                InkWell(
                  onTap: (shopClosed || outOfStock || _quantity >= maxQty) ? null : _incrementQuantity,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.add, size: 16),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_isUnlimited)
            Text(
              l10n.translate('package_unlimited_stock'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green.shade700),
            )
          else
            Text(
              l10n.translate('package_available').replaceAll('{stock}', _stock.toString()),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen(cartProvider, (_, __) {
      if (!mounted) return;
      _syncCartState();
    });

    if (_isLoading)
      return const Scaffold(
          backgroundColor: Color(0xFFF2F2F7),
          body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    if (_error != null || _package == null)
      return Scaffold(
          backgroundColor: const Color(0xFFF2F2F7),
          appBar: AppBar(
              backgroundColor: AppColors.cardBackground, elevation: 0,
              title: Text(l10n.translate('package_not_found'), style: const TextStyle(color: AppColors.textPrimary))),
          body: Center(child: Text(_error ?? l10n.translate('package_not_found'), style: const TextStyle(color: AppColors.error))));

    final pkg = _package!;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final textTheme = Theme.of(context).textTheme;
    final wishlist = ref.watch(wishlistProvider);
    final cart = ref.watch(cartProvider);
    final cartItemCount = cart?.itemCount ?? 0;
    final wishlistCount = wishlist.length;

    final showDelivery = _deliveryEstimateText != null;

    final showReturnPolicy = _vendorDetails != null &&
        _vendorDetails!['return_policy'] != null &&
        _vendorDetails!['return_policy'].toString().trim().isNotEmpty &&
        _vendorDetails!['return_policy'].toString().trim().toLowerCase() !=
            'we accept returns within 14 days of delivery.';

    final double avgRating = pkg.rating ?? 0.0;
    final int totalReviews = pkg.reviewsCount ?? 0;

    // Safe features list
    final packageFeatures = safeStringList(pkg.features);

    final localisedTabs = _buildLocalisedTabs(l10n);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: Stack(children: [
        CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Column(children: [
                _buildCarousel(),
                _buildShopClosedBanner(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 12),
                    Text(pkg.name,
                        style: textTheme.headlineMedium?.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    if (avgRating > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(avgRating.toStringAsFixed(1),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          const SizedBox(width: 6),
                          Row(
                            children: List.generate(5, (index) {
                              final starValue = index + 1;
                              return Icon(
                                starValue <= avgRating.round()
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 14,
                                color: const Color(0xFFF59E0B),
                              );
                            }),
                          ),
                          const SizedBox(width: 4),
                          Text('($totalReviews reviews)',
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 4),
                    _buildPriceBlock(),
                    _buildQuantitySelector(),
                    const SizedBox(height: 6),
                    if (pkg.products != null && pkg.products!.isNotEmpty) ...[
                      _buildItemsInPackageCard(),
                      const SizedBox(height: 6),
                    ],
                    if (pkg.description != null && pkg.description!.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(l10n.translate('package_description'), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(pkg.description!,
                              style: textTheme.bodyMedium?.copyWith(height: 1.5, color: AppColors.textPrimary)),
                        ]),
                      ),
                    if (pkg.vendor != null) ...[
                      _buildVendorCard(),
                      const SizedBox(height: 6),
                    ],
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(AppShapes.radiusMd),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l10n.translate('package_reviews'), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        ReviewListWidget(
                          key: ValueKey('reviews_$_reviewRefreshCounter'),
                          packageId: widget.packageId,
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton(
                            onPressed: () {
                              Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => AllReviewsPage(packageId: widget.packageId)));
                            },
                            child: Text(l10n.translate('package_see_all_reviews'),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ]),
                    ),
                    if (showDelivery || showReturnPolicy) ...[
                      _buildDeliveryAndReturnPolicyRow(),
                      const SizedBox(height: 6),
                    ],
                    if (packageFeatures.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ...packageFeatures.map((f) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(children: [
                              const Icon(Icons.check_circle, size: 16, color: AppColors.success),
                              const SizedBox(width: 6),
                              Text(f, style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary)),
                            ]),
                          )),
                    ],
                  ]),
                ),
              ]),
            ),
            SliverToBoxAdapter(child: _buildSimilarPackagesSection()),
            SliverToBoxAdapter(child: SizedBox(height: 80 + bottomPadding)),
          ],
        ),
        // Sticky header
        Positioned(
          top: topPadding + AppSpacing.sm, left: 0, right: 0,
          child: FadeTransition(
            opacity: _imageIconsFadeAnimation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _TransparentIcon(icon: Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.pop(context)),
                Row(children: [
                  _TransparentIcon(
                      icon: Icons.search_rounded,
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const SearchScreen()))),
                  const SizedBox(width: 8),
                  _TransparentIcon(icon: Icons.share_rounded, onTap: _sharePackage),
                ]),
              ]),
            ),
          ),
        ),
        // Sticky search bar
        FadeTransition(
          opacity: _searchBarFadeAnimation,
          child: Visibility(
            visible: _searchBarFadeAnimation.value > 0.0,
            child: Positioned(
              top: 0, left: 0, right: 0,
              child: Material(
                elevation: 0,
                child: Container(
                  color: AppColors.cardBackground,
                  padding: EdgeInsets.only(top: topPadding),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
                      child: Row(children: [
                        _HeaderIcon(icon: Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.pop(context)),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                                context, MaterialPageRoute(builder: (_) => const SearchScreen())),
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFFE0E0E0), width: 1)),
                              child: Row(children: [
                                const SizedBox(width: 12),
                                Icon(Icons.search_rounded, size: 20, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Text(l10n.translate('package_search_hint'),
                                    style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
                              ]),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        _HeaderIcon(icon: Icons.share_rounded, onTap: _sharePackage),
                      ]),
                    ),
                    if (_showTabs)
                      Container(
                        height: 44,
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: const BoxDecoration(color: AppColors.cardBackground),
                        child: TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                          labelColor: AppColors.primary,
                          unselectedLabelColor: AppColors.textMuted,
                          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                          dividerColor: Colors.transparent,
                          indicator: const BoxDecoration(color: Colors.transparent),
                          indicatorWeight: 0,
                          indicatorPadding: EdgeInsets.zero,
                          overlayColor: WidgetStateProperty.all(Colors.transparent),
                          splashFactory: NoSplash.splashFactory,
                          tabAlignment: TabAlignment.start,
                          tabs: localisedTabs,
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
        // Bottom bar
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Material(
            elevation: 9.8,
            shadowColor: Colors.black.withOpacity(0.15),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppShapes.radiusMd)),
            child: Container(
              padding: EdgeInsets.fromLTRB(AppSpacing.xs, 8, AppSpacing.xs, 8 + bottomPadding),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppShapes.radiusMd)),
              ),
              child: Row(
                children: [
                  _BottomIconCompact(
                    icon: PhosphorIcons.shoppingCart(PhosphorIconsStyle.regular),
                    badgeCount: cartItemCount,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
                    badgeColor: AppColors.error,
                    iconColor: AppColors.textPrimary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _BottomIconCompact(
                    icon: PhosphorIcons.heart(PhosphorIconsStyle.regular),
                    badgeCount: wishlistCount,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WishlistScreen())),
                    badgeColor: AppColors.error,
                    iconColor: AppColors.textPrimary,
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 140,
                    child: OutlinedButton(
                      onPressed: (_shopClosed || _outOfStock || _isCartActionInProgress)
                          ? null
                          : _toggleCart,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _isInCart ? AppColors.primary : AppColors.textPrimary,
                        side: BorderSide(color: _isInCart ? AppColors.primary : AppColors.textPrimary, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
                        backgroundColor: AppColors.cardBackground,
                      ),
                      child: _isCartActionInProgress
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(
                                _isInCart ? Icons.check_rounded : Icons.shopping_cart_outlined,
                                size: 16,
                                color: _isInCart ? AppColors.primary : AppColors.textPrimary,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  _shopClosed
                                      ? l10n.translate('package_shop_closed')
                                      : (_outOfStock
                                          ? l10n.translate('package_out_of_stock')
                                          : (_isInCart ? l10n.translate('package_added') : l10n.translate('package_add_to_cart'))),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _isInCart ? AppColors.primary : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: ElevatedButton(
                      onPressed: (_shopClosed || _outOfStock)
                          ? null
                          : () async {
                              if (!_isInCart) {
                                final prod = _packageToProduct(pkg);
                                await ref.read(cartProvider.notifier).addItem(prod, quantity: _quantity);
                              }
                              if (mounted) Navigator.pushNamed(context, '/checkout');
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (_shopClosed || _outOfStock) ? Colors.grey.shade400 : AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.radiusSm)),
                        elevation: 2,
                      ),
                      child: Text(
                        _shopClosed
                            ? l10n.translate('package_shop_closed')
                            : (_outOfStock
                                ? l10n.translate('package_out_of_stock')
                                : l10n.translate('package_buy_now')),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Fullscreen images
        if (_fullscreenOpen)
          Material(
            color: Colors.black,
            child: Stack(children: [
              PageView.builder(
                controller: _fullscreenPageController,
                physics: const BouncingScrollPhysics(),
                itemCount: _fullscreenImages.length,
                onPageChanged: (index) => setState(() => _fullscreenIndex = index),
                itemBuilder: (context, index) {
                  return InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: Center(
                        child: CachedNetworkImage(
                            imageUrl: _fullscreenImages[index],
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity)),
                  );
                },
              ),
              Positioned(
                  top: 40, right: 20,
                  child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 32),
                      onPressed: _closeFullscreen)),
              if (_fullscreenImages.length > 1)
                Positioned(
                    bottom: 20, left: 0, right: 0,
                    child: Center(
                        child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(
                                '${_fullscreenIndex + 1} / ${_fullscreenImages.length}',
                                style: const TextStyle(color: Colors.white, fontSize: 14))))),
            ]),
          ),
        if (_showProductZoom && _zoomedProductData != null)
          _ProductDetailViewer(
            item: _zoomedProductData!,
            images: _zoomedProductImages,
            pageController: _productZoomPageController,
            onClose: _closeProductZoom,
          ),
      ]),
    );
  }
}

// ─── Helper widgets ─────────────────────
class _BottomIconCompact extends StatelessWidget {
  final PhosphorIconData icon;
  final int badgeCount;
  final VoidCallback onTap;
  final Color? badgeColor;
  final Color? iconColor;
  const _BottomIconCompact(
      {required this.icon,
      required this.badgeCount,
      required this.onTap,
      this.badgeColor,
      this.iconColor});
  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: AppColors.hoverState,
              borderRadius:
                  BorderRadius.circular(AppShapes.radiusSm)),
          child: IconButton(
              padding: EdgeInsets.zero,
              icon: PhosphorIcon(icon,
                  color: iconColor ?? AppColors.textPrimary,
                  size: 22),
              onPressed: onTap)),
      if (badgeCount > 0)
        Positioned(
            right: -4,
            top: -4,
            child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                    color: badgeColor ?? AppColors.error,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white, width: 1.5)),
                constraints: const BoxConstraints(
                    minWidth: 16, minHeight: 16),
                child: Text(
                    badgeCount > 9 ? '9+' : '$badgeCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center))),
    ]);
  }
}

class _TransparentIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;
  const _TransparentIcon(
      {required this.icon, required this.onTap, this.iconColor});
  @override
  State<_TransparentIcon> createState() => _TransparentIconState();
}

class _TransparentIconState extends State<_TransparentIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.9).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _ctrl.forward();
  void _onTapUp(_) {
    _ctrl.reverse();
    widget.onTap();
  }

  void _onTapCancel() => _ctrl.reverse();
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: ScaleTransition(
            scale: _scale,
            child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    shape: BoxShape.circle),
                child: Icon(widget.icon,
                    color: widget.iconColor ?? Colors.white,
                    size: 20))));
  }
}

class _HeaderIcon extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIcon({required this.icon, required this.onTap});
  @override
  State<_HeaderIcon> createState() => _HeaderIconState();
}

class _HeaderIconState extends State<_HeaderIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.9).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _ctrl.forward();
  void _onTapUp(_) {
    _ctrl.reverse();
    widget.onTap();
  }

  void _onTapCancel() => _ctrl.reverse();
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
          scale: _scale,
          child: Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                  color: AppColors.cardBackground,
                  shape: BoxShape.circle),
              child: Icon(widget.icon,
                  color: AppColors.textPrimary, size: 18))));
}

class _ProductDetailViewer extends ConsumerStatefulWidget {
  final Map<String, dynamic> item;
  final List<String> images;
  final PageController? pageController;
  final VoidCallback onClose;
  const _ProductDetailViewer(
      {required this.item,
      required this.images,
      required this.pageController,
      required this.onClose});
  @override
  ConsumerState<_ProductDetailViewer> createState() =>
      _ProductDetailViewerState();
}

class _ProductDetailViewerState extends ConsumerState<_ProductDetailViewer> {
  late Product _product;
  int _currentImageIndex = 0;
  @override
  void initState() {
    super.initState();
    _product = _itemToProduct(widget.item);
    widget.pageController?.addListener(() {
      final page = widget.pageController?.page?.round() ?? 0;
      if (page != _currentImageIndex)
        setState(() => _currentImageIndex = page);
    });
  }

  Product _itemToProduct(Map<String, dynamic> item) {
    final images = safeList<String>(item['image_urls']);
    Map<String, dynamic> productAttrs = {};
    final attrs = safeMap(item['attributes']);
    if (attrs.isNotEmpty) productAttrs = attrs;
    return Product(
        id: item['id'] ?? 0,
        title: item['title'] ?? '',
        price: double.tryParse(item['price']?.toString() ?? '0') ?? 0,
        imageUrl: images.isNotEmpty ? images.first : '',
        images: images,
        rating: 0.0,
        reviewsCount: 0,
        soldCount: 0,
        freeShipping: false,
        effectivePrice: double.tryParse(
                item['effective_price']?.toString() ??
                    item['price']?.toString() ??
                    '0') ??
            0,
        description: item['description']?.toString(),
        productAttributes: productAttrs,
        videoUrls: safeList<String>(item['video_urls']));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final hasMultiple = widget.images.length > 1;

    // Dimensions & weight for this product
    final weightKg = widget.item['weight_kg'];
    final lengthCm = widget.item['length_cm'];
    final widthCm = widget.item['width_cm'];
    final heightCm = widget.item['height_cm'];
    final hasDimensions = weightKg != null || lengthCm != null || widthCm != null || heightCm != null;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
          backgroundColor: AppColors.cardBackground,
          elevation: 0,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppColors.textPrimary),
              onPressed: widget.onClose),
          title: Text(_product.title,
              style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 16))),
      body: Column(children: [
        SizedBox(
            height: 360,
            child: Stack(children: [
              PageView.builder(
                  controller: widget.pageController,
                  physics: const BouncingScrollPhysics(),
                  itemCount: widget.images.length,
                  itemBuilder: (_, index) => InteractiveViewer(
                      child: CachedNetworkImage(
                          imageUrl: widget.images[index],
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity))),
              if (hasMultiple)
                Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius:
                                BorderRadius.circular(20)),
                        child: Text(
                            '${_currentImageIndex + 1} / ${widget.images.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12)))),
            ])),
        Expanded(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_product.title,
                          style: textTheme.headlineMedium?.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                          'ETB ${formatPrice(_product.effectivePrice ?? _product.price)}',
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.error)),
                      if (_product.description != null &&
                          _product.description!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(l10n.translate('package_description'),
                            style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: AppSpacing.xs),
                        Text(_product.description!,
                            style: textTheme.bodyMedium?.copyWith(
                                height: 1.5,
                                color: AppColors.textPrimary))
                      ],
                      // ★ Dimensions & Weight
                      if (hasDimensions) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text('Dimensions & Weight',
                            style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            if (weightKg != null)
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.monitor_weight_outlined, size: 16, color: AppColors.textMuted),
                                const SizedBox(width: 4),
                                Text('$weightKg kg', style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary)),
                              ]),
                            if (lengthCm != null)
                              Text('Length: $lengthCm cm', style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary)),
                            if (widthCm != null)
                              Text('Width: $widthCm cm', style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary)),
                            if (heightCm != null)
                              Text('Height: $heightCm cm', style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary)),
                          ],
                        ),
                      ],
                      if (_product.productAttributes != null &&
                          _product.productAttributes!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(l10n.translate('package_specifications'),
                            style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: AppSpacing.xs),
                        ..._product.productAttributes!.entries.map(
                            (e) => Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4),
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                          width: 100,
                                          child: Text(
                                              e.key.replaceAll(
                                                  '_', ' '),
                                              style: textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                      color: AppColors
                                                          .textMuted))),
                                      Expanded(
                                          child: Text(
                                              e.value.toString(),
                                              style: textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight
                                                              .w500,
                                                      color: AppColors
                                                          .textPrimary)))
                                    ])))
                      ]
                    ]))),
      ]),
    );
  }
}

// ─── Full‑screen video player ──
class _FullVideoPlayerScreen extends StatefulWidget {
  final String url;
  const _FullVideoPlayerScreen({required this.url});
  @override
  State<_FullVideoPlayerScreen> createState() =>
      _FullVideoPlayerScreenState();
}

class _FullVideoPlayerScreenState extends State<_FullVideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false,
      _showControls = true,
      _isSeeking = false;
  Timer? _hideControlsTimer;
  String? _errorMessage;

  bool _showSkipOverlay = false;
  bool _skipForward = true;
  Timer? _skipOverlayTimer;

  bool _longPressActive = false;
  double _normalSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _controller =
          VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _controller.addListener(_onControllerUpdate);
      await _controller.initialize();
      if (mounted) {
        setState(() {
          _initialized = true;
          _errorMessage = null;
        });
        _controller.play();
        _startHideControlsTimer();
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _errorMessage = 'Could not load video:\n$e';
        });
    }
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    final value = _controller.value;
    if (value.hasError) {
      setState(() {
        _errorMessage = 'Video error: ${value.errorDescription}';
        _initialized = false;
      });
      return;
    }
    if (!_initialized && value.isInitialized)
      setState(() => _initialized = true);
    if (value.isPlaying || value.isBuffering || _isSeeking || _showControls) {
      setState(() {});
    } else {
      if (value.position != value.duration) setState(() {});
    }
  }

  void _togglePlayPause() {
    if (!_initialized || _controller.value.hasError) return;
    setState(() {
      if (_controller.value.isPlaying)
        _controller.pause();
      else
        _controller.play();
      _showControls = true;
      _startHideControlsTimer();
    });
  }

  void _onSeekStart(double _) {
    if (!_initialized) return;
    setState(() {
      _isSeeking = true;
      _showControls = true;
    });
    _hideControlsTimer?.cancel();
    if (_controller.value.isPlaying) _controller.pause();
  }

  void _onSeekUpdate(double seconds) {
    if (!_initialized) return;
    _controller.seekTo(
        Duration(milliseconds: (seconds * 1000).toInt()));
  }

  void _onSeekEnd(double seconds) {
    if (!_initialized) return;
    _controller.seekTo(
        Duration(milliseconds: (seconds * 1000).toInt()));
    setState(() {
      _isSeeking = false;
    });
    if (_controller.value.isInitialized &&
        !_controller.value.hasError) _controller.play();
    _startHideControlsTimer();
  }

  void _onTapScreen() {
    _togglePlayPause();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          _controller.value.isPlaying &&
          !_isSeeking) setState(() => _showControls = false);
    });
  }

  void _triggerSkipOverlay(bool forward) {
    setState(() {
      _skipForward = forward;
      _showSkipOverlay = true;
    });
    _skipOverlayTimer?.cancel();
    _skipOverlayTimer =
        Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showSkipOverlay = false);
    });
  }

  void _seekRelative(int seconds) {
    if (_initialized && !_controller.value.hasError) {
      final newPos = _controller.value.position +
          Duration(seconds: seconds);
      final target = newPos < Duration.zero
          ? Duration.zero
          : newPos > _controller.value.duration
              ? _controller.value.duration
              : newPos;
      _controller.seekTo(target);
    }
  }

  void _startLongPress() {
    if (_initialized && _controller.value.isPlaying) {
      setState(() => _longPressActive = true);
      _controller.setPlaybackSpeed(2.0);
    }
  }

  void _endLongPress() {
    if (_longPressActive) {
      _controller.setPlaybackSpeed(_normalSpeed);
      setState(() => _longPressActive = false);
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _skipOverlayTimer?.cancel();
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
              backgroundColor: Colors.black,
              leading: IconButton(
                  icon: const Icon(Icons.close,
                      color: Colors.white),
                  onPressed: () =>
                      Navigator.pop(context))),
          body: Center(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(_errorMessage!,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16),
                      textAlign: TextAlign.center))));
    }
    if (!_initialized)
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
              child:
                  CircularProgressIndicator(color: Colors.white)));

    final video = _controller.value;
    final position = video.position,
        duration = video.duration,
        isPlaying = video.isPlaying;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTapDown: (details) {
          final halfWidth = (context.size?.width ?? 0) / 2;
          final tapX = details.localPosition.dx;
          if (tapX < halfWidth) {
            _seekRelative(-10);
            _triggerSkipOverlay(false);
          } else {
            _seekRelative(10);
            _triggerSkipOverlay(true);
          }
        },
        onLongPressStart: (_) => _startLongPress(),
        onLongPressEnd: (_) => _endLongPress(),
        onTap: _onTapScreen,
        child: Stack(
          children: [
            Center(
                child: AspectRatio(
                    aspectRatio: video.aspectRatio,
                    child: VideoPlayer(_controller))),
            if (video.isBuffering)
              const Center(
                  child:
                      CircularProgressIndicator(color: Colors.white)),
            Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                child: IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.white),
                    onPressed: () => Navigator.pop(context))),
            IgnorePointer(
              ignoring: !_showControls,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                            gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                              Colors.black.withOpacity(0.9),
                              Colors.transparent
                            ])),
                        child: SafeArea(
                            top: false,
                            child: Row(children: [
                              Text(_formatDuration(position),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12)),
                              Expanded(
                                  child: SliderTheme(
                                      data: SliderTheme.of(context)
                                          .copyWith(
                                              trackHeight: 4,
                                              thumbShape:
                                                  const RoundSliderThumbShape(
                                                      enabledThumbRadius:
                                                          8),
                                              overlayShape:
                                                  const RoundSliderOverlayShape(
                                                      overlayRadius:
                                                          16),
                                              activeTrackColor:
                                                  AppColors.primary,
                                              inactiveTrackColor:
                                                  Colors.white24,
                                              thumbColor:
                                                  AppColors.primary,
                                              overlayColor: AppColors
                                                  .primary
                                                  .withOpacity(0.3)),
                                      child: Slider(
                                          value: position
                                              .inMilliseconds
                                              .clamp(
                                                  0,
                                                  duration
                                                      .inMilliseconds)
                                              .toDouble(),
                                          max: duration.inMilliseconds
                                              .toDouble()
                                              .clamp(1.0,
                                                  double.infinity),
                                          onChangeStart:
                                              _onSeekStart,
                                          onChanged: (v) =>
                                              _onSeekUpdate(
                                                  v / 1000),
                                          onChangeEnd: (v) =>
                                              _onSeekEnd(
                                                  v / 1000)))),
                              Text(_formatDuration(duration),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12)),
                            ])),
                      ),
                    ),
                    Center(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _onTapScreen,
                          borderRadius:
                              BorderRadius.circular(32),
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: Colors.white
                                  .withOpacity(0.85),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: AppColors.primary,
                              size: 40,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_showSkipOverlay)
              Align(
                alignment: _skipForward
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _skipForward
                            ? Icons.fast_forward_rounded
                            : Icons.fast_rewind_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                      const SizedBox(width: 6),
                      const Text('10 s',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours),
        minutes = twoDigits(d.inMinutes.remainder(60)),
        seconds = twoDigits(d.inSeconds.remainder(60));
    return d.inHours > 0
        ? '$hours:$minutes:$seconds'
        : '$minutes:$seconds';
  }
}

// ─── Simple similar package card (no badge) ─────────
class _SimilarPackageCard extends StatelessWidget {
  final Package package;
  const _SimilarPackageCard({required this.package});

  @override
  Widget build(BuildContext context) {
    final imageUrl = package.imageUrls.isNotEmpty ? package.imageUrls.first : 'https://placehold.co/400x400?text=No+Image';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppShapes.radiusSm),
        border: Border.all(color: AppColors.borderLight, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppShapes.radiusSm)),
            child: AspectRatio(
              aspectRatio: 1.0,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.image, size: 32, color: AppColors.textMuted),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(package.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('ETB ${formatPrice(package.price)}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}