// lib/screens/legal_page_viewer.dart
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import '../api/client.dart';
import '../theme/app_theme.dart';

class LegalPageViewer extends StatefulWidget {
  final String keyName;
  const LegalPageViewer({super.key, required this.keyName});

  @override
  State<LegalPageViewer> createState() => _LegalPageViewerState();
}

class _LegalPageViewerState extends State<LegalPageViewer> {
  Map<String, dynamic>? _page;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPage();
  }

  Future<void> _fetchPage() async {
    try {
      final res = await ApiClient.instance.get('/legal/${widget.keyName}');
      if (mounted) {
        setState(() {
          _page = res.data as Map<String, dynamic>?;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _page = null;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.pageBackground,
        appBar: AppBar(
          backgroundColor: AppColors.cardBackground,
          title: const Text('Loading...'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_page == null) {
      return Scaffold(
        backgroundColor: AppColors.pageBackground,
        appBar: AppBar(
          backgroundColor: AppColors.cardBackground,
          title: const Text('Page not found'),
        ),
        body: const Center(
          child: Text('Could not load legal page.',
              style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }

    final title = _page!['title'] as String? ?? '';
    final body = _page!['body'] as String? ?? '';
    final version = _page!['version']?.toString() ?? '';
    final updatedAt = _page!['updated_at']?.toString() ?? '';

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: AppColors.textPrimary)),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: Container(
            color: AppColors.borderLight,
            height: 1,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Version meta ─────────────────────────
            Row(
              children: [
                Icon(Icons.info_outline,
                    size: 14, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  'Version $version · $updatedAt',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Content card with watermark ──────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.borderLight.withOpacity(0.6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Watermark – perfectly fitting inside the card
                  Positioned.fill(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Transform.rotate(
                        angle: -0.2,
                        child: Text(
                          'ET MARKETPLACE',
                          style: TextStyle(
                            fontSize: 100, // will be scaled down by FittedBox
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary.withOpacity(0.04),
                            letterSpacing: 8,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Content – readable, professional typography
                  Html(
                    data: body,
                    style: {
                      'body': Style(
                        fontSize: FontSize(14),
                        color: AppColors.textPrimary,
                        lineHeight: LineHeight(1.55),
                        margin: Margins.zero,
                      ),
                      'h2': Style(
                        fontSize: FontSize(16),
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        margin: Margins.only(top: 20, bottom: 6),
                        padding: HtmlPaddings.only(bottom: 6),
                        border: Border(
                          bottom: BorderSide(
                            color: AppColors.borderLight,
                            width: 1,
                          ),
                        ),
                      ),
                      'h3': Style(
                        fontSize: FontSize(14),
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        margin: Margins.only(top: 14, bottom: 4),
                      ),
                      'p': Style(
                        margin: Margins.only(bottom: 10),
                      ),
                      'ul': Style(
                        margin: Margins.only(bottom: 10),
                      ),
                      'ol': Style(
                        margin: Margins.only(bottom: 10),
                      ),
                      'li': Style(
                        margin: Margins.only(bottom: 2),
                      ),
                      'strong': Style(
                        fontWeight: FontWeight.w700,
                      ),
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── Footer ──────────────────────────────
            Center(
              child: Column(
                children: [
                  Text(
                    '© ${DateTime.now().year} ET Marketplace. All rights reserved.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'For questions about this policy, contact support@etmarketplace.com',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}