import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme.dart';

enum LegalPage {
  privacyPolicy(
    title: 'Privacy policy',
    path: '/privacy-policy',
    icon: Icons.privacy_tip_outlined,
  ),
  termsConditions(
    title: 'Terms & conditions',
    path: '/terms-conditions',
    icon: Icons.article_outlined,
  ),
  purchasePolicy(
    title: 'Purchase & refund policy',
    path: '/purchase-policy',
    icon: Icons.receipt_long_outlined,
  ),
  faqs(title: 'FAQs', path: '/faqs', icon: Icons.quiz_outlined),
  contactUs(
    title: 'Contact us',
    path: '/contact-us',
    icon: Icons.support_agent_outlined,
  );

  const LegalPage({
    required this.title,
    required this.path,
    required this.icon,
  });
  final String title;
  final String path;
  final IconData icon;
  Uri get uri => Uri.https('tktsapp.com', path);
}

/// Public legal/support content remains website-managed. This view permits only
/// its exact TKTS APP page; native app keeps all other navigation ownership.
class LegalWebViewScreen extends StatefulWidget {
  const LegalWebViewScreen({super.key, required this.page});
  final LegalPage page;

  @override
  State<LegalWebViewScreen> createState() => _LegalWebViewScreenState();
}

class _LegalWebViewScreenState extends State<LegalWebViewScreen> {
  late final WebViewController _controller;
  var _loading = true;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(AppColors.ivory)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final target = Uri.tryParse(request.url);
            final documentRequest =
                target != null &&
                target.scheme == 'https' &&
                target.host == widget.page.uri.host &&
                target.path == widget.page.path &&
                target.query.isEmpty &&
                target.fragment.isEmpty;
            final contactSubmit =
                target != null &&
                widget.page == LegalPage.contactUs &&
                target.scheme == 'https' &&
                target.host == widget.page.uri.host &&
                target.path == '/contact-submissions';
            return documentRequest || contactSubmit
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true || !mounted) return;
            setState(() {
              _loading = false;
              _failed = true;
            });
          },
        ),
      )
      ..loadRequest(widget.page.uri);
  }

  Future<void> _retry() async {
    setState(() {
      _failed = false;
      _loading = true;
    });
    await _controller.loadRequest(widget.page.uri);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.ivory,
    appBar: AppBar(
      title: Text(widget.page.title),
      centerTitle: true,
      actions: [
        IconButton(
          tooltip: 'Reload',
          onPressed: _retry,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_failed)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.page.icon, size: 46, color: AppColors.burgundy),
                  const SizedBox(height: 14),
                  Text(
                    'Could not load this page',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Check connection, then try again.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
