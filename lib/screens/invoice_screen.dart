// 📁 lib/screens/invoice_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../api/client.dart';
import '../theme/app_theme.dart';

class OrderInvoiceScreen extends StatefulWidget {
  final int orderId;
  const OrderInvoiceScreen({Key? key, required this.orderId}) : super(key: key);

  @override
  State<OrderInvoiceScreen> createState() => _OrderInvoiceScreenState();
}

class _OrderInvoiceScreenState extends State<OrderInvoiceScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    _loadInvoice();
  }

  Future<void> _loadInvoice() async {
    try {
      final response = await ApiClient.instance.get(
        '/orders/${widget.orderId}/invoice_data',
      );
      final html = response.data['html'] as String;
      final baseUrl = ApiClient.instance.dio.options.baseUrl;

      // ─── Mobile‑optimised overrides that preserve original header ───
      final mobileFix = '''
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
      <style>
        html, body {
          overflow: visible !important;
          margin: 0 !important;
          padding: 0 !important;
          width: 100% !important;
        }
        .invoice-wrapper, .invoice-container {
          max-width: 100% !important;
          padding: 10px !important;
          border: none !important;
          box-shadow: none !important;
          margin: 0 auto !important;
          overflow: hidden !important;
        }
        .watermark {
          font-size: 45px !important;
          top: 50% !important;
          left: 50% !important;
          transform: translate(-50%, -50%) rotate(-25deg) !important;
          color: rgba(0,0,0,0.05) !important;
          letter-spacing: 2px !important;
        }
        .content {
          padding: 0 !important;
        }
        /* Slightly reduce logo only if necessary for small screens */
        .logo {
          height: 38px !important;
        }
        table {
          font-size: 11px !important;
        }
        thead th, tbody td {
          padding: 6px 4px !important;
        }
        .totals-table {
          margin-left: auto !important;
        }
        .footer {
          margin-top: 16px !important;
          padding-top: 12px !important;
        }
      </style>
      ''';

      final fixedHtml = html.contains('</head>')
          ? html.replaceFirst('</head>', '$mobileFix</head>')
          : '$mobileFix\n$html';

      final withBase = '<base href="$baseUrl/">\n' + fixedHtml;

      await _controller.loadHtmlString(withBase);
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load invoice.\n$e';
        });
      }
    }
  }

  Future<void> _downloadPdf() async {
    try {
      // 1. Fetch base64‑encoded PDF from the authenticated endpoint
      final response = await ApiClient.instance.get(
        '/orders/${widget.orderId}/invoice_pdf_data',
      );
      final pdfBase64 = response.data['pdf_base64'] as String;
      final bytes = base64Decode(pdfBase64);

      // 2. Save to temporary file
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/invoice_${widget.orderId}.pdf');
      await file.writeAsBytes(bytes, flush: true);

      // 3. Open the PDF
      await OpenFilex.open(file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: Text(
          'Invoice',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: AppColors.textPrimary),
            onPressed: _downloadPdf,
            tooltip: 'Download PDF',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return SafeArea(
      child: WebViewWidget(controller: _controller),
    );
  }
}