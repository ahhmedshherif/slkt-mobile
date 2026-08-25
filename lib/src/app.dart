import 'dart:async';
import 'dart:math' as math;

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/api_client.dart';
import 'core/push_notifications.dart';
import 'core/session_controller.dart';
import 'core/theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/buyer/buyer_shell.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'widgets/common.dart';

bool isTicketsAppLink(Uri link) {
  final isWebTicketsLink =
      link.scheme == 'https' &&
      link.host.toLowerCase() == 'tktsapp.com' &&
      (link.path == '/tickets' || link.path.startsWith('/tickets/'));
  final isCustomTicketsLink =
      link.scheme == 'slkt' && link.host.toLowerCase() == 'tickets';
  return isWebTicketsLink || isCustomTicketsLink;
}

class EvntsApp extends StatefulWidget {
  const EvntsApp({
    super.key,
    required this.api,
    required this.session,
    required this.pushNotifications,
  });

  final ApiClient api;
  final SessionController session;
  final PushNotifications pushNotifications;

  @override
  State<EvntsApp> createState() => _EvntsAppState();
}

class _EvntsAppState extends State<EvntsApp> {
  static const currentBuild = 4009;
  final navigatorKey = GlobalKey<NavigatorState>();
  Timer? timer;
  final AppLinks appLinks = AppLinks();
  StreamSubscription<Uri>? appLinkSubscription;
  bool minimumSplashDone = false;
  Map<String, dynamic>? mobileUpdate;
  bool updateCheckDone = false;
  bool updateSkipped = false;
  bool onboardingChecked = false;
  bool onboardingComplete = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      timer = Timer(const Duration(milliseconds: 4200), () {
        if (mounted) setState(() => minimumSplashDone = true);
      });
    });
    appLinkSubscription = appLinks.uriLinkStream.listen(_handleAppLink);
    unawaited(_readInitialAppLink());
    unawaited(_loadOnboarding());
    _checkForUpdate();
  }

  Future<void> _loadOnboarding() async {
    final preferences = await SharedPreferences.getInstance();
    onboardingComplete =
        preferences.getBool('tkts_onboarding_complete') ?? false;
    onboardingChecked = true;
    if (mounted) setState(() {});
  }

  Future<void> _completeOnboarding() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('tkts_onboarding_complete', true);
    if (mounted) {
      setState(() {
        onboardingComplete = true;
        onboardingChecked = true;
      });
    }
  }

  Future<void> _readInitialAppLink() async {
    try {
      final initialLink = await appLinks.getInitialLink();
      if (initialLink != null) _handleAppLink(initialLink);
    } catch (_) {
      // A malformed external link must never block app startup.
    }
  }

  void _handleAppLink(Uri link) {
    if (isTicketsAppLink(link)) {
      widget.session.requestOpenTickets();
    }
  }

  Future<void> _checkForUpdate() async {
    try {
      final response = await widget.api.get(
        '/mobile/bootstrap',
        query: const {'platform': 'android', 'current_build': currentBuild},
      );
      final data = response['data'];
      if (data is Map && data['mobile_update'] is Map) {
        mobileUpdate = Map<String, dynamic>.from(data['mobile_update'] as Map);
      }
    } catch (_) {
      // A temporary connectivity problem must never lock users out of the app.
    } finally {
      updateCheckDone = true;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    appLinkSubscription?.cancel();
    widget.pushNotifications.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TKTS APP',
    navigatorKey: navigatorKey,
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    builder: (context, child) => _EdgeSwipeBack(
      navigatorKey: navigatorKey,
      child: child ?? const SizedBox.shrink(),
    ),
    home: AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        final showSplash =
            widget.session.restoring ||
            !minimumSplashDone ||
            !updateCheckDone ||
            !onboardingChecked;
        final Widget destination;
        if (showSplash) {
          destination = const SplashScreen(key: ValueKey('slkt-splash'));
        } else if (mobileUpdate?['update_available'] == true &&
            !updateSkipped) {
          destination = AppUpdateScreen(
            key: const ValueKey('app-update'),
            update: mobileUpdate!,
            onLater: mobileUpdate?['force_update'] == true
                ? null
                : () => setState(() => updateSkipped = true),
          );
        } else if (!onboardingComplete) {
          destination = OnboardingScreen(
            key: const ValueKey('onboarding'),
            onComplete: _completeOnboarding,
          );
        } else {
          destination = switch (widget.session.kind) {
            SessionKind.buyer => BuyerShell(
              key: const ValueKey('buyer-shell'),
              api: widget.api,
              session: widget.session,
            ),
            SessionKind.guest => AuthScreen(
              key: const ValueKey('guest-shell'),
              api: widget.api,
              session: widget.session,
            ),
          };
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 560),
          reverseDuration: const Duration(milliseconds: 320),
          switchInCurve: const Cubic(0.05, 0.7, 0.1, 1),
          switchOutCurve: const Cubic(0.3, 0, 1, 1),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: .975, end: 1).animate(animation),
              child: child,
            ),
          ),
          child: destination,
        );
      },
    ),
  );
}

