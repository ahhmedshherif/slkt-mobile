import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/common.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});

  final Future<void> Function() onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final controller = PageController();
  int page = 0;
  bool completing = false;

  static const pages = [
    _OnboardingPageData(
      eyebrow: 'DISCOVER',
      title: 'Find events worth going out for.',
      message:
          'Explore upcoming experiences, compare dates and venues, and keep the best nights close.',
      icon: Icons.explore_rounded,
      accent: AppColors.lavender,
    ),
    _OnboardingPageData(
      eyebrow: 'BOOK',
      title: 'Choose your ticket. Pay securely.',
      message:
          'Pick the right session and ticket type, then finish payment through Paymob without losing your reservation.',
      icon: Icons.shopping_bag_rounded,
      accent: AppColors.yellow,
    ),
    _OnboardingPageData(
      eyebrow: 'ENTER',
      title: 'Your ticket is ready at the door.',
      message:
          'Open your wallet, brighten the QR, transfer safely, and get through the gate smoothly.',
      icon: Icons.qr_code_2_rounded,
      accent: Color(0xFF8DE5C3),
    ),
  ];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (page < pages.length - 1) {
      await controller.nextPage(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 520),
        curve: const Cubic(0.05, 0.7, 0.1, 1),
      );
      return;
    }
    setState(() => completing = true);
    await widget.onComplete();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.black,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
            child: Row(
              children: [
                const BrandMark(dark: true, height: 32),
                const Spacer(),
                if (page < pages.length - 1)
                  TextButton(
                    onPressed: completing ? null : widget.onComplete,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                    ),
                    child: const Text('Skip'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: controller,
              itemCount: pages.length,
              onPageChanged: (value) => setState(() => page = value),
              itemBuilder: (context, index) => _OnboardingPage(
                data: pages[index],
                active: index == page,
                index: index,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    pages.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      width: index == page ? 28 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: index == page
                            ? pages[page].accent
                            : Colors.white24,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const ValueKey('onboarding-next'),
                  onPressed: completing ? null : _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: pages[page].accent,
                    foregroundColor: AppColors.black,
                  ),
                  child: completing
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          page == pages.length - 1
                              ? 'Start exploring'
                              : 'Continue',
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

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.data,
    required this.active,
    required this.index,
  });

  final _OnboardingPageData data;
  final bool active;
  final int index;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Center(
              child: AnimatedScale(
                scale: active ? 1 : .86,
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 620),
                curve: const Cubic(0.05, 0.7, 0.1, 1),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 270,
                      height: 270,
                      decoration: BoxDecoration(
                        color: data.accent.withValues(alpha: .16),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Transform.rotate(
                      angle: index == 1 ? -.08 : .06,
                      child: Container(
                        width: 210,
                        height: 250,
                        decoration: BoxDecoration(
                          color: data.accent,
                          borderRadius: BorderRadius.circular(34),
                        ),
                        child: Icon(
                          data.icon,
                          size: 104,
                          color: AppColors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Text(
            data.eyebrow,
            style: TextStyle(
              color: data.accent,
              fontSize: 12,
              letterSpacing: 2.4,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            data.title,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: Colors.white,
              height: 1.04,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            data.message,
            style: const TextStyle(color: Colors.white60, height: 1.55),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.eyebrow,
    required this.title,
    required this.message,
    required this.icon,
    required this.accent,
  });

  final String eyebrow;
  final String title;
  final String message;
  final IconData icon;
  final Color accent;
}
