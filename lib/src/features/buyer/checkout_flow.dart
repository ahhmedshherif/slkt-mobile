import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/api_client.dart';
import '../../core/buyer_local_store.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

enum CheckoutPaymentStatus { paid, pending, failed }

class CheckoutCompletion {
  const CheckoutCompletion({
    required this.status,
    required this.orderId,
    required this.orderNumber,
  });

  final CheckoutPaymentStatus status;
  final int orderId;
  final String orderNumber;
}

Future<CheckoutCompletion?> showCheckoutCartSheet({
  required BuildContext context,
  required ApiClient api,
  required Map<String, dynamic> event,
  int? initialTicketTypeId,
}) => showModalBottomSheet<CheckoutCompletion>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  backgroundColor: Colors.transparent,
  builder: (_) => _CheckoutCartSheet(
    api: api,
    event: event,
    initialTicketTypeId: initialTicketTypeId,
  ),
);

class _CheckoutCartSheet extends StatefulWidget {
  const _CheckoutCartSheet({
    required this.api,
    required this.event,
    this.initialTicketTypeId,
  });

  final ApiClient api;
  final Map<String, dynamic> event;
  final int? initialTicketTypeId;

  @override
  State<_CheckoutCartSheet> createState() => _CheckoutCartSheetState();
}

class _CheckoutCartSheetState extends State<_CheckoutCartSheet> {
  final promo = TextEditingController();
  final quantities = <int, int>{};
  Map<String, dynamic>? preview;
  Timer? previewDebounce;
  bool previewBusy = false;
  bool checkoutBusy = false;
  String? error;
  int previewSequence = 0;
  bool restoringCart = true;
  String checkoutAttemptKey = const Uuid().v4();