class AppUpdateScreen extends StatelessWidget {
  const AppUpdateScreen({
    super.key,
    required this.update,
    required this.onLater,
  });

  final Map<String, dynamic> update;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context) {
    final forced = update['force_update'] == true;
    final notes = (update['release_notes'] ?? '').toString().trim();
    final url = Uri.tryParse((update['download_url'] ?? '').toString());

    return Scaffold(
      backgroundColor: AppColors.yellow,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),
              const BrandMark(height: 74),
              const SizedBox(height: 42),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  color: AppColors.black,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 30,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      forced ? Icons.security_rounded : Icons.auto_awesome,
                      color: AppColors.yellow,
                      size: 34,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      forced
                          ? 'Critical update required'
                          : 'A smarter TKTS APP is ready',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Version ${update['latest_version'] ?? ''}',
                      style: const TextStyle(
                        color: Color(0xFFBDBDBD),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        notes,
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: url == null
                            ? null
                            : () => launchUrl(
                                url,
                                mode: LaunchMode.externalApplication,
                              ),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Update now'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.yellow,
                          foregroundColor: AppColors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    if (onLater != null)
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: onLater,
                          child: const Text(
                            'Later',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _EdgeSwipeBack extends StatefulWidget {
  const _EdgeSwipeBack({required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<_EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<_EdgeSwipeBack> {
  double dragDistance = 0;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final progress = (dragDistance / 72).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          left: 0,
          top: MediaQuery.paddingOf(context).top + 64,
          bottom: MediaQuery.paddingOf(context).bottom + 64,
          width: 28,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (_) {
                    if (widget.navigatorKey.currentState?.canPop() ?? false) {
                      setState(() => dragDistance = 1);
                    }
                  },
                  onHorizontalDragUpdate: (details) {
                    if (dragDistance == 0 || details.delta.dx <= 0) return;
                    setState(() {
                      dragDistance = (dragDistance + details.delta.dx).clamp(
                        0,
                        104,
                      );
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    final shouldPop =
                        dragDistance >= 64 ||
                        details.primaryVelocity != null &&
                            details.primaryVelocity! > 650;
                    setState(() => dragDistance = 0);
                    if (shouldPop) widget.navigatorKey.currentState?.maybePop();
                  },
                  onHorizontalDragCancel: () =>
                      setState(() => dragDistance = 0),
                ),
              ),
              if (dragDistance > 0)
                EdgeSwipeShadow(progress: progress, reduceMotion: reduceMotion),
            ],
          ),
        ),
      ],
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.forward();
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced && !controller.isCompleted) controller.value = 1;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _CinematicSplashCanvas(
        progress: controller.value,
        reduceMotion: reduced,
      ),
    );
  }
}

class _CinematicSplashCanvas extends StatelessWidget {
  const _CinematicSplashCanvas({
    required this.progress,
    required this.reduceMotion,
  });

