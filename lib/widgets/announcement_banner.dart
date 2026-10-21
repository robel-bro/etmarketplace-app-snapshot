import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/client.dart';

class AnnouncementFloatingIcon extends StatefulWidget {
  const AnnouncementFloatingIcon({Key? key}) : super(key: key);

  @override
  State<AnnouncementFloatingIcon> createState() => _AnnouncementFloatingIconState();
}

class _AnnouncementFloatingIconState extends State<AnnouncementFloatingIcon> {
  Map<String, dynamic>? _announcement;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetchAnnouncement();
  }

  Future<void> _fetchAnnouncement() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.get('/api/v1/announcements');
      final list = res.data as List;
      if (list.isNotEmpty && mounted) {
        setState(() => _announcement = Map<String, dynamic>.from(list.first));
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _showDetails() {
    if (_announcement == null) return;
    final title = _announcement!['title'] ?? '';
    final content = _announcement!['content'] ?? '';
    final link = _announcement!['link'] as String?;

    showDialog(
      context: context,
      builder: (ctx) => Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with gradient
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      gradient: LinearGradient(
                        colors: [Color(0xFFFF9800), Color(0xFFFFB74D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.2),
                          ),
                          child: const Icon(
                            Icons.campaign,
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Body
                  if (content.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Text(
                        content,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  // Actions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);           // close dialog
                            setState(() {
                              _announcement = null;       // ★ remove floating icon
                            });
                          },
                          child: const Text(
                            'DISMISS',
                            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (link != null && link.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final uri = Uri.tryParse(link);
                              if (uri != null && await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                              Navigator.pop(ctx);
                            },
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('OPEN'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_announcement == null) return const SizedBox.shrink();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        FloatingActionButton.small(
          onPressed: _showDetails,
          backgroundColor: Colors.orange,
          child: const Icon(Icons.campaign, color: Colors.white, size: 20),
        ),
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            constraints: const BoxConstraints(
              minWidth: 16,
              minHeight: 16,
            ),
            child: const Text(
              '1',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}