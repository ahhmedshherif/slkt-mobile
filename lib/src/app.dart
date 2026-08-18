import 'dart:async';
import 'dart:math' as math;

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/api_client.dart';
import 'core/session_controller.dart';
import 'core/theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/buyer/buyer_shell.dart';
import 'widgets/common.dart';

bool isTicketsAppLink(Uri link) {
  final isWebTicketsLink =
      link.scheme == 'https' &&
      link.host.toLowerCase() == 'slktegy.com' &&
      (link.path == '/tickets' || link.path.startsWith('/tickets/'));
  final isCustomTicketsLink =
      link.scheme == 'slkt' && link.host.toLowerCase() == 'tickets';
  return isWebTicketsLink || isCustomTicketsLink;
}

class EvntsApp extends StatefulWidget {
  const EvntsApp({super.key, required this.api, required this.session});

  final ApiClient api;
  final SessionController session;

  @override
  State<EvntsApp> createState() => _EvntsAppState();
}

class _EvntsAppState extends State<EvntsApp> {
  static const currentBuild = 4007;
  final navigatorKey = GlobalKey<NavigatorState>();
  Timer? timer;
  final AppLinks appLinks = AppLinks();
  StreamSubscription<Uri>? appLinkSubscription;
  bool minimumSplashDone = false;
  Map<String, dynamic>? mobileUpdate;
  bool updateCheckDone = false;
  bool updateSkipped = false;

  @override
  void initState() {
    super.initState();
    timer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => minimumSplashDone = true);
    });
    appLinkSubscription = appLinks.uriLinkStream.listen(_handleAppLink);
    unawaited(_readInitialAppLink());
    _checkForUpdate();
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
            widget.session.restoring || !minimumSplashDone || !updateCheckDone;
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
                IgnorePointer(
                  child: Transform.translate(
                    offset: Offset(8 + 28 * progress, 0),
                    child: AnimatedScale(
                      scale: .82 + .18 * progress,
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 90),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.black.withValues(
                            alpha: .72 + .2 * progress,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 18,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: progress >= .88
                              ? AppColors.yellow
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
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
      duration: const Duration(milliseconds: 3000),
    )..forward();
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

    return Scaffold(
      backgroundColor: AppColors.black,
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final progress = controller.value;
          final darkScene = Curves.easeInOutCubic.transform(
            const Interval(.56, .74).transform(progress),
          );
          final underline = Curves.easeOutExpo.transform(
            const Interval(.42, .66).transform(progress),
          );
          final tagline = Curves.easeOutCubic.transform(
            const Interval(.68, .82).transform(progress),
          );
          final exit =
              1 -
              Curves.easeInCubic.transform(
                const Interval(.9, 1).transform(progress),
              );

          return AnnotatedRegion(
            value: progress < .66 ? AppSystemUi.dark : AppSystemUi.light,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: AppColors.yellow),
                Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: darkScene,
                    heightFactor: 1,
                    child: const ColoredBox(color: AppColors.black),
                  ),
                ),
                Opacity(
                  opacity: .08 * exit,
                  child: _AmbientBarcode(
                    progress: progress,
                    color: Color.lerp(
                      AppColors.black,
                      AppColors.yellow,
                      darkScene,
                    )!,
                  ),
                ),
                Center(
                  child: Opacity(
                    opacity: exit,
                    child: Transform.scale(
                      scale: .96 + (.04 * exit),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Opacity(
                                opacity: 1 - darkScene,
                                child: _SplashLetters(
                                  progress: progress,
                                  color: AppColors.black,
                                ),
                              ),
                              Opacity(
                                opacity: darkScene,
                                child: _SplashLetters(
                                  progress: progress,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Align(
                            widthFactor: 1,
                            child: Container(
                              width: 236 * underline,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Color.lerp(
                                  AppColors.black,
                                  AppColors.yellow,
                                  darkScene,
                                ),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Opacity(
                            opacity: tagline,
                            child: Transform.translate(
                              offset: Offset(0, 10 * (1 - tagline)),
                              child: Text(
                                'SELECT SMART. ENTER SMOOTH.',
                                style: TextStyle(
                                  color: Color.lerp(
                                    AppColors.black,
                                    Colors.white,
                                    darkScene,
                                  ),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2.4,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SplashLetters extends StatelessWidget {
  const _SplashLetters({required this.progress, required this.color});

  final double progress;
  final Color color;

  static const _letters = ['T', 'K', 'T', 'S', 'A', 'P', 'P'];

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'TKTS APP',
    image: true,
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(_letters.length, (index) {
          final start = .035 + (index * .052);
          final end = start + .2;
          final raw = Interval(start, end).transform(progress);
          final enter = Curves.easeOutBack.transform(raw);
          final isApp = index >= 4;
          final direction = index.isEven ? -1.0 : 1.0;

          return Padding(
            padding: EdgeInsets.only(left: index == 4 ? 16 : 0),
            child: Opacity(
              opacity: raw.clamp(0, 1),
              child: Transform.translate(
                offset: Offset(
                  direction * 9 * (1 - enter),
                  (isApp ? 52 : -64) * (1 - enter),
                ),
                child: Transform.rotate(
                  angle: direction * .09 * (1 - enter),
                  child: Transform.scale(
                    scale: .72 + (.28 * enter),
                    child: Text(
                      _letters[index],
                      key: ValueKey('splash-letter-$index'),
                      style: TextStyle(
                        color: color,
                        fontSize: isApp ? 46 : 58,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    ),
  );
}

class _AmbientBarcode extends StatelessWidget {
  const _AmbientBarcode({
    required this.progress,
    this.color = AppColors.yellow,
  });

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final drift = Curves.easeInOutSine.transform(progress);
    return IgnorePointer(
      child: Opacity(
        opacity: .1,
        child: Transform.rotate(
          angle: -math.pi / 10,
          child: Transform.translate(
            offset: Offset(-60 + (120 * drift), 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(16, (index) {
                final width = index.isEven ? 10.0 : 24.0;
                return Container(
                  width: width,
                  height: MediaQuery.sizeOf(context).height * 1.25,
                  color: index % 3 == 0 ? color.withValues(alpha: .55) : color,
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