  final double progress;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final p = reduceMotion ? 1.0 : progress;
    final groupShift = Curves.easeInOutCubic.transform(
      _splashInterval(p, .22, .46),
    );
    final appReveal = Curves.easeOutCubic.transform(
      _splashInterval(p, .38, .72),
    );
    final dotFade =
        1 - Curves.easeInCubic.transform(_splashInterval(p, .69, .79));
    final settle = Curves.easeOutCubic.transform(_splashInterval(p, .70, .88));
    final contrast = Curves.easeInOutCubic.transform(
      _splashInterval(p, .28, .53),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: p < .34 ? AppSystemUi.dark : AppSystemUi.light,
      child: Scaffold(
        backgroundColor: AppColors.ivory,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final tktsWidth = math.min(size.width * .59, 276.0);
            final tktsHeight = tktsWidth * (140 / 470);
            final tktsContentWidth = tktsWidth * (402 / 470);
            final appHeight = tktsHeight * .48;
            final appWidth = appHeight * (157 / 56);
            final gap = math.max(7.0, tktsHeight * .09);
            final groupWidth = tktsContentWidth + gap + appWidth;
            final openingLeft = (size.width - tktsWidth) / 2;
            final finalLeft = (size.width - groupWidth) / 2;
            final logoLeft =
                openingLeft + (finalLeft - openingLeft) * groupShift;
            final logoTop = (size.height - tktsHeight) / 2 + 8 * (1 - settle);
            final appLeft = finalLeft + tktsContentWidth + gap;
            final appTop = logoTop + tktsHeight * .46;
            final dotStart = Offset(
              openingLeft + tktsWidth * (425.6 / 470),
              (size.height - tktsHeight) / 2 + tktsHeight * (108.5 / 140),
            );
            final dotDock = Offset(
              appLeft - gap * .35,
              appTop + appHeight * .70,
            );
            final dotAcross = Offset(
              appLeft + appWidth,
              appTop + appHeight * .70,
            );
            final dockProgress = Curves.easeInOutCubic.transform(
              _splashInterval(p, .22, .42),
            );
            final slideProgress = Curves.easeInOutCubic.transform(
              _splashInterval(p, .40, .72),
            );
            final dockedDot = Offset.lerp(dotStart, dotDock, dockProgress)!;
            final movingDot = Offset.lerp(dockedDot, dotAcross, slideProgress)!;
            final dotRadius = math.max(6.0, tktsHeight * (14.5 / 140));
            final dotStretch = math.sin(appReveal * math.pi).clamp(0.0, 1.0);
            final dotWidth = dotRadius * 2 * (1 + .72 * dotStretch);
            final logoColor = Color.lerp(
              AppColors.burgundy,
              AppColors.ivory,
              contrast,
            )!;

            return Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _DotRevealBackgroundPainter(
                      progress: p,
                      origin: dotStart,
                    ),
                  ),
                ),
                Positioned(
                  left: logoLeft,
                  top: logoTop,
                  width: tktsWidth,
                  height: tktsHeight,
                  child: SvgPicture.asset(
                    'assets/brand/tkts-reference-traced-letters.svg',
                    key: const ValueKey('splash-primary-logo'),
                    fit: BoxFit.contain,
                    colorFilter: ColorFilter.mode(logoColor, BlendMode.srcIn),
                  ),
                ),
                Positioned(
                  left: appLeft,
                  top: appTop,
                  width: appWidth,
                  height: appHeight,
                  child: ClipRect(
                    clipper: _HorizontalRevealClipper(appReveal),
                    child: Transform.translate(
                      offset: Offset(18 * (1 - appReveal), 0),
                      child: Opacity(
                        opacity: appReveal,
                        child: SvgPicture.asset(
                          'assets/brand/tkts-app-label.svg',
                          key: const ValueKey('splash-app-logo'),
                          width: appWidth,
                          height: appHeight,
                          fit: BoxFit.fill,
                        ),
                      ),
                    ),
                  ),
                ),
                for (var echo = 0; echo < 2; echo++)
                  if (p > .30 && p < .72)
                    Positioned(
                      left: movingDot.dx - dotRadius - 8 - echo * 9,
                      top: movingDot.dy - dotRadius,
                      width: dotRadius * 2,
                      height: dotRadius * 2,
                      child: Opacity(
                        opacity: (.15 - echo * .045) * dotFade,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppColors.gold,
                              width: 1.2,
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                Positioned(
                  left: movingDot.dx - dotWidth / 2,
                  top: movingDot.dy - dotRadius,
                  width: dotWidth,
                  height: dotRadius * 2,
                  child: Opacity(
                    opacity: dotFade,
                    child: DecoratedBox(
                      key: const ValueKey('splash-signature-dot'),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(dotRadius),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.gold.withValues(alpha: .22),
                            blurRadius: 22,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

double _splashInterval(double value, double begin, double end) =>
    ((value - begin) / (end - begin)).clamp(0.0, 1.0);

class _HorizontalRevealClipper extends CustomClipper<Rect> {
  const _HorizontalRevealClipper(this.progress);

  final double progress;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * progress, size.height);

  @override
  bool shouldReclip(covariant _HorizontalRevealClipper oldClipper) =>
      oldClipper.progress != progress;
}

class _DotRevealBackgroundPainter extends CustomPainter {
  const _DotRevealBackgroundPainter({
    required this.progress,
    required this.origin,
  });

  final double progress;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.ivory);
    final corners = <Offset>[
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    final maxRadius = corners
        .map((corner) => (corner - origin).distance)
        .reduce(math.max);
    _drawField(
      canvas,
      AppColors.burgundy,
      maxRadius,
      Curves.easeInOutCubic.transform(_splashInterval(progress, .22, .45)),
    );
    _drawField(
      canvas,
      AppColors.oxblood,
      maxRadius,
      Curves.easeInOutCubic.transform(_splashInterval(progress, .38, .61)),
    );
    _drawField(
      canvas,
      AppColors.charcoal,
      maxRadius,
      Curves.easeInOutCubic.transform(_splashInterval(progress, .54, .78)),
    );
  }

  void _drawField(Canvas canvas, Color color, double maxRadius, double reveal) {
    if (reveal <= 0) return;
    canvas.drawCircle(origin, maxRadius * reveal, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _DotRevealBackgroundPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.origin != origin;
}
