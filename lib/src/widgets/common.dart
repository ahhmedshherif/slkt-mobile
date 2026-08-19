import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';

import '../core/api_client.dart';
import '../core/theme.dart';

class SlktRefresh extends StatefulWidget {
  const SlktRefresh({super.key, required this.onRefresh, required this.child});

  final RefreshCallback onRefresh;
  final Widget child;

  @override
  State<SlktRefresh> createState() => _SlktRefreshState();
}

class _SlktRefreshState extends State<SlktRefresh> {
  RefreshIndicatorStatus? status;

  @override
  Widget build(BuildContext context) {
    final visible = status != null && status != RefreshIndicatorStatus.done;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        RefreshIndicator.noSpinner(
          onRefresh: () async {
            HapticFeedback.selectionClick();
            await widget.onRefresh();
          },
          onStatusChange: (value) => setState(() => status = value),
          child: widget.child,
        ),
        IgnorePointer(
          child: SafeArea(
            bottom: false,
            child: AnimatedSlide(
              duration: reduced
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: const Cubic(0.2, 0, 0, 1),
              offset: visible ? Offset.zero : const Offset(0, -1.6),
              child: AnimatedScale(
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                scale: visible ? 1 : .8,
                child: Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.black,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 18),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: status == RefreshIndicatorStatus.refresh
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.yellow,
                          ),
                        )
                      : const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.yellow,
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.dark = false, this.height = 38});
  final bool dark;
  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'TKTS APP',
    image: true,
    child: ColorFiltered(
      colorFilter: ColorFilter.mode(
        dark ? Colors.white : AppColors.black,
        BlendMode.srcIn,
      ),
      child: Image.asset(
        'assets/brand/tkts-wordmark-transparent.png',
        height: height,
        width: height * 1.48,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    ),
  );
}

class MotionEntrance extends StatefulWidget {
  const MotionEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, .055),
  });

  final Widget child;
  final Duration delay;
  final Offset offset;

  @override
  State<MotionEntrance> createState() => _MotionEntranceState();
}

class _MotionEntranceState extends State<MotionEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<double> curve;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    curve = CurvedAnimation(
      parent: controller,
      curve: const Cubic(0.05, 0.7, 0.1, 1),
    );
    Future<void>.delayed(widget.delay, () {
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
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: widget.offset,
          end: Offset.zero,
        ).animate(curve),
        child: ScaleTransition(
          scale: Tween<double>(begin: .985, end: 1).animate(curve),
          child: widget.child,
        ),
      ),
    );
  }
}

class AnimatedIndexedStack extends StatefulWidget {
  const AnimatedIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<AnimatedIndexedStack> createState() => _AnimatedIndexedStackState();
}