  List<Map<String, dynamic>> get types =>
      (widget.event['ticket_types'] as List? ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();

  int get maxTickets =>
      ((widget.event['max_tickets_per_order'] as num?)?.toInt() ?? 5).clamp(
        1,
        5,
      );

  int get ticketCount => quantities.values.fold(0, (sum, value) => sum + value);

  double get localTotal => types.fold(0, (sum, type) {
    final id = (type['id'] as num).toInt();
    return sum + (_unitPrice(type) * (quantities[id] ?? 0));
  });

  String get currency => widget.event['currency']?.toString() ?? 'EGP';

  @override
  void initState() {
    super.initState();
    promo.addListener(_persistCart);
    _restoreCart();
  }

  @override
  void dispose() {
    previewDebounce?.cancel();
    promo.removeListener(_persistCart);
    promo.dispose();
    super.dispose();
  }

  Future<void> _restoreCart() async {
    final slug = widget.event['slug']?.toString() ?? '';
    final values = await Future.wait([
      BuyerLocalStore.cart(slug),
      BuyerLocalStore.checkoutAttempt(slug),
    ]);
    final saved = values[0] as Map<String, dynamic>?;
    final savedAttempt = values[1] as String?;
    if (!mounted) return;
    final restored = Map<String, dynamic>.from(
      saved?['quantities'] as Map? ?? const {},
    );
    for (final entry in restored.entries) {
      final id = int.tryParse(entry.key);
      final value = (entry.value as num?)?.toInt() ?? 0;
      if (id != null && value > 0 && types.any((type) => type['id'] == id)) {
        quantities[id] = value;
      }
    }
    promo.text = saved?['promo']?.toString() ?? '';
    if (savedAttempt?.isNotEmpty == true) checkoutAttemptKey = savedAttempt!;
    final selected = widget.initialTicketTypeId;
    if (selected != null) quantities[selected] = quantities[selected] ?? 1;
    setState(() => restoringCart = false);
    if (quantities.isNotEmpty) await _loadPreview();
  }

  void _persistCart() {
    if (restoringCart) return;
    BuyerLocalStore.saveCart(
      widget.event['slug']?.toString() ?? '',
      quantities: payloadQuantities,
      promo: promo.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = (preview?['total'] as num?)?.toDouble() ?? localTotal;
    return FractionallySizedBox(
      heightFactor: .94,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.yellow,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(Icons.shopping_bag_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose your tickets',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          widget.event['name']?.toString() ?? 'TKTS APP event',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close cart',
                    onPressed: checkoutBusy
                        ? null
                        : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
              child: UxStepper(
                steps: const ['Tickets', 'Details', 'Payment', 'Confirmation'],
                currentStep: ticketCount == 0 ? 0 : 1,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                children: [
                  Text(
                    'TICKET TYPES',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      letterSpacing: 1.8,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...types.map(_ticketRow),
                  const SizedBox(height: 8),
                  TextField(
                    controller: promo,
                    textCapitalization: TextCapitalization.characters,
                    enabled: !checkoutBusy,
                    decoration: InputDecoration(
                      labelText: 'Promo code (optional)',
                      prefixIcon: const Icon(Icons.sell_outlined),
                      suffixIcon: TextButton(
                        onPressed: ticketCount == 0 || previewBusy
                            ? null
                            : _loadPreview,
                        child: const Text('Apply'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: const Cubic(0.05, 0.7, 0.1, 1),
                    child: _summary(total),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      key: const ValueKey('checkout-error'),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE6E1),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(error!)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                MediaQuery.paddingOf(context).bottom + 14,
              ),
              decoration: const BoxDecoration(
                color: AppColors.paper,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: FilledButton(
                key: const ValueKey('create-order-and-pay'),
                onPressed: ticketCount == 0 || checkoutBusy ? null : _checkout,
                child: checkoutBusy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text('Create order & pay ${_money(total)} $currency'),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ticketRow(Map<String, dynamic> type) {
    final id = (type['id'] as num).toInt();
    final quantity = quantities[id] ?? 0;
    final available = (type['available'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: quantity > 0 ? const Color(0xFFFFF6C9) : AppColors.paper,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type['name']?.toString() ?? 'Admission',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_money(_unitPrice(type))} $currency • $available available',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _QuantityStepper(
                quantity: quantity,
                canAdd: available > quantity && ticketCount < maxTickets,
                enabled: !checkoutBusy,
                onChanged: (value) => _setQuantity(id, value),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary(double total) {
    if (ticketCount == 0) {
      return const EmptyState(
        key: ValueKey('empty-cart'),
        icon: Icons.add_shopping_cart_rounded,
        title: 'Your cart is empty',
        message:
            'Choose one or more tickets above. You can buy up to 5 per order.',
      );
    }
    final subtotal = (preview?['subtotal'] as num?)?.toDouble() ?? localTotal;
    final tax = (preview?['tax'] as num?)?.toDouble() ?? 0;
    final discount = (preview?['discount'] as num?)?.toDouble() ?? 0;
    return Card(
      key: ValueKey('summary-$ticketCount-${preview?['total']}'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            _SummaryLine(
              label: '$ticketCount ticket${ticketCount == 1 ? '' : 's'}',
              value: '${_money(subtotal)} $currency',
            ),
            _SummaryLine(
              label: tax > 0 ? 'Service fees & VAT' : 'Service fees',
              value: tax > 0 ? '${_money(tax)} $currency' : 'Included',
            ),
            if (discount > 0)
              _SummaryLine(
                label: 'Discount',
                value: '-${_money(discount)} $currency',
                highlighted: true,
              ),
            const Divider(height: 22),
            _SummaryLine(
              label: 'Total',
              value: '${_money(total)} $currency',
              strong: true,
            ),
            if (previewBusy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 3),
            ],
          ],
        ),
      ),
    );
  }

  void _setQuantity(int id, int value) {
    HapticFeedback.selectionClick();
    setState(() {
      error = null;
      if (value <= 0) {
        quantities.remove(id);
      } else {
        quantities[id] = value;
      }
      preview = null;
    });
    _persistCart();
    previewDebounce?.cancel();
    if (ticketCount > 0) {
      previewDebounce = Timer(const Duration(milliseconds: 320), _loadPreview);
    }
  }

  Map<String, int> get payloadQuantities => {
    for (final entry in quantities.entries)
      if (entry.value > 0) entry.key.toString(): entry.value,
  };

  Future<void> _loadPreview() async {
    if (ticketCount == 0) return;
    final sequence = ++previewSequence;
    setState(() {
      previewBusy = true;
      error = null;
    });
    try {
      final response = await widget.api.post(
        '/mobile/buyer/events/${widget.event['slug']}/checkout/preview',
        audience: 'buyer',
        data: {
          'quantities': payloadQuantities,
          if (promo.text.trim().isNotEmpty) 'promo_code': promo.text.trim(),
        },
      );
      if (!mounted || sequence != previewSequence) return;
      setState(
        () => preview = Map<String, dynamic>.from(response['data'] as Map),
      );
    } catch (exception) {
      if (!mounted || sequence != previewSequence) return;
      setState(() => error = _message(exception));
    } finally {
      if (mounted && sequence == previewSequence) {
        setState(() => previewBusy = false);
      }
    }
  }

  Future<void> _checkout() async {
    if (checkoutBusy) return;
    final slug = widget.event['slug']?.toString() ?? '';
    await BuyerLocalStore.saveCheckoutAttempt(slug, checkoutAttemptKey);
    await BuyerLocalStore.saveCart(
      slug,
      quantities: payloadQuantities,
      promo: promo.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      checkoutBusy = true;
      error = null;
    });
    try {
      final response = await _createCheckoutWithSafeRetry();
      final data = Map<String, dynamic>.from(response['data'] as Map);
      final checkoutUrl = Uri.tryParse(data['checkout_url']?.toString() ?? '');
      final orderId = (data['order_id'] as num?)?.toInt();
      final expiresAt = DateTime.tryParse(data['expires_at']?.toString() ?? '');
      final serverTime = DateTime.tryParse(
        data['server_time']?.toString() ?? '',
      );
      if (checkoutUrl == null ||
          !isTrustedPaymobCheckoutUrl(checkoutUrl) ||
          orderId == null ||
          expiresAt == null ||
          serverTime == null) {
        throw const ApiException('TKTS APP could not start secure payment.');
      }
      await BuyerLocalStore.savePendingCheckout({
        'order_id': orderId,
        'order_number': data['order_number']?.toString() ?? 'Order #$orderId',
        'checkout_url': checkoutUrl.toString(),
        'redirect_path':
            data['redirect_path']?.toString() ?? '/checkout/$orderId/success',
        'expires_at': expiresAt.toIso8601String(),
        'server_time': serverTime.toIso8601String(),
        'event_slug': slug,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      });
      await BuyerLocalStore.clearCart(slug);
      if (!mounted) return;
      final result = await showPaymentSheet(
        context: context,
        api: widget.api,
        checkoutUrl: checkoutUrl,
        orderId: orderId,
        orderNumber: data['order_number']?.toString() ?? 'Order #$orderId',
        redirectPath:
            data['redirect_path']?.toString() ?? '/checkout/$orderId/success',
        expiresAt: expiresAt,
        serverTime: serverTime,
      );
      if (!mounted || result == null) return;
      if (result.status == CheckoutPaymentStatus.failed) {
        await BuyerLocalStore.clearPendingCheckout();
        await BuyerLocalStore.clearCheckoutAttempt(slug);
        checkoutAttemptKey = const Uuid().v4();
        setState(
          () => error =
              'Payment was not completed. Your card was not confirmed. You can try again.',
        );
        return;
      }
      if (result.status == CheckoutPaymentStatus.paid) {
        await BuyerLocalStore.clearPendingCheckout();
        await BuyerLocalStore.clearCheckoutAttempt(slug);
      }
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (exception) {
      if (mounted) setState(() => error = _message(exception));
    } finally {
      if (mounted) setState(() => checkoutBusy = false);
    }
  }

  Future<Map<String, dynamic>> _createCheckoutWithSafeRetry() async {
    const attempts = 4;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final response = await widget.api.post(
        '/mobile/buyer/events/${widget.event['slug']}/checkout',
        audience: 'buyer',
        data: {
          'quantities': payloadQuantities,
          if (promo.text.trim().isNotEmpty) 'promo_code': promo.text.trim(),
          'recipient_details': {},
          'idempotency_key': checkoutAttemptKey,
        },
      );
      final data = Map<String, dynamic>.from(
        response['data'] as Map? ?? const {},
      );
      if (data['checkout_url']?.toString().isNotEmpty == true) return response;

      final retryAfter = (data['retry_after_seconds'] as num?)?.toInt() ?? 1;
      if (attempt == attempts - 1) {
        throw const ApiException(
          'Secure payment is still being prepared. Please try again in a moment.',
        );
      }
      await Future<void>.delayed(Duration(seconds: retryAfter.clamp(1, 3)));
    }

    throw const ApiException('TKTS APP could not start secure payment.');
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.canAdd,
    required this.enabled,
    required this.onChanged,
  });

  final int quantity;
  final bool canAdd;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: enabled && quantity > 0
              ? () => onChanged(quantity - 1)
              : null,
          icon: const Icon(Icons.remove_rounded, size: 18),
        ),
        SizedBox(
          width: 22,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: enabled && canAdd ? () => onChanged(quantity + 1) : null,
          icon: const Icon(Icons.add_rounded, size: 18),
        ),
      ],
    ),
  );
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    this.highlighted = false,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool highlighted;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: highlighted ? AppColors.success : AppColors.ink,
            fontSize: strong ? 17 : 14,
            fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

Future<CheckoutCompletion?> showPaymentSheet({
  required BuildContext context,
  required ApiClient api,
  required Uri checkoutUrl,
  required int orderId,
  required String orderNumber,
  required String redirectPath,
  required DateTime expiresAt,
  required DateTime serverTime,
}) => showModalBottomSheet<CheckoutCompletion>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  enableDrag: false,
  isDismissible: false,
  backgroundColor: Colors.transparent,
  builder: (_) => _PaymentWebViewSheet(
    api: api,
    checkoutUrl: checkoutUrl,
    orderId: orderId,
    orderNumber: orderNumber,
    redirectPath: redirectPath,
    expiresAt: expiresAt,
    serverTime: serverTime,
  ),
);

class _PaymentWebViewSheet extends StatefulWidget {
  const _PaymentWebViewSheet({
    required this.api,
    required this.checkoutUrl,
    required this.orderId,
    required this.orderNumber,
    required this.redirectPath,
    required this.expiresAt,
    required this.serverTime,
  });

  final ApiClient api;
  final Uri checkoutUrl;
  final int orderId;
  final String orderNumber;
  final String redirectPath;
  final DateTime expiresAt;
  final DateTime serverTime;

  @override
  State<_PaymentWebViewSheet> createState() => _PaymentWebViewSheetState();
}

class _PaymentWebViewSheetState extends State<_PaymentWebViewSheet> {
  late final WebViewController controller;
  Timer? poller;
  Timer? countdown;
  late DateTime localDeadline;
  Duration remaining = const Duration(minutes: 15);
  int progress = 0;
  bool checking = false;
  bool redirectSeen = false;
  bool pageFailed = false;
  bool expired = false;
  CheckoutPaymentStatus? terminalStatus;
  bool fiveMinuteWarningSent = false;
  bool twoMinuteWarningSent = false;

  @override
  void initState() {
    super.initState();
    _syncDeadline(widget.expiresAt, widget.serverTime);
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => progress = value);
          },
          onPageStarted: (url) {
            if (mounted) setState(() => pageFailed = false);
            _inspectUrl(url);
          },
          onPageFinished: (url) {
            _inspectUrl(url);
            unawaited(_installKeyboardVisibilityHelper());
          },
          onWebResourceError: (_) {
            if (mounted && progress < 20) setState(() => pageFailed = true);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null ||
                !isTrustedPaymentNavigationUrl(uri, widget.redirectPath)) {
              return NavigationDecision.prevent;
            }
            _inspectUrl(request.url);
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(widget.checkoutUrl);
    poller = Timer.periodic(const Duration(seconds: 3), (_) => _checkOrder());
    countdown = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickCountdown(),
    );
  }

  @override
  void dispose() {
    poller?.cancel();
    countdown?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: const Cubic(0.2, 0, 0, 1),
      child: FractionallySizedBox(
        heightFactor: 1,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              children: [
                Container(
                  color: AppColors.black,
                  padding: const EdgeInsets.fromLTRB(14, 4, 8, 10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.lock_rounded,
                            color: AppColors.yellow,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Secure payment  ·  ${widget.orderNumber}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close payment',
                            onPressed: _requestClose,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      AnimatedSize(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        child: remaining.inSeconds <= 300
                            ? Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.warning_amber_rounded,
                                      color: Color(0xFFFFA07A),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        remaining.inSeconds <= 120
                                            ? 'Only 2 minutes left. Finish payment now or the tickets return to sale.'
                                            : 'Less than 5 minutes left. Your tickets are not held after the timer ends.',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      Row(
                        children: [
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                TweenAnimationBuilder<double>(
                                  tween: Tween<double>(
                                    begin: 0,
                                    end: _progressValue,
                                  ),
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 240),
                                  builder: (context, value, child) =>
                                      CircularProgressIndicator(
                                        value: value,
                                        strokeWidth: 3.5,
                                        strokeCap: StrokeCap.round,
                                        backgroundColor: Colors.white12,
                                        color: remaining.inSeconds <= 120
                                            ? const Color(0xFFFF8A65)
                                            : AppColors.yellow,
                                      ),
                                ),
                                const Icon(
                                  Icons.schedule_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'RESERVATION HELD',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.8,
                                  ),
                                ),
                                AnimatedSwitcher(
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 180),
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                        opacity: animation,
                                        child: SlideTransition(
                                          position: Tween(
                                            begin: const Offset(0, .12),
                                            end: Offset.zero,
                                          ).animate(animation),
                                          child: child,
                                        ),
                                      ),
                                  child: Text(
                                    _formattedRemaining,
                                    key: ValueKey(remaining.inSeconds),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 27,
                                      height: 1.05,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 3,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                                const Text(
                                  'Complete payment before time runs out',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (redirectSeen || checking) ...[
                            const SizedBox(width: 8),
                            Container(
                              key: const ValueKey('payment-confirming-header'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.yellow.withValues(alpha: .14),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppColors.yellow.withValues(
                                    alpha: .32,
                                  ),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox.square(
                                    dimension: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.yellow,
                                    ),
                                  ),
                                  SizedBox(width: 7),
                                  Text(
                                    'Confirming\npayment',
                                    style: TextStyle(
                                      color: Colors.white,
                                      height: 1.05,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const ColoredBox(
                  color: AppColors.paper,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(22, 10, 22, 10),
                    child: UxStepper(
                      steps: ['Tickets', 'Details', 'Payment', 'Confirmation'],
                      currentStep: 2,
                    ),
                  ),
                ),
                if (progress < 100)
                  LinearProgressIndicator(value: progress / 100, minHeight: 3),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: WebViewWidget(controller: controller),
                      ),
                      if (pageFailed)
                        Positioned.fill(
                          child: ColoredBox(
                            color: Colors.white,
                            child: EmptyState(
                              icon: Icons.wifi_off_rounded,
                              title: 'Payment page did not load',
                              message:
                                  'Check your connection, then reload the secure page.',
                              action: FilledButton.icon(
                                onPressed: () {
                                  setState(() => pageFailed = false);
                                  controller.reload();
                                },
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Reload payment'),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: const Cubic(0.05, 0.7, 0.1, 1),
                  child: _statusPanel(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _installKeyboardVisibilityHelper() async {
    try {
      await controller.runJavaScript('''
        (() => {
          if (window.__tktsKeyboardHelperInstalled) return;
          window.__tktsKeyboardHelperInstalled = true;
          document.addEventListener('focusin', (event) => {
            const target = event.target;
            if (!target || !['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)) return;
            window.setTimeout(() => {
              target.scrollIntoView({behavior: 'smooth', block: 'center', inline: 'nearest'});
            }, 260);
          }, true);
        })();
      ''');
    } catch (_) {
      // Payment remains usable if the provider blocks helper injection.
    }
  }

  Widget _statusPanel() {
    final status = terminalStatus;
    if (status == CheckoutPaymentStatus.paid) {
      return _PaymentNotice(
        key: const ValueKey('payment-paid'),
        color: const Color(0xFFE1F7EE),
        icon: Icons.verified_rounded,
        iconColor: AppColors.success,
        title: 'Payment confirmed',
        message: 'Your tickets are ready in the wallet.',
        action: FilledButton(
          onPressed: _finishPaid,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          child: const Text('View my tickets'),
        ),
      );
    }
    if (status == CheckoutPaymentStatus.failed) {
      return _PaymentNotice(
        key: const ValueKey('payment-failed'),
        color: const Color(0xFFFFE6E1),
        icon: Icons.cancel_rounded,
        iconColor: Colors.red,
        title: expired ? 'Reservation expired' : 'Payment not completed',
        message: expired
            ? 'The 15-minute hold was released so the tickets can be booked again.'
            : 'No confirmed payment was found for this order.',
        action: TextButton(
          onPressed: () => Navigator.pop(
            context,
            CheckoutCompletion(
              status: CheckoutPaymentStatus.failed,
              orderId: widget.orderId,
              orderNumber: widget.orderNumber,
            ),
          ),
          child: const Text('Return to cart'),
        ),
      );
    }
    return const SizedBox.shrink(key: ValueKey('payment-active'));
  }

  void _inspectUrl(String value) {
    if (!isCheckoutReturnUrl(value, widget.redirectPath)) return;
    if (mounted) setState(() => redirectSeen = true);
    unawaited(_checkOrder());
  }

  Future<void> _checkOrder() async {
    if (checking || terminalStatus != null || !mounted) return;
    setState(() => checking = true);
    try {
      final response = await widget.api.get(
        '/mobile/buyer/orders/${widget.orderId}',
        audience: 'buyer',
      );
      final status = response['data']?['status']?.toString().toLowerCase();
      final expiresAt = DateTime.tryParse(
        response['data']?['checkout_expires_at']?.toString() ?? '',
      );
      final serverTime = DateTime.tryParse(
        response['data']?['server_time']?.toString() ?? '',
      );
      if (expiresAt != null && serverTime != null) {
        _syncDeadline(expiresAt, serverTime);
      }
      if (!mounted) return;
      if (status == 'paid') {
        poller?.cancel();
        countdown?.cancel();
        unawaited(BuyerLocalStore.clearPendingCheckout());
        setState(() => terminalStatus = CheckoutPaymentStatus.paid);
      } else if (['failed', 'cancelled', 'refunded'].contains(status)) {
        poller?.cancel();
        countdown?.cancel();
        unawaited(BuyerLocalStore.clearPendingCheckout());
        setState(() => terminalStatus = CheckoutPaymentStatus.failed);
      } else if (['expired', 'payment_review'].contains(status)) {
        poller?.cancel();
        countdown?.cancel();
        if (status == 'expired') {
          unawaited(BuyerLocalStore.clearPendingCheckout());
        }
        setState(() {
          expired = status == 'expired';
          terminalStatus = CheckoutPaymentStatus.failed;
        });
      }
    } catch (_) {
      // A temporary polling error must not interrupt an active payment page.
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> _finishPaid() async {
    await BuyerLocalStore.clearPendingCheckout();
    if (!mounted) return;
    Navigator.pop(
      context,
      CheckoutCompletion(
        status: CheckoutPaymentStatus.paid,
        orderId: widget.orderId,
        orderNumber: widget.orderNumber,
      ),
    );
  }

  double get _progressValue =>
      (remaining.inMilliseconds / const Duration(minutes: 15).inMilliseconds)
          .clamp(0.0, 1.0);

  String get _formattedRemaining {
    final seconds = remaining.inSeconds.clamp(0, 15 * 60);
    final minutesPart = seconds ~/ 60;
    final secondsPart = seconds % 60;
    return '${minutesPart.toString().padLeft(2, '0')}:${secondsPart.toString().padLeft(2, '0')}';
  }

  void _syncDeadline(DateTime expiresAt, DateTime serverTime) {
    final serverRemaining = expiresAt.toUtc().difference(serverTime.toUtc());
    localDeadline = DateTime.now().add(
      serverRemaining.isNegative ? Duration.zero : serverRemaining,
    );
    remaining = localDeadline.difference(DateTime.now());
    if (remaining.isNegative) remaining = Duration.zero;
  }

  void _tickCountdown() {
    if (!mounted || terminalStatus != null) return;
    final next = localDeadline.difference(DateTime.now());
    setState(() => remaining = next.isNegative ? Duration.zero : next);
    if (remaining.inSeconds <= 300 && !fiveMinuteWarningSent) {
      fiveMinuteWarningSent = true;
      HapticFeedback.mediumImpact();
    }
    if (remaining.inSeconds <= 120 && !twoMinuteWarningSent) {
      twoMinuteWarningSent = true;
      HapticFeedback.heavyImpact();
    }
    if (remaining == Duration.zero) {
      countdown?.cancel();
      unawaited(_checkOrder());
    }
  }

  Future<void> _requestClose() async {
    await _checkOrder();
    if (!mounted) return;
    if (terminalStatus == CheckoutPaymentStatus.paid) return;
    if (terminalStatus == CheckoutPaymentStatus.failed) {
      Navigator.pop(
        context,
        CheckoutCompletion(
          status: CheckoutPaymentStatus.failed,
          orderId: widget.orderId,
          orderNumber: widget.orderNumber,
        ),
      );
      return;
    }
    final close = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave secure payment?'),
        content: const Text(
          'If you already paid, confirmation may still arrive. The order will stay visible in Orders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep paying'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leave payment'),
          ),
        ],
      ),
    );
    if (close == true && mounted) {
      Navigator.pop(
        context,
        CheckoutCompletion(
          status: CheckoutPaymentStatus.pending,
          orderId: widget.orderId,
          orderNumber: widget.orderNumber,
        ),
      );
    }
  }
}

class _PaymentNotice extends StatelessWidget {
  const _PaymentNotice({
    super.key,
    required this.color,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    this.action,
  });

  final Color color;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    color: color,
    padding: EdgeInsets.fromLTRB(
      18,
      12,
      18,
      MediaQuery.paddingOf(context).bottom + 12,
    ),
    child: Row(
      children: [
        Icon(icon, color: iconColor, size: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                message,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        ?action,
      ],
    ),
  );
}

double _unitPrice(Map<String, dynamic> type) =>
    (type['early_bird_price'] as num?)?.toDouble() ??
    (type['price'] as num?)?.toDouble() ??
    0;

String _money(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);

String _message(Object exception) => exception is ApiException
    ? exception.message
    : 'Something went wrong. Please try again.';

bool isTrustedPaymobCheckoutUrl(Uri uri) {
  final trustedHost = isTrustedPaymobHost(uri.host);
  return uri.scheme == 'https' &&
      trustedHost &&
      uri.path.toLowerCase().contains('unifiedcheckout');
}

bool isTrustedPaymobHost(String value) {
  final host = value.toLowerCase();
  return host == 'paymob.com' ||
      host.endsWith('.paymob.com') ||
      host == 'paymobsolutions.com' ||
      host.endsWith('.paymobsolutions.com');
}

bool isTrustedPaymentNavigationUrl(Uri uri, String redirectPath) {
  if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) return false;
  if (isTrustedPaymobHost(uri.host)) return true;

  final host = uri.host.toLowerCase();
  final trustedApiHost = host == 'tktsapp.com' || host.endsWith('.tktsapp.com');
  if (!trustedApiHost) return false;

  return uri.path == redirectPath || uri.path.startsWith('/api/');
}

bool isCheckoutReturnUrl(String value, String redirectPath) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https') return false;
  final trustedHost =
      uri.host == 'tktsapp.com' || uri.host.endsWith('.tktsapp.com');
  return trustedHost && uri.path == redirectPath;
}