class SlktNavigationBar extends StatelessWidget {
  const SlktNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 280);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .26),
              blurRadius: 34,
              offset: const Offset(0, 15),
            ),
            BoxShadow(
              color: AppColors.yellow.withValues(alpha: .08),
              blurRadius: 22,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Material(
              key: const ValueKey('slkt-glass-navigation'),
              color: const Color(0xD90B0B0D),
              child: Container(
                height: 72,
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: .10),
                      Colors.white.withValues(alpha: .025),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .13),
                  ),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: List.generate(destinations.length, (index) {
                    final destination = destinations[index];
                    final selected = selectedIndex == index;
                    return Expanded(
                      child: Semantics(
                        selected: selected,
                        button: true,
                        label: destination.label,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(23),
                          onTap: () => onDestinationSelected(index),
                          child: AnimatedContainer(
                            duration: duration,
                            curve: const Cubic(.2, 0, 0, 1),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.yellow.withValues(alpha: .14)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(23),
                              border: Border.all(
                                color: selected
                                    ? AppColors.yellow.withValues(alpha: .24)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedSlide(
                                  duration: duration,
                                  curve: const Cubic(.2, 0, 0, 1),
                                  offset: selected
                                      ? const Offset(0, -.06)
                                      : Offset.zero,
                                  child: AnimatedScale(
                                    duration: duration,
                                    curve: const Cubic(.2, 0, 0, 1),
                                    scale: selected ? 1.12 : 1,
                                    child: IconTheme(
                                      data: IconThemeData(
                                        color: selected
                                            ? AppColors.yellow
                                            : Colors.white60,
                                        size: selected ? 24 : 22,
                                        shadows: selected
                                            ? [
                                                Shadow(
                                                  color: AppColors.yellow
                                                      .withValues(alpha: .38),
                                                  blurRadius: 13,
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: selected
                                          ? (destination.selectedIcon ??
                                                destination.icon)
                                          : destination.icon,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                AnimatedDefaultTextStyle(
                                  duration: duration,
                                  curve: const Cubic(.2, 0, 0, 1),
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : Colors.white54,
                                    fontSize: selected ? 10 : 9.5,
                                    fontWeight: selected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    letterSpacing: selected ? .15 : 0,
                                  ),
                                  child: Text(
                                    destination.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                AnimatedContainer(
                                  duration: duration,
                                  curve: const Cubic(.2, 0, 0, 1),
                                  width: selected ? 16 : 0,
                                  height: 2,
                                  margin: const EdgeInsets.only(top: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.yellow,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedIndexedStackState extends State<AnimatedIndexedStack> {
  static const _curve = Cubic(0.05, 0.7, 0.1, 1);

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Stack(
      children: List.generate(widget.children.length, (itemIndex) {
        final selected = itemIndex == widget.index;
        final restingOffset = itemIndex < widget.index
            ? const Offset(-.055, 0)
            : const Offset(.055, 0);
        return Positioned.fill(
          child: IgnorePointer(
            ignoring: !selected,
            child: AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: reduced
                  ? Duration.zero
                  : const Duration(milliseconds: 340),
              curve: Curves.easeOutCubic,
              child: AnimatedSlide(
                offset: selected ? Offset.zero : restingOffset,
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 480),
                curve: _curve,
                child: AnimatedScale(
                  scale: selected ? 1 : .975,
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 480),
                  curve: _curve,
                  child: TickerMode(
                    enabled: selected,
                    child: RepaintBoundary(child: widget.children[itemIndex]),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => MotionEntrance(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: const TextStyle(color: AppColors.muted)),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class AsyncPanel extends StatelessWidget {
  const AsyncPanel({
    super.key,
    required this.future,
    required this.builder,
    this.emptyMessage = 'Nothing here yet.',
    this.animateResult = true,
    this.onRetry,
    this.skeleton,
  });
  final Future<dynamic> future;
  final Widget Function(BuildContext, dynamic) builder;
  final String emptyMessage;
  final bool animateResult;
  final VoidCallback? onRetry;
  final Widget? skeleton;

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return skeleton ?? const SkeletonList();
      }
      if (snapshot.hasError) {
        final error = snapshot.error;
        return EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Couldn\'t load this',
          message: error is ApiException
              ? error.message
              : 'Check your connection and try again.',
          action: onRetry == null
              ? null
              : FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
        );
      }
      final child = builder(context, snapshot.data);
      return animateResult ? MotionEntrance(child: child) : child;
    },
  );
}

class UxStepper extends StatelessWidget {
  const UxStepper({super.key, required this.steps, required this.currentStep});

  final List<String> steps;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label:
          'Step ${currentStep + 1} of ${steps.length}: ${steps[currentStep]}',
      child: Row(
        children: List.generate(steps.length, (index) {
          final active = index <= currentStep;
          return Expanded(
            child: Row(
              children: [
                AnimatedContainer(
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 260),
                  curve: const Cubic(.2, 0, 0, 1),
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? AppColors.black : const Color(0xFFE5DFDA),
                    shape: BoxShape.circle,
                  ),
                  child: index < currentStep
                      ? const Icon(
                          Icons.check_rounded,
                          color: AppColors.yellow,
                          size: 17,
                        )
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: active ? AppColors.yellow : AppColors.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
                if (index < steps.length - 1)
                  Expanded(
                    child: AnimatedContainer(
                      duration: reduced
                          ? Duration.zero
                          : const Duration(milliseconds: 260),
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      color: index < currentStep
                          ? AppColors.black
                          : const Color(0xFFE5DFDA),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class SectionSkeleton extends StatelessWidget {
  const SectionSkeleton({super.key, this.cards = 3, this.cardHeight = 168});

  final int cards;
  final double cardHeight;

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor: const Color(0xFFE7E1DC),
    highlightColor: const Color(0xFFF9F6F3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 148,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 14),
        ...List.generate(
          cards,
          (_) => Container(
            height: cardHeight,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ],
    ),
  );
}

class SlktEventPageRoute<T> extends PageRouteBuilder<T> {
  SlktEventPageRoute({required WidgetBuilder builder, super.settings})
    : super(
        transitionDuration: const Duration(milliseconds: 620),
        reverseTransitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (MediaQuery.disableAnimationsOf(context)) return child;
          final curved = CurvedAnimation(
            parent: animation,
            curve: const Cubic(0.05, 0.7, 0.1, 1),
            reverseCurve: const Cubic(0.3, 0, 1, 1),
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .075),
                end: Offset.zero,
              ).animate(curved),
              child: ScaleTransition(
                scale: Tween<double>(begin: .985, end: 1).animate(curved),
                child: child,
              ),
            ),
          );
        },
      );
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4});
  final int count;

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor: const Color(0xFFE9E3DE),
    highlightColor: const Color(0xFFF9F6F3),
    child: Column(
      children: List.generate(
        count,
        (_) => Container(
          height: 112,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
          ),
        ),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => MotionEntrance(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: Color(0xFFFFE9DF),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.coral, size: 34),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(color: AppColors.muted),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    ),
  );
}

void showError(BuildContext context, Object error) {
  showAppNotice(context, errorMessage(error), error: true);
}

String errorMessage(Object error) =>
    error is ApiException ? error.message : error.toString();

void showAppNotice(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              color: error ? const Color(0xFFFFB4A8) : AppColors.yellow,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.black,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        duration: Duration(seconds: error ? 5 : 3),
      ),
    );
}
