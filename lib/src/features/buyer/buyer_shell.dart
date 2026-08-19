import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:intl/intl.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/buyer_local_store.dart';
import '../../core/session_controller.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../auth/auth_screen.dart';
import 'checkout_flow.dart';

class BuyerShell extends StatefulWidget {
  const BuyerShell({super.key, required this.api, required this.session});
  final ApiClient api;
  final SessionController session;

  @override
  State<BuyerShell> createState() => _BuyerShellState();
}

class _BuyerShellState extends State<BuyerShell> {
  int index = 0;
  final commerceRefresh = ValueNotifier<int>(0);
  final unreadNotifications = ValueNotifier<int>(0);
  final ticketsKey = GlobalKey<_TicketsScreenState>();
  late final pages = [
    HomeScreen(
      api: widget.api,
      session: widget.session,
      explore: () => setState(() => index = 1),
      purchaseCompleted: _refreshCommerce,
      unreadNotifications: unreadNotifications,
      openNotifications: _openNotifications,
      openTickets: _openTickets,
      openOrders: () => setState(() => index = 3),
    ),
    ExploreScreen(
      api: widget.api,
      purchaseCompleted: _refreshCommerce,
      openTickets: _openTickets,
    ),
    TicketsScreen(
      key: ticketsKey,
      api: widget.api,
      refreshSignal: commerceRefresh,
    ),
    OrdersScreen(
      api: widget.api,
      refreshSignal: commerceRefresh,
      openTickets: _openTickets,
    ),
    ProfileScreen(api: widget.api, session: widget.session),
  ];

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_handleSessionNavigation);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _handleSessionNavigation(),
    );
    _refreshNotifications();
  }

  void _handleSessionNavigation() {
    if (!mounted) return;
    final destination = widget.session.consumeBuyerDestination();
    if (destination == null) return;
    unawaited(_navigateToDestination(destination));
  }

  Future<void> _navigateToDestination(String destination) async {
    if (!mounted) return;
    if (destination.startsWith('event:')) {
      final slug = destination.substring(6);
      try {
        final response = await widget.api.get('/mobile/events/$slug');
        if (!mounted) return;
        _openEvent(
          context,
          widget.api,
          Map<String, dynamic>.from(response['data'] as Map),
          _refreshCommerce,
          _openTickets,
        );
      } catch (error) {
        if (mounted) showError(context, error);
      }
      return;
    }
    if (destination.startsWith('order:')) {
      setState(() => index = 3);
      try {
        final response = await widget.api.get(
          '/mobile/buyer/orders/${destination.substring(6)}',
          audience: 'buyer',
        );
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(
              api: widget.api,
              order: Map<String, dynamic>.from(response['data'] as Map),
              openTickets: _openTickets,
            ),
          ),
        );
      } catch (error) {
        if (mounted) showError(context, error);
      }
      return;
    }
    setState(() => index = destination == 'orders' ? 3 : 2);
    _refreshCommerce();
    if (destination.startsWith('ticket:')) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ticketsKey.currentState?.openTicket(destination.substring(7)),
      );
    } else if (destination == 'transfers') {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ticketsKey.currentState?.showTab(1),
      );
    }
  }

  void _refreshCommerce() {
    commerceRefresh.value++;
    _refreshNotifications();
  }

  void _openTickets() {
    if (!mounted) return;
    setState(() => index = 2);
    _refreshCommerce();
  }

  Future<void> _refreshNotifications() async {
    try {
      final response = await widget.api.get(
        '/mobile/buyer/notifications',
        audience: 'buyer',
        query: {'per_page': 1},
      );
      if (mounted) {
        unreadNotifications.value =
            (response['unread_count'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {
      // Notification badge failure must never block the buyer shell.
    }
  }

  Future<void> _openNotifications() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NotificationsSheet(api: widget.api),
    );
    await _refreshNotifications();
    if (!mounted || action == null) return;
    try {
      final payload = Map<String, dynamic>.from(jsonDecode(action) as Map);
      final meta = Map<String, dynamic>.from(
        payload['meta'] as Map? ?? const {},
      );
      final destination = meta['order_id'] != null
          ? 'order:${meta['order_id']}'
          : meta['ticket_id'] != null
          ? 'ticket:${meta['ticket_id']}'
          : meta['event_slug'] != null
          ? 'event:${meta['event_slug']}'
          : payload['action']?.toString() ?? 'tickets';
      await _navigateToDestination(destination);
    } catch (_) {
      await _navigateToDestination(action);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_handleSessionNavigation);
    commerceRefresh.dispose();
    unreadNotifications.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion(
    value: AppSystemUi.dark,
    child: Scaffold(
      extendBody: true,
      body: AnimatedIndexedStack(index: index, children: pages),
      bottomNavigationBar: SlktNavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          HapticFeedback.selectionClick();
          if (value == 2 || value == 3) _refreshCommerce();
          setState(() => index = value);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_activity_outlined),
            selectedIcon: Icon(Icons.local_activity_rounded),
            label: 'Tickets',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            label: 'Profile',
          ),
        ],
      ),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.session,
    required this.explore,
    required this.purchaseCompleted,
    required this.unreadNotifications,
    required this.openNotifications,
    required this.openTickets,
    required this.openOrders,
  });
  final ApiClient api;
  final SessionController session;
  final VoidCallback explore;
  final VoidCallback purchaseCompleted;
  final ValueListenable<int> unreadNotifications;
  final VoidCallback openNotifications;
  final VoidCallback openTickets;
  final VoidCallback openOrders;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<Map<String, dynamic>> future = _load();

  Future<Map<String, dynamic>> _load() async {
    final recent = await BuyerLocalStore.recentEvents();
    final recommendationQuery = <String, dynamic>{
      'per_page': 12,
      'recommended': true,
    };
    if (recent.isNotEmpty) {
      final categoryId = recent.first['category']?['id'];
      final city = recent.first['venue']?['city']?.toString();
      if (categoryId != null) {
        recommendationQuery['category_id'] = categoryId;
      } else if (city?.isNotEmpty == true) {
        recommendationQuery['city'] = city;
      }
    }
    final responses = await Future.wait([
      widget.api.get('/mobile/events', query: {'per_page': 16}),
      widget.api.get('/mobile/events', query: recommendationQuery),
      widget.api.get(
        '/mobile/events',
        query: {'per_page': 8, 'period': 'past'},
      ),
      widget.api.get('/mobile/events', query: {'per_page': 10, 'hot': true}),
    ]);
    Map<String, dynamic> tickets = const {};
    Map<String, dynamic> orders = const {};
    try {
      final buyerData = await Future.wait([
        widget.api.get('/buyer/tickets', audience: 'buyer'),
        widget.api.get(
          '/mobile/buyer/orders',
          audience: 'buyer',
          query: {'per_page': 10},
        ),
      ]);
      tickets = buyerData[0];
      orders = buyerData[1];
    } catch (_) {}
    return {
      'upcoming': responses[0]['data'] ?? [],
      'recommended': responses[1]['data'] ?? [],
      'past': responses[2]['data'] ?? [],
      'trending': responses[3]['data'] ?? [],
      'tickets': tickets['tickets'] ?? [],
      'orders': orders['data'] ?? [],
      'recent': recent,
    };
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SlktRefresh(
      onRefresh: () async {
        setState(() {
          future = _load();
        });
        await future;
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
        children: [
          Row(
            children: [
              const BrandMark(),
              const Spacer(),
              ValueListenableBuilder<int>(
                valueListenable: widget.unreadNotifications,
                builder: (context, count, _) => Badge(
                  isLabelVisible: count > 0,
                  label: Text(count > 99 ? '99+' : '$count'),
                  child: IconButton.filledTonal(
                    tooltip: 'Notifications',
                    onPressed: widget.openNotifications,
                    icon: Icon(
                      count > 0
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_none_rounded,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'Hello, ${_firstName(widget.session.user['name'])}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Your next great night starts here.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          AsyncPanel(
            future: future,
            skeleton: const SectionSkeleton(cards: 3, cardHeight: 190),
            onRetry: () => setState(() {
              future = _load();
            }),
            builder: (context, raw) {
              final data = Map<String, dynamic>.from(raw as Map);
              final upcoming = List<Map<String, dynamic>>.from(
                (data['upcoming'] as List).map(
                  (e) => Map<String, dynamic>.from(e as Map),
                ),
              );
              final recommended = List<Map<String, dynamic>>.from(
                (data['recommended'] as List).map(
                  (e) => Map<String, dynamic>.from(e as Map),
                ),
              );
              final past = List<Map<String, dynamic>>.from(
                (data['past'] as List).map(
                  (e) => Map<String, dynamic>.from(e as Map),
                ),
              );
              final tickets = List<Map<String, dynamic>>.from(
                (data['tickets'] as List).map(
                  (e) => Map<String, dynamic>.from(e as Map),
                ),
              );
              final trending = _eventList(data['trending']);
              final recent = _eventList(data['recent']);
              final orders = _eventList(data['orders']);
              final pending = orders
                  .where((order) => order['can_resume_payment'] == true)
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _QuickSummary(events: upcoming, tickets: tickets),
                  if (pending.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _PendingCheckoutCard(
                      order: pending.first,
                      onContinue: widget.openOrders,
                    ),
                  ],
                  const SizedBox(height: 28),
                  if (upcoming.isEmpty)
                    EmptyState(
                      icon: Icons.event_busy_rounded,
                      title: 'Events are on the way',
                      message: 'Approved upcoming events will appear here.',
                      action: FilledButton.tonalIcon(
                        onPressed: widget.explore,
                        icon: const Icon(Icons.explore_rounded),
                        label: const Text('Explore events'),
                      ),
                    )
                  else ...[
                    _EventRail(
                      title: 'Upcoming events',
                      subtitle: 'Your next night out',
                      events: upcoming.take(8).toList(),
                      onViewAll: widget.explore,
                      onOpen: _open,
                    ),
                    if (_nearby(upcoming).isNotEmpty) ...[
                      const SizedBox(height: 30),
                      _EventRail(
                        title: 'Near you',
                        subtitle:
                            'Around ${_nearby(upcoming).first['venue']?['city'] ?? 'your city'}',
                        events: _nearby(upcoming).take(6).toList(),
                        onViewAll: widget.explore,
                        onOpen: _open,
                      ),
                    ],
                    if (recommended.isNotEmpty) ...[
                      const SizedBox(height: 30),
                      _EventRail(
                        title: 'Recommended',
                        subtitle: 'Popular picks for you',
                        events: recommended.take(8).toList(),
                        onViewAll: widget.explore,
                        onOpen: _open,
                      ),
                    ],
                    if (trending.isNotEmpty) ...[
                      const SizedBox(height: 30),
                      _EventRail(
                        title: 'Trending this week',
                        subtitle: 'The events everyone is watching',
                        events: trending.take(8).toList(),
                        onViewAll: widget.explore,
                        onOpen: _open,
                      ),
                    ],
                    if (recent.isNotEmpty) ...[
                      const SizedBox(height: 30),
                      _EventRail(
                        title: 'Recently viewed',
                        subtitle: 'Pick up where you left off',
                        events: recent.take(8).toList(),
                        onViewAll: widget.explore,
                        onOpen: _open,
                      ),
                    ],
                    if (past.isNotEmpty) ...[
                      const SizedBox(height: 30),
                      _EventRail(
                        title: 'Past events',
                        subtitle: 'Highlights from before',
                        events: past.take(6).toList(),
                        onViewAll: widget.explore,
                        onOpen: _open,
                      ),
                    ],
                  ],
                ],
              );
            },
          ),
        ],
      ),
    ),
  );

  List<Map<String, dynamic>> _eventList(Object? raw) => List.from(
    raw as List? ?? const [],
  ).map((value) => Map<String, dynamic>.from(value as Map)).toList();

  List<Map<String, dynamic>> _nearby(List<Map<String, dynamic>> events) {
    final cities = events
        .map((event) => event['venue']?['city']?.toString().trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList();
    final city = cities.isEmpty ? null : cities.first;
    if (city == null) return const [];
    return events
        .where(
          (event) =>
              event['venue']?['city']?.toString().toLowerCase() ==
              city.toLowerCase(),
        )
        .toList();
  }

  void _open(Map<String, dynamic> event) => _openEvent(
    context,
    widget.api,
    event,
    widget.purchaseCompleted,
    widget.openTickets,
  );
}

class _QuickSummary extends StatelessWidget {
  const _QuickSummary({required this.events, required this.tickets});
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> tickets;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(30),
      gradient: const LinearGradient(
        colors: [AppColors.navy, Color(0xFF202A41)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'YOUR TKTS APP',
          style: TextStyle(
            color: Colors.white60,
            fontSize: 11,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Everything you need,\nready at the door.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 23,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            SummaryPill(value: tickets.length.toString(), label: 'Tickets'),
            const SizedBox(width: 10),
            SummaryPill(value: events.length.toString(), label: 'Upcoming'),
          ],
        ),
      ],
    ),
  );
}

class _PendingCheckoutCard extends StatelessWidget {
  const _PendingCheckoutCard({required this.order, required this.onContinue});

  final Map<String, dynamic> order;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Card(
    color: AppColors.yellow,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.black,
            foregroundColor: AppColors.yellow,
            child: Icon(Icons.shopping_bag_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Continue checkout',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  order['event']?['name']?.toString() ??
                      order['order_number']?.toString() ??
                      'Pending order',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              onContinue();
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
}

class SummaryPill extends StatelessWidget {
  const SummaryPill({super.key, required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _EventRail extends StatelessWidget {
  const _EventRail({
    required this.title,
    required this.subtitle,
    required this.events,
    required this.onOpen,
    required this.onViewAll,
  });

  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> events;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionTitle(title: title, action: 'View all', onTap: onViewAll),
      Text(subtitle, style: const TextStyle(color: AppColors.muted)),
      const SizedBox(height: 14),
      SizedBox(
        height: 272,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: events.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final event = <String, dynamic>{
              ...events[index],
              '_hero_tag':
                  'event-${title.toLowerCase().replaceAll(' ', '-')}-${events[index]['slug'] ?? events[index]['id']}',
            };
            return EventPosterCard(event: event, onTap: () => onOpen(event));
          },
        ),
      ),
    ],
  );
}

class EventPosterCard extends StatefulWidget {
  const EventPosterCard({super.key, required this.event, required this.onTap});

  final Map<String, dynamic> event;
  final VoidCallback onTap;

  @override
  State<EventPosterCard> createState() => _EventPosterCardState();
}

class _EventPosterCardState extends State<EventPosterCard> {
  bool favorite = false;

  Map<String, dynamic> get event => widget.event;

  @override
  void initState() {
    super.initState();
    _loadFavorite();
  }

  Future<void> _loadFavorite() async {
    final values = await BuyerLocalStore.favorites();
    if (mounted) setState(() => favorite = values.contains(event['slug']));
  }

  Future<void> _toggleFavorite() async {
    HapticFeedback.selectionClick();
    final selected = await BuyerLocalStore.toggleFavorite(
      event['slug']?.toString() ?? '',
    );
    if (mounted) setState(() => favorite = selected);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 208,
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: _eventHeroTag(event),
                    createRectTween: (begin, end) =>
                        MaterialRectArcTween(begin: begin, end: end),
                    child: EventImage(url: event['image_url']?.toString()),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x80000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    bottom: 10,
                    child: StatusChip(
                      label: event['has_ended'] == true
                          ? 'ENDED'
                          : _eventNextSession(event),
                      color: event['has_ended'] == true
                          ? Colors.white
                          : AppColors.yellow,
                    ),
                  ),
                  if (_eventAvailabilityLabel(event) case final label?)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: StatusChip(
                        label: label,
                        color: label == 'SOLD OUT'
                            ? Colors.white
                            : AppColors.yellow,
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filled(
                      tooltip: favorite
                          ? 'Remove from favorites'
                          : 'Add to favorites',
                      onPressed: _toggleFavorite,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xCFFFFFFF),
                        foregroundColor: AppColors.black,
                      ),
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          favorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          key: ValueKey(favorite),
                          color: favorite ? AppColors.coralDark : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event['name']?.toString() ?? 'Event',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    event['venue']?['name']?.toString() ?? 'Venue TBA',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _eventPriceLabel(event),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.coralDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.api,
    required this.purchaseCompleted,
    required this.openTickets,
  });
  final ApiClient api;
  final VoidCallback purchaseCompleted;
  final VoidCallback openTickets;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final search = TextEditingController();
  String query = '';
  int? categoryId;
  int? venueId;
  int? organizerId;
  DateTimeRange? dateRange;
  double? minPrice;
  double? maxPrice;
  late Future<Map<String, dynamic>> categories = widget.api.get(
    '/mobile/categories',
  );
  late Future<List<Map<String, dynamic>>> filterOptions = _loadFilterOptions();

  Future<List<Map<String, dynamic>>> _loadFilterOptions() async {
    final responses = await Future.wait([
      widget.api.get('/mobile/venues'),
      widget.api.get('/mobile/organizers'),
    ]);
    return [
      ...((responses[0]['data'] as List? ?? const []).map(
        (raw) => {'kind': 'venue', ...Map<String, dynamic>.from(raw as Map)},
      )),
      ...((responses[1]['data'] as List? ?? const []).map(
        (raw) => {
          'kind': 'organizer',
          ...Map<String, dynamic>.from(raw as Map),
        },
      )),
    ];
  }

  int get activeFilterCount => [
    venueId,
    organizerId,
    dateRange,
    minPrice,
    maxPrice,
  ].where((value) => value != null).length;

  Future<Map<String, dynamic>> _events() => widget.api.get(
    '/mobile/events',
    query: {
      if (query.isNotEmpty) 'search': query,
      if (categoryId != null) 'category_id': categoryId,
      if (venueId != null) 'venue_id': venueId,
      if (organizerId != null) 'organizer_id': organizerId,
      if (dateRange != null)
        'date_from': DateFormat('yyyy-MM-dd').format(dateRange!.start),
      if (dateRange != null)
        'date_to': DateFormat('yyyy-MM-dd').format(dateRange!.end),
      if (minPrice != null) 'min_price': minPrice,
      if (maxPrice != null) 'max_price': maxPrice,
      'per_page': 30,
    },
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
      children: [
        const PageHeading(
          'Explore events',
          subtitle: 'Find your next unforgettable experience.',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: search,
          textInputAction: TextInputAction.search,
          onSubmitted: (value) => setState(() => query = value.trim()),
          decoration: InputDecoration(
            hintText: 'Search by event, venue or organizer',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              onPressed: () => setState(() {
                search.clear();
                query = '';
              }),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openFilters,
                icon: const Icon(Icons.tune_rounded),
                label: Text(
                  activeFilterCount == 0
                      ? 'Filters'
                      : 'Filters ($activeFilterCount)',
                ),
              ),
            ),
            if (activeFilterCount > 0) ...[
              const SizedBox(width: 10),
              TextButton(onPressed: _clearFilters, child: const Text('Clear')),
            ],
          ],
        ),
        const SizedBox(height: 14),
        FutureBuilder<Map<String, dynamic>>(
          future: categories,
          builder: (context, snapshot) {
            final items = (snapshot.data?['data'] as List? ?? const []);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: categoryId == null,
                    onSelected: (_) => setState(() => categoryId = null),
                  ),
                  const SizedBox(width: 8),
                  ...items.map((raw) {
                    final item = Map<String, dynamic>.from(raw as Map);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(item['name'].toString()),
                        selected: categoryId == (item['id'] as num?)?.toInt(),
                        onSelected: (_) => setState(
                          () => categoryId = (item['id'] as num).toInt(),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 22),
        AsyncPanel(
          key: ValueKey(
            '$query-$categoryId-$venueId-$organizerId-$dateRange-$minPrice-$maxPrice',
          ),
          future: _events(),
          onRetry: () => setState(() {}),
          builder: (context, response) {
            final events = response['data'] as List? ?? const [];
            if (events.isEmpty) {
              return const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No matching events',
                message: 'Try another search or clear a filter.',
              );
            }
            return Column(
              children: events.map((raw) {
                final event = Map<String, dynamic>.from(raw as Map);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: EventCard(
                    event: event,
                    onTap: () => _openEvent(
                      context,
                      widget.api,
                      event,
                      widget.purchaseCompleted,
                      widget.openTickets,
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    ),
  );

  void _clearFilters() => setState(() {
    venueId = null;
    organizerId = null;
    dateRange = null;
    minPrice = null;
    maxPrice = null;
  });

  Future<void> _openFilters() async {
    try {
      final options = await filterOptions;
      if (!mounted) return;
      final result = await showModalBottomSheet<_ExploreFilterResult>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) => _ExploreFiltersSheet(
          options: options,
          venueId: venueId,
          organizerId: organizerId,
          dateRange: dateRange,
          minPrice: minPrice,
          maxPrice: maxPrice,
        ),
      );
      if (result == null || !mounted) return;
      setState(() {
        venueId = result.venueId;
        organizerId = result.organizerId;
        dateRange = result.dateRange;
        minPrice = result.minPrice;
        maxPrice = result.maxPrice;
      });
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }
}

class _ExploreFilterResult {
  const _ExploreFilterResult({
    this.venueId,
    this.organizerId,
    this.dateRange,
    this.minPrice,
    this.maxPrice,
  });

  final int? venueId;
  final int? organizerId;
  final DateTimeRange? dateRange;
  final double? minPrice;
  final double? maxPrice;
}

class _ExploreFiltersSheet extends StatefulWidget {
  const _ExploreFiltersSheet({
    required this.options,
    this.venueId,
    this.organizerId,
    this.dateRange,
    this.minPrice,
    this.maxPrice,
  });

  final List<Map<String, dynamic>> options;
  final int? venueId;
  final int? organizerId;
  final DateTimeRange? dateRange;
  final double? minPrice;
  final double? maxPrice;

  @override
  State<_ExploreFiltersSheet> createState() => _ExploreFiltersSheetState();
}

class _ExploreFiltersSheetState extends State<_ExploreFiltersSheet> {
  late int? venueId = widget.venueId;
  late int? organizerId = widget.organizerId;
  late DateTimeRange? dateRange = widget.dateRange;
  late final minPrice = TextEditingController(
    text: widget.minPrice?.toStringAsFixed(0) ?? '',
  );
  late final maxPrice = TextEditingController(
    text: widget.maxPrice?.toStringAsFixed(0) ?? '',
  );

  List<Map<String, dynamic>> get venues =>
      widget.options.where((item) => item['kind'] == 'venue').toList();
  List<Map<String, dynamic>> get organizers =>
      widget.options.where((item) => item['kind'] == 'organizer').toList();

  @override
  void dispose() {
    minPrice.dispose();
    maxPrice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      4,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filter events',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          const Text(
            'Narrow results by date, venue, organizer and price.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<int?>(
            initialValue: venueId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Venue'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Any venue')),
              ...venues.map(
                (venue) => DropdownMenuItem(
                  value: (venue['id'] as num).toInt(),
                  child: Text(
                    venue['name']?.toString() ?? 'Venue',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (value) => setState(() => venueId = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: organizerId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Organizer'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Any organizer')),
              ...organizers.map(
                (organizer) => DropdownMenuItem(
                  value: (organizer['id'] as num).toInt(),
                  child: Text(
                    organizer['name']?.toString() ?? 'Organizer',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (value) => setState(() => organizerId = value),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDates,
            icon: const Icon(Icons.date_range_rounded),
            label: Text(
              dateRange == null
                  ? 'Any date'
                  : '${DateFormat('MMM d').format(dateRange!.start)} – ${DateFormat('MMM d').format(dateRange!.end)}',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              alignment: Alignment.centerLeft,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: minPrice,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Min price'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: maxPrice,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Max price'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.pop(
              context,
              _ExploreFilterResult(
                venueId: venueId,
                organizerId: organizerId,
                dateRange: dateRange,
                minPrice: double.tryParse(minPrice.text.trim()),
                maxPrice: double.tryParse(maxPrice.text.trim()),
              ),
            ),
            icon: const Icon(Icons.search_rounded),
            label: const Text('Show matching events'),
          ),
        ],
      ),
    ),
  );

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDateRange: dateRange,
    );
    if (result != null && mounted) setState(() => dateRange = result);
  }
}

class EventCard extends StatefulWidget {
  const EventCard({super.key, required this.event, required this.onTap});
  final Map<String, dynamic> event;
  final VoidCallback onTap;

  @override
  State<EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<EventCard> {
  bool favorite = false;

  Map<String, dynamic> get event => widget.event;

  @override
  void initState() {
    super.initState();
    BuyerLocalStore.favorites().then((values) {
      if (mounted) setState(() => favorite = values.contains(event['slug']));
    });
  }

  Future<void> _toggleFavorite() async {
    HapticFeedback.selectionClick();
    final value = await BuyerLocalStore.toggleFavorite(
      event['slug']?.toString() ?? '',
    );
    if (mounted) setState(() => favorite = value);
  }

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: widget.onTap,
      child: Row(
        children: [
          SizedBox(
            width: 112,
            height: 132,
            child: Hero(
              tag: _eventHeroTag(event),
              createRectTween: (begin, end) =>
                  MaterialRectArcTween(begin: begin, end: end),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  EventImage(url: event['image_url']?.toString()),
                  if (event['has_ended'] == true) ...[
                    const ColoredBox(color: Color(0x52000000)),
                    Center(
                      child: Transform.rotate(
                        angle: -.11,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2.5),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Text(
                            'ENDED',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (event['is_hot'] == true)
                        const StatusChip(label: 'HOT', color: AppColors.coral),
                      const Spacer(),
                      Text(
                        _eventNextSession(event),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.coralDark,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    event['name']?.toString() ?? 'Event',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontSize: 17),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _eventPriceLabel(event),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.coralDark,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (_eventAvailabilityLabel(event) case final label?)
                        StatusChip(
                          label: label,
                          color: label == 'SOLD OUT'
                              ? AppColors.muted
                              : AppColors.coralDark,
                        ),
                      IconButton(
                        tooltip: favorite
                            ? 'Remove from favorites'
                            : 'Add to favorites',
                        onPressed: _toggleFavorite,
                        icon: Icon(
                          favorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: favorite ? AppColors.coralDark : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    event['venue']?['name']?.toString() ??
                        event['venue']?['city']?.toString() ??
                        'Venue TBA',
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
          ),
        ],
      ),
    ),
  );
}

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.api,
    required this.slug,
    required this.preview,
    required this.onPurchaseCompleted,
    required this.openTickets,
  });
  final ApiClient api;
  final String slug;
  final Map<String, dynamic> preview;
  final VoidCallback onPurchaseCompleted;
  final VoidCallback openTickets;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  int? selectedSessionId;
  late Future<Map<String, dynamic>> future = widget.api.get(
    '/mobile/events/${widget.slug}',
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: future,
    builder: (context, snapshot) {
      final response = snapshot.data;
      final loaded = response?['data'] is Map
          ? Map<String, dynamic>.from(response!['data'] as Map)
          : null;
      final event = loaded ?? widget.preview;
      final loading = snapshot.connectionState != ConnectionState.done;
      final eventEnded = event['has_ended'] == true;
      final sessions = (event['sessions'] as List? ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final activeSessionId =
          selectedSessionId ??
          (sessions.isEmpty ? null : (sessions.first['id'] as num?)?.toInt());
      final matchingSessions = sessions
          .where(
            (session) => (session['id'] as num?)?.toInt() == activeSessionId,
          )
          .toList();
      final activeSession = matchingSessions.isEmpty
          ? null
          : matchingSessions.first;
      final visibleTypes = (event['ticket_types'] as List? ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .where((type) {
            if (activeSessionId == null) return true;
            final sessionIds = (type['session_ids'] as List? ?? const [])
                .map((value) => (value as num).toInt())
                .toList();
            return sessionIds.isEmpty || sessionIds.contains(activeSessionId);
          })
          .toList();
      final checkoutEvent = <String, dynamic>{
        ...event,
        'ticket_types': visibleTypes,
        'selected_session_id': ?activeSessionId,
      };

      return Scaffold(
        backgroundColor: AppColors.canvas,
        bottomNavigationBar: !eventEnded && visibleTypes.isNotEmpty
            ? _EventCheckoutBar(
                event: checkoutEvent,
                onPressed: () => _openCart(checkoutEvent),
              )
            : null,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverAppBar(
              expandedHeight: 355,
              pinned: true,
              stretch: true,
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              forceMaterialTransparency: true,
              systemOverlayStyle: AppSystemUi.light,
              leading: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.black.withValues(alpha: .58),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                stretchModes: const [
                  StretchMode.zoomBackground,
                  StretchMode.blurBackground,
                ],
                background: Hero(
                  tag: _eventHeroTag(widget.preview),
                  createRectTween: (begin, end) =>
                      MaterialRectArcTween(begin: begin, end: end),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      EventImage(
                        url:
                            event['hero_image_url']?.toString() ??
                            event['image_url']?.toString(),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x33000000),
                              Colors.transparent,
                              Color(0xA6000000),
                            ],
                            stops: [0, .5, 1],
                          ),
                        ),
                      ),
                      if (eventEnded)
                        Center(
                          child: Transform.rotate(
                            angle: -.1,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .2),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 4,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'ENDED',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 22,
                        right: 22,
                        bottom: 34,
                        child: Text(
                          event['name']?.toString() ?? 'Event',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                color: Colors.white,
                                height: 1.02,
                                shadows: const [
                                  Shadow(
                                    color: Color(0x66000000),
                                    blurRadius: 18,
                                  ),
                                ],
                              ),
                        ),
                      ),
                      const Align(
                        alignment: Alignment.bottomCenter,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.canvas,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(28),
                            ),
                          ),
                          child: SizedBox(height: 18, width: double.infinity),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MotionEntrance(
                      delay: const Duration(milliseconds: 80),
                      offset: const Offset(0, .08),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (event['category']?['name'] != null)
                            StatusChip(
                              label: event['category']['name'].toString(),
                              color: AppColors.navy,
                            ),
                          if (event['is_hot'] == true)
                            const StatusChip(
                              label: 'Trending',
                              color: AppColors.coral,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (sessions.length > 1) ...[
                      MotionEntrance(
                        delay: const Duration(milliseconds: 120),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Choose a date',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 10),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: sessions.map((session) {
                                  final id = (session['id'] as num).toInt();
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      selected: id == activeSessionId,
                                      onSelected: (_) => setState(
                                        () => selectedSessionId = id,
                                      ),
                                      avatar: const Icon(
                                        Icons.calendar_month_rounded,
                                        size: 18,
                                      ),
                                      label: Text(
                                        '${session['name'] ?? 'Session'} · ${_date(session['starts_at'])}',
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    MotionEntrance(
                      delay: const Duration(milliseconds: 150),
                      offset: const Offset(0, .07),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            children: [
                              DetailRow(
                                icon: Icons.calendar_month_rounded,
                                title: _dateLong(
                                  activeSession?['starts_at'] ??
                                      event['starts_at'],
                                ),
                                subtitle:
                                    activeSession?['doors_open_at'] != null
                                    ? 'Doors open ${_time(activeSession?['doors_open_at'])}'
                                    : event['door_opens_at_note']?.toString(),
                              ),
                              const SizedBox(height: 16),
                              DetailRow(
                                icon: Icons.location_on_rounded,
                                title:
                                    activeSession?['venue']?['name']
                                        ?.toString() ??
                                    event['venue']?['name']?.toString() ??
                                    'Venue TBA',
                                subtitle:
                                    activeSession?['venue']?['address']
                                        ?.toString() ??
                                    event['venue']?['address']?.toString(),
                                onTap: () => _openVenueMap(
                                  activeSession?['venue']?['location_url']
                                          ?.toString() ??
                                      event['venue']?['location_url']
                                          ?.toString(),
                                ),
                                trailing:
                                    (activeSession?['venue']?['location_url'] ??
                                            event['venue']?['location_url']) !=
                                        null
                                    ? const Icon(Icons.open_in_new_rounded)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    MotionEntrance(
                      delay: const Duration(milliseconds: 230),
                      offset: const Offset(0, .065),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'About this event',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            event['about_event']?.toString() ??
                                event['summary']?.toString() ??
                                'More details are coming soon.',
                            style: const TextStyle(
                              height: 1.6,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (event['organizer'] is Map) ...[
                      const SizedBox(height: 24),
                      _OrganizerProfileCard(
                        organizer: Map<String, dynamic>.from(
                          event['organizer'] as Map,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    if (eventEnded)
                      MotionEntrance(
                        delay: const Duration(milliseconds: 310),
                        child: const Card(
                          color: AppColors.black,
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.event_busy_rounded,
                                  color: AppColors.yellow,
                                ),
                                SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    'This event has ended. Ticket sales are closed; event information remains available.',
                                    style: TextStyle(
                                      color: Colors.white,
                                      height: 1.45,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      MotionEntrance(
                        delay: const Duration(milliseconds: 310),
                        offset: const Offset(0, .06),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Choose your ticket',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            if (loading)
                              const SkeletonList(count: 2)
                            else if (snapshot.hasError)
                              EmptyState(
                                icon: Icons.wifi_off_rounded,
                                title: 'Ticket options did not load',
                                message: 'Check your connection and try again.',
                                action: FilledButton.tonalIcon(
                                  onPressed: () => setState(
                                    () => future = widget.api.get(
                                      '/mobile/events/${widget.slug}',
                                    ),
                                  ),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Try again'),
                                ),
                              )
                            else if (visibleTypes.isEmpty)
                              const EmptyState(
                                icon: Icons.event_seat_rounded,
                                title: 'Tickets coming soon',
                                message:
                                    'Ticket types will appear here when sales open.',
                              )
                            else
                              ...visibleTypes.map(
                                (raw) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: TicketTier(
                                    type: Map<String, dynamic>.from(raw as Map),
                                    currency:
                                        event['currency']?.toString() ?? 'EGP',
                                    onBuy: () => _openCart(
                                      checkoutEvent,
                                      initialTicketTypeId: (raw['id'] as num)
                                          .toInt(),
                                    ),
                                    onWaitlist: () => _joinWaitlist(
                                      (raw['id'] as num).toInt(),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _openCart(
    Map<String, dynamic> event, {
    int? initialTicketTypeId,
  }) async {
    final result = await showCheckoutCartSheet(
      context: context,
      api: widget.api,
      event: event,
      initialTicketTypeId: initialTicketTypeId,
    );
    if (result == null || !mounted) return;
    widget.onPurchaseCompleted();
    await _showCheckoutResult(result);
  }

  Future<void> _joinWaitlist(int ticketTypeId) async {
    try {
      await widget.api.post(
        '/mobile/buyer/events/${widget.slug}/waitlist',
        audience: 'buyer',
        data: {'ticket_type_id': ticketTypeId},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are on the waitlist. We will notify you first.'),
        ),
      );
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _openVenueMap(String? rawUrl) async {
    final url = Uri.tryParse(rawUrl ?? '');
    if (url == null || !url.isScheme('https')) return;
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
        mounted) {
      showAppNotice(context, 'Could not open the venue map.', error: true);
    }
  }

  Future<void> _showCheckoutResult(CheckoutCompletion result) async {
    if (result.status == CheckoutPaymentStatus.paid) {
      await HapticFeedback.heavyImpact();
    } else {
      await HapticFeedback.mediumImpact();
    }
    if (!mounted) return;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final paid = result.status == CheckoutPaymentStatus.paid;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            6,
            24,
            MediaQuery.paddingOf(sheetContext).bottom + 30,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const UxStepper(
                steps: ['Tickets', 'Details', 'Payment', 'Confirmation'],
                currentStep: 3,
              ),
              const SizedBox(height: 24),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: .65, end: 1),
                duration: MediaQuery.disableAnimationsOf(sheetContext)
                    ? Duration.zero
                    : const Duration(milliseconds: 520),
                curve: const Cubic(0.05, 0.7, 0.1, 1),
                builder: (context, value, child) => Transform.scale(
                  scale: value,
                  child: Opacity(opacity: value.clamp(0, 1), child: child),
                ),
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: paid
                        ? const Color(0xFFE1F7EE)
                        : const Color(0xFFFFF6C9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    paid ? Icons.verified_rounded : Icons.schedule_rounded,
                    color: paid ? AppColors.success : AppColors.coralDark,
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                paid ? 'Payment confirmed' : 'Order is being confirmed',
                textAlign: TextAlign.center,
                style: Theme.of(sheetContext).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                paid
                    ? '${result.orderNumber} is paid. Your tickets are now available in the Ticket wallet.'
                    : '${result.orderNumber} is saved in Orders. TKTS APP will update it automatically when Paymob confirms the payment.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, height: 1.5),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  if (paid) {
                    Navigator.pop(context);
                    widget.openTickets();
                  }
                },
                child: Text(paid ? 'View my tickets' : 'View status in Orders'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EventCheckoutBar extends StatelessWidget {
  const _EventCheckoutBar({required this.event, required this.onPressed});

  final Map<String, dynamic> event;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final types = (event['ticket_types'] as List? ?? const [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .where((type) => (type['available'] as num? ?? 0) > 0)
        .toList();
    final prices = types
        .map(
          (type) =>
              (type['early_bird_price'] as num?)?.toDouble() ??
              (type['price'] as num?)?.toDouble() ??
              0,
        )
        .toList();
    final minimum = prices.isEmpty
        ? 0.0
        : prices.reduce((value, price) => value < price ? value : price);
    final currency = event['currency']?.toString() ?? 'EGP';
    return Container(
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: AppColors.black,
        boxShadow: [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TICKETS FROM',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${minimum == minimum.roundToDouble() ? minimum.toStringAsFixed(0) : minimum.toStringAsFixed(2)} $currency',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: types.isEmpty ? null : onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
              backgroundColor: AppColors.yellow,
              foregroundColor: AppColors.black,
            ),
            icon: const Icon(Icons.shopping_bag_rounded, size: 18),
            label: const Text('Choose tickets'),
          ),
        ],
      ),
    );
  }
}

class NotificationsSheet extends StatefulWidget {
  const NotificationsSheet({super.key, required this.api});

  final ApiClient api;

  @override
  State<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<NotificationsSheet> {
  late Future<Map<String, dynamic>> future = _load();
  bool markingRead = false;
  String? error;
  String filter = 'all';

  Future<Map<String, dynamic>> _load() => widget.api.get(
    '/mobile/buyer/notifications',
    audience: 'buyer',
    query: {'per_page': 30},
  );

  Future<void> _markAllRead() async {
    if (markingRead) return;
    setState(() {
      markingRead = true;
      error = null;
    });
    try {
      await widget.api.post(
        '/mobile/buyer/notifications/read',
        audience: 'buyer',
      );
      if (mounted) {
        setState(() {
          future = _load();
        });
      }
    } catch (error) {
      if (mounted) setState(() => this.error = errorMessage(error));
    } finally {
      if (mounted) setState(() => markingRead = false);
    }
  }

  Future<void> _markRead(String id) async {
    try {
      await widget.api.post(
        '/mobile/buyer/notifications/$id/read',
        audience: 'buyer',
      );
      if (mounted) {
        setState(() {
          future = _load();
        });
      }
    } catch (caught) {
      if (mounted) setState(() => error = errorMessage(caught));
    }
  }

  Future<void> _delete(String id) async {
    try {
      await widget.api.delete(
        '/mobile/buyer/notifications/$id',
        audience: 'buyer',
      );
      if (mounted) {
        setState(() {
          future = _load();
        });
      }
    } catch (caught) {
      if (mounted) setState(() => error = errorMessage(caught));
    }
  }

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .88,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 10, 10),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.yellow,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.notifications_active_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Notifications',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: markingRead ? null : _markAllRead,
                  child: markingRead
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Mark all read'),
                ),
                IconButton(
                  tooltip: 'Notification preferences',
                  onPressed: _showPreferences,
                  icon: const Icon(Icons.tune_rounded),
                ),
                IconButton(
                  tooltip: 'Close notifications',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: error == null
                ? const SizedBox.shrink(key: ValueKey('notifications-no-error'))
                : Container(
                    key: const ValueKey('notifications-error'),
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE6E1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            error!,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          Expanded(
            child: SlktRefresh(
              onRefresh: () async {
                setState(() {
                  future = _load();
                });
                await future;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children:
                          [
                                'all',
                                'orders',
                                'payments',
                                'transfers',
                                'promotions',
                              ]
                              .map(
                                (value) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    selected: filter == value,
                                    onSelected: (_) =>
                                        setState(() => filter = value),
                                    label: Text(
                                      '${value[0].toUpperCase()}${value.substring(1)}',
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AsyncPanel(
                    future: future,
                    onRetry: () => setState(() {
                      future = _load();
                    }),
                    skeleton: const SectionSkeleton(cards: 4, cardHeight: 96),
                    builder: (context, response) {
                      final items = (response['data'] as List? ?? const [])
                          .where((raw) => _matchesFilter(raw as Map))
                          .toList();
                      if (items.isEmpty) {
                        return const EmptyState(
                          icon: Icons.notifications_none_rounded,
                          title: 'You are all caught up',
                          message:
                              'Payment and ticket transfer updates will appear here.',
                        );
                      }
                      return Column(
                        children: items.map((raw) {
                          final item = Map<String, dynamic>.from(raw as Map);
                          final unread = item['read_at'] == null;
                          final action = item['action']?.toString();
                          final meta = Map<String, dynamic>.from(
                            item['meta'] as Map? ?? const {},
                          );
                          final canOpen =
                              action != null ||
                              meta['order_id'] != null ||
                              meta['ticket_id'] != null ||
                              meta['event_slug'] != null;
                          final id = item['id']?.toString() ?? '';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Dismissible(
                              key: ValueKey('notification-$id'),
                              direction: DismissDirection.horizontal,
                              confirmDismiss: (direction) async {
                                if (direction == DismissDirection.startToEnd) {
                                  await _markRead(id);
                                } else {
                                  await _delete(id);
                                }
                                return false;
                              },
                              background: const _SwipeAction(
                                alignment: Alignment.centerLeft,
                                color: AppColors.navy,
                                icon: Icons.done_all_rounded,
                                label: 'Mark read',
                              ),
                              secondaryBackground: const _SwipeAction(
                                alignment: Alignment.centerRight,
                                color: Color(0xFFB42318),
                                icon: Icons.delete_outline_rounded,
                                label: 'Delete',
                              ),
                              child: Card(
                                color: unread
                                    ? const Color(0xFFFFF6C9)
                                    : AppColors.paper,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(28),
                                  onTap: !canOpen
                                      ? (unread ? () => _markRead(id) : null)
                                      : () async {
                                          if (unread) await _markRead(id);
                                          if (context.mounted) {
                                            Navigator.pop(
                                              context,
                                              jsonEncode({
                                                'action': action,
                                                'meta': meta,
                                              }),
                                            );
                                          }
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: unread
                                              ? AppColors.black
                                              : const Color(0xFFEDE8E3),
                                          foregroundColor: unread
                                              ? AppColors.yellow
                                              : AppColors.muted,
                                          child: Icon(
                                            _notificationIcon(
                                              item['kind']?.toString(),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 13),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item['title']?.toString() ??
                                                    'TKTS APP update',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                item['message']?.toString() ??
                                                    '',
                                                style: const TextStyle(
                                                  color: AppColors.muted,
                                                  height: 1.4,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                _date(item['created_at']),
                                                style: const TextStyle(
                                                  color: AppColors.muted,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (canOpen)
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  bool _matchesFilter(Map raw) {
    if (filter == 'all') return true;
    final kind = raw['kind']?.toString().toLowerCase() ?? '';
    return switch (filter) {
      'orders' => kind.contains('order') || kind.contains('ticket_issued'),
      'payments' => kind.contains('payment') || kind.contains('refund'),
      'transfers' => kind.contains('transfer'),
      'promotions' => kind.contains('promo') || kind.contains('campaign'),
      _ => true,
    };
  }

  Future<void> _showPreferences() async {
    final values = await BuyerLocalStore.notificationPreferences();
    if (!mounted) return;
    final updated = await showModalBottomSheet<Map<String, bool>>(
      context: context,
      showDragHandle: true,
      builder: (context) => _NotificationPreferences(initial: values),
    );
    if (updated == null) return;
    await BuyerLocalStore.saveNotificationPreferences(updated);
    try {
      for (final entry in updated.entries) {
        await OneSignal.User.addTagWithKey(
          'notify_${entry.key}',
          entry.value ? '1' : '0',
        );
      }
    } catch (_) {
      // Local inbox filtering remains available if push tag sync is offline.
    }
  }
}

class _NotificationPreferences extends StatefulWidget {
  const _NotificationPreferences({required this.initial});

  final Map<String, bool> initial;

  @override
  State<_NotificationPreferences> createState() =>
      _NotificationPreferencesState();
}

class _NotificationPreferencesState extends State<_NotificationPreferences> {
  late final values = Map<String, bool>.from(widget.initial);

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      22,
      8,
      22,
      MediaQuery.paddingOf(context).bottom + 24,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notification preferences',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose which updates can reach this device.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        ...values.entries.map(
          (entry) => SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: entry.value,
            onChanged: (value) {
              HapticFeedback.selectionClick();
              setState(() => values[entry.key] = value);
            },
            title: Text(
              '${entry.key[0].toUpperCase()}${entry.key.substring(1)}',
            ),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: () => Navigator.pop(context, values),
          child: const Text('Save preferences'),
        ),
      ],
    ),
  );
}

class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    alignment: alignment,
    padding: const EdgeInsets.symmetric(horizontal: 22),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

IconData _notificationIcon(String? kind) => switch (kind) {
  'payment_paid' => Icons.verified_rounded,
  'transfer_incoming' => Icons.move_to_inbox_rounded,
  'transfer_accepted' => Icons.swap_horiz_rounded,
  'transfer_declined' || 'transfer_cancelled' => Icons.cancel_outlined,
  _ => Icons.notifications_rounded,
};

class TicketsScreen extends StatefulWidget {
  const TicketsScreen({
    super.key,
    required this.api,
    required this.refreshSignal,
  });
  final ApiClient api;
  final ValueListenable<int> refreshSignal;

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen>
    with SingleTickerProviderStateMixin {
  late final tabs = TabController(length: 2, vsync: this);
  String ticketFilter = 'upcoming';
  late Future<Map<String, dynamic>> tickets = _loadTickets();
  late Future<Map<String, dynamic>> transfers = widget.api.get(
    '/buyer/transfers',
    audience: 'buyer',
  );

  @override
  void initState() {
    super.initState();
    widget.refreshSignal.addListener(_reload);
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      tickets = _loadTickets();
      transfers = widget.api.get('/buyer/transfers', audience: 'buyer');
    });
  }

  Future<Map<String, dynamic>> _loadTickets() async {
    try {
      final responses = await Future.wait([
        widget.api.get('/buyer/tickets', audience: 'buyer'),
        widget.api.get('/buyer/transfers', audience: 'buyer'),
      ]);
      final response = responses[0];
      final transferred = (responses[1]['transfers'] as List? ?? const [])
          .where(
            (raw) =>
                (raw as Map)['direction'] == 'sent' &&
                raw['status'] == 'completed',
          )
          .map((raw) {
            final transfer = Map<String, dynamic>.from(raw as Map);
            final ticket = Map<String, dynamic>.from(
              transfer['ticket'] as Map? ?? const {},
            );
            return {
              ...ticket,
              'id': 'transferred-${transfer['id']}',
              'status': 'transferred',
              'recipient_name': transfer['other_party']?['name'],
            };
          });
      final combined = <Object?>[
        ...List<Object?>.from(response['tickets'] as List? ?? const []),
        ...transferred,
      ];
      await BuyerLocalStore.cacheTickets(combined);
      return {...response, 'tickets': combined};
    } catch (_) {
      final cached = await BuyerLocalStore.cachedTickets();
      if (cached != null) return {...cached, 'offline': true};
      rethrow;
    }
  }

  void showTab(int index) {
    if (!mounted || index < 0 || index >= tabs.length) return;
    tabs.animateTo(index);
    _reload();
  }

  Future<void> openTicket(String ticketId) async {
    showTab(0);
    try {
      final response = await _loadTickets();
      final items = response['tickets'] as List? ?? const [];
      final matches = items.where(
        (raw) => (raw as Map)['id']?.toString() == ticketId,
      );
      if (matches.isEmpty || !mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TicketDetailScreen(
            api: widget.api,
            ticket: Map<String, dynamic>.from(matches.first as Map),
          ),
        ),
      );
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_reload);
    tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeading(
                'My passes',
                subtitle: 'Tickets, QR access and transfers in one place.',
              ),
              const SizedBox(height: 18),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFECE6E0),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TabBar(
                  controller: tabs,
                  padding: const EdgeInsets.all(4),
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: AppColors.black,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: AppColors.muted,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                  tabs: const [
                    Tab(text: 'Tickets'),
                    Tab(text: 'Transfers'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: tabs,
            children: [
              SlktRefresh(
                onRefresh: () async {
                  setState(() {
                    tickets = _loadTickets();
                  });
                  await tickets;
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['upcoming', 'used', 'expired', 'transferred']
                            .map(
                              (value) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  selected: ticketFilter == value,
                                  onSelected: (_) {
                                    HapticFeedback.selectionClick();
                                    setState(() => ticketFilter = value);
                                  },
                                  label: Text(
                                    '${value[0].toUpperCase()}${value.substring(1)}',
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AsyncPanel(
                      future: tickets,
                      builder: (context, response) {
                        final all = (response['tickets'] as List? ?? const [])
                            .map((raw) => Map<String, dynamic>.from(raw as Map))
                            .toList();
                        final items = all.where(_ticketMatchesFilter).toList();
                        if (items.isEmpty) {
                          return EmptyState(
                            icon: Icons.local_activity_outlined,
                            title: 'No $ticketFilter tickets',
                            message:
                                'Tickets matching this status will appear here.',
                          );
                        }
                        return Column(
                          children: items.map((raw) {
                            final ticket = Map<String, dynamic>.from(raw);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: WalletTicketCard(
                                ticket: ticket,
                                onQuickQr:
                                    ticket['qr_raw']?.toString().isNotEmpty ==
                                        true
                                    ? () => _showQuickQr(ticket)
                                    : null,
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TicketDetailScreen(
                                        api: widget.api,
                                        ticket: ticket,
                                      ),
                                    ),
                                  );
                                  setState(() {
                                    tickets = _loadTickets();
                                    transfers = widget.api.get(
                                      '/buyer/transfers',
                                      audience: 'buyer',
                                    );
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
              SlktRefresh(
                onRefresh: () async => setState(
                  () => transfers = widget.api.get(
                    '/buyer/transfers',
                    audience: 'buyer',
                  ),
                ),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
                  children: [
                    AsyncPanel(
                      future: transfers,
                      builder: (context, response) {
                        final items =
                            response['transfers'] as List? ?? const [];
                        if (items.isEmpty) {
                          return const EmptyState(
                            icon: Icons.swap_horiz_rounded,
                            title: 'No transfer activity',
                            message:
                                'Incoming and sent transfer requests will appear here.',
                          );
                        }
                        return Column(
                          children: items
                              .map(
                                (raw) => TransferCard(
                                  api: widget.api,
                                  transfer: Map<String, dynamic>.from(
                                    raw as Map,
                                  ),
                                  changed: () => setState(
                                    () => transfers = widget.api.get(
                                      '/buyer/transfers',
                                      audience: 'buyer',
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  bool _ticketMatchesFilter(Map<String, dynamic> ticket) {
    final status = ticket['status']?.toString().toLowerCase() ?? 'valid';
    final eventDate = DateTime.tryParse(ticket['event_date']?.toString() ?? '');
    return switch (ticketFilter) {
      'used' => status == 'used',
      'expired' => status == 'expired' || status == 'cancelled',
      'transferred' => status.contains('transfer'),
      _ =>
        status == 'valid' &&
            (eventDate == null || eventDate.isAfter(DateTime.now())),
    };
  }

  Future<void> _showQuickQr(Map<String, dynamic> ticket) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _BrightQrSheet(ticket: ticket),
      );
}

class WalletTicketCard extends StatelessWidget {
  const WalletTicketCard({
    super.key,
    required this.ticket,
    required this.onTap,
    this.onQuickQr,
  });
  final Map<String, dynamic> ticket;
  final VoidCallback onTap;
  final VoidCallback? onQuickQr;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 184,
    child: Card(
      color: AppColors.navy,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              right: -45,
              top: -55,
              child: Container(
                width: 170,
                height: 170,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [AppColors.coral, Color(0x0010172A)],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _date(ticket['event_date']),
                        style: const TextStyle(
                          color: Color(0xFFFFB59E),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      StatusChip(
                        label:
                            ticket['status']?.toString().toUpperCase() ??
                            'VALID',
                        color: _statusColor(ticket['status']?.toString()),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    ticket['event_name']?.toString() ?? 'Event ticket',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${ticket['ticket_type'] ?? 'Admission'} • ${ticket['gate'] ?? 'Gate TBA'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      if (onQuickQr != null)
                        IconButton(
                          tooltip: 'Show QR',
                          onPressed: onQuickQr,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white12,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.qr_code_2_rounded, size: 30),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BrightQrSheet extends StatelessWidget {
  const _BrightQrSheet({required this.ticket});

  final Map<String, dynamic> ticket;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      12,
      24,
      MediaQuery.paddingOf(context).bottom + 28,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          ticket['event_name']?.toString() ?? 'Ticket QR',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          '${ticket['ticket_type'] ?? 'Admission'} • ${ticket['gate'] ?? 'Gate TBA'}',
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        _BrightQr(data: ticket['qr_raw']?.toString() ?? '', size: 280),
        const SizedBox(height: 14),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.brightness_high_rounded, size: 18),
            SizedBox(width: 7),
            Text('Brightness raised for faster scanning'),
          ],
        ),
      ],
    ),
  );
}

class _BrightQr extends StatefulWidget {
  const _BrightQr({required this.data, required this.size});

  final String data;
  final double size;

  @override
  State<_BrightQr> createState() => _BrightQrState();
}

class _BrightQrState extends State<_BrightQr> {
  @override
  void initState() {
    super.initState();
    ScreenBrightness.instance.setApplicationScreenBrightness(1);
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    ScreenBrightness.instance.resetApplicationScreenBrightness();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
    ),
    child: QrImageView(
      data: widget.data,
      size: widget.size,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    ),
  );
}

class TicketDetailScreen extends StatelessWidget {
  const TicketDetailScreen({
    super.key,
    required this.api,
    required this.ticket,
  });
  final ApiClient api;
  final Map<String, dynamic> ticket;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(ticket['label']?.toString() ?? 'Ticket')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Text(
                ticket['event_name']?.toString() ?? 'Event',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${_dateLong(ticket['event_date'])}\n${ticket['venue'] ?? 'Venue TBA'}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.5),
              ),
              const SizedBox(height: 24),
              _BrightQr(data: ticket['qr_raw']?.toString() ?? '', size: 230),
              const SizedBox(height: 12),
              const Text(
                'Present this QR at the venue entrance',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                TicketInfo(
                  label: 'Ticket type',
                  value: ticket['ticket_type']?.toString(),
                ),
                TicketInfo(label: 'Gate', value: ticket['gate']?.toString()),
                TicketInfo(
                  label: 'Seat',
                  value: ticket['seat']?.toString() ?? 'N/A',
                ),
                TicketInfo(
                  label: 'Holder',
                  value: ticket['recipient_name']?.toString(),
                ),
                TicketInfo(
                  label: 'Status',
                  value: ticket['status']?.toString(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => _download(context),
          icon: const Icon(Icons.picture_as_pdf_rounded),
          label: const Text('Download one-time PDF'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () async {
            final sent = await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              showDragHandle: false,
              backgroundColor: Colors.transparent,
              builder: (_) => TransferSheet(api: api, ticket: ticket),
            );
            if (sent == true && context.mounted) {
              showAppNotice(
                context,
                'Transfer request sent. Waiting for recipient approval.',
              );
            }
          },
          icon: const Icon(Icons.swap_horiz_rounded),
          label: const Text('Transfer this ticket'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            shape: const StadiumBorder(),
          ),
        ),
      ],
    ),
  );

  Future<void> _download(BuildContext context) async {
    try {
      final response = await api.post(
        '/buyer/tickets/${ticket['id']}/pdf-link',
        audience: 'buyer',
      );
      final url = Uri.parse(response['url'].toString());
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw const ApiException('Could not open the PDF link.');
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class TransferSheet extends StatefulWidget {
  const TransferSheet({super.key, required this.api, required this.ticket});
  final ApiClient api;
  final Map<String, dynamic> ticket;

  @override
  State<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<TransferSheet> {
  final recipient = TextEditingController();
  Map<String, dynamic>? preview;
  bool confirmed = false;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    recipient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: AppColors.canvas,
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        18,
        22,
        MediaQuery.viewInsetsOf(context).bottom + 28,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transfer ticket',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'The recipient must already have a TKTS APP account. After acceptance, your old QR is cancelled and a new one is issued.',
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 18),
            UxStepper(
              steps: const ['Recipient', 'Preview', 'Confirm'],
              currentStep: preview == null ? 0 : (confirmed ? 2 : 1),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.yellow,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.swap_horiz_rounded),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Close transfer',
                  onPressed: busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: recipient,
              decoration: InputDecoration(
                labelText: 'Account code, email or mobile',
                prefixIcon: const Icon(Icons.person_search_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Choose from contacts',
                  onPressed: busy ? null : _pickContact,
                  icon: const Icon(Icons.contacts_rounded),
                ),
              ),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: error == null
                  ? const SizedBox.shrink(key: ValueKey('transfer-no-error'))
                  : Container(
                      key: const ValueKey('transfer-error'),
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE6E1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              error!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            OutlinedButton(
              onPressed: busy ? null : _lookup,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: const StadiumBorder(),
              ),
              child: const Text('Find registered recipient'),
            ),
            if (preview != null) ...[
              const SizedBox(height: 18),
              Card(
                color: const Color(0xFFFFEEE6),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.coral,
                    backgroundImage:
                        preview!['avatar_url']?.toString().isNotEmpty == true
                        ? NetworkImage(preview!['avatar_url'].toString())
                        : null,
                    child: preview!['avatar_url']?.toString().isNotEmpty == true
                        ? null
                        : Text(
                            _initials(preview!['name']),
                            style: const TextStyle(color: Colors.white),
                          ),
                  ),
                  title: Text(
                    preview!['name']?.toString() ?? 'Registered buyer',
                  ),
                  subtitle: Text(
                    preview!['contact']?.toString() ??
                        preview!['masked_phone']?.toString() ??
                        preview!['phone']?.toString() ??
                        'Verified TKTS APP account',
                  ),
                  trailing: const Icon(
                    Icons.verified_rounded,
                    color: AppColors.success,
                  ),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: confirmed,
                onChanged: (value) =>
                    setState(() => confirmed = value ?? false),
                title: const Text('I approve moving ownership of this ticket.'),
                subtitle: const Text(
                  'Completion requires the recipient\'s approval.',
                ),
              ),
              FilledButton(
                onPressed: !confirmed || busy ? null : _send,
                child: busy
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : const Text('Approve & send request'),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Future<void> _lookup() async {
    if (recipient.text.trim().isEmpty) {
      setState(() => error = 'Enter an account code, email or mobile number.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      preview = null;
      confirmed = false;
    });
    try {
      final response = await widget.api.post(
        '/buyer/transfer-recipients/lookup',
        audience: 'buyer',
        data: {'recipient': recipient.text.trim()},
      );
      setState(
        () => preview = Map<String, dynamic>.from(response['recipient'] as Map),
      );
    } catch (error) {
      if (mounted) setState(() => this.error = errorMessage(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pickContact() async {
    try {
      final status = await FlutterContacts.permissions.request(
        PermissionType.read,
      );
      if (status != PermissionStatus.granted) {
        if (mounted) {
          setState(
            () => error =
                'Contacts permission is needed only to choose a recipient.',
          );
        }
        return;
      }
      final contact = await FlutterContacts.native.showPicker(
        properties: {ContactProperty.phone},
      );
      final phones = contact?.phones;
      final phone = phones == null || phones.isEmpty
          ? null
          : phones.first.number.trim();
      if (phone == null || phone.isEmpty || !mounted) return;
      recipient.text = phone;
      HapticFeedback.selectionClick();
      await _lookup();
    } catch (caught) {
      if (mounted) setState(() => error = errorMessage(caught));
    }
  }

  Future<void> _send() async {
    HapticFeedback.mediumImpact();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.post(
        '/buyer/tickets/${widget.ticket['id']}/transfers',
        audience: 'buyer',
        data: {'recipient': recipient.text.trim(), 'confirmed': true},
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => this.error = errorMessage(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _TransferTimeline extends StatelessWidget {
  const _TransferTimeline({required this.transfer, required this.incoming});

  final Map<String, dynamic> transfer;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    final completed = transfer['completed_at'] != null;
    final recipientApproved = transfer['recipient_approved_at'] != null;
    final status = transfer['status']?.toString() ?? 'pending';
    final stopped = ['declined', 'cancelled', 'expired'].contains(status);
    final steps = <(String, bool)>[
      ('Sender approved', transfer['sender_approved_at'] != null),
      (incoming ? 'Your approval' : 'Recipient approval', recipientApproved),
      (stopped ? status.toUpperCase() : 'Ownership moved', completed),
    ];
    return Row(
      children: List.generate(steps.length, (index) {
        final active = steps[index].$2;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 240),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: active ? AppColors.success : AppColors.line,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        active ? Icons.check_rounded : Icons.more_horiz_rounded,
                        size: 15,
                        color: active ? Colors.white : AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      steps[index].$1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: active ? AppColors.ink : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (index < steps.length - 1)
                Container(
                  width: 20,
                  height: 2,
                  color: steps[index + 1].$2
                      ? AppColors.success
                      : AppColors.line,
                ),
            ],
          ),
        );
      }),
    );
  }
}

class TransferCard extends StatefulWidget {
  const TransferCard({
    super.key,
    required this.api,
    required this.transfer,
    required this.changed,
  });
  final ApiClient api;
  final Map<String, dynamic> transfer;
  final VoidCallback changed;

  @override
  State<TransferCard> createState() => _TransferCardState();
}

class _TransferCardState extends State<TransferCard> {
  bool busy = false;
  String? actionError;

  @override
  Widget build(BuildContext context) {
    final incoming =
        widget.transfer['direction'] == 'incoming' ||
        widget.transfer['can_accept'] == true;
    final status =
        widget.transfer['status']?.toString() ?? 'pending_recipient_approval';
    final otherParty = Map<String, dynamic>.from(
      widget.transfer['other_party'] as Map? ?? const {},
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: incoming
                          ? const Color(0xFFE1F7EE)
                          : const Color(0xFFFFF6C9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      incoming
                          ? Icons.call_received_rounded
                          : Icons.call_made_rounded,
                      color: incoming ? AppColors.success : AppColors.coralDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          incoming ? 'Incoming transfer' : 'Sent transfer',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          incoming
                              ? 'From ${otherParty['name'] ?? 'TKTS APP buyer'}'
                              : 'To ${otherParty['name'] ?? 'TKTS APP buyer'}',
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
                  const SizedBox(width: 8),
                  StatusChip(
                    label: status.replaceAll('_', ' ').toUpperCase(),
                    color: _statusColor(status),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                widget.transfer['event_name']?.toString() ??
                    widget.transfer['ticket']?['event_name']?.toString() ??
                    'Ticket transfer',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontSize: 17),
              ),
              const SizedBox(height: 8),
              if (widget.transfer['created_at'] != null)
                Text(
                  _date(widget.transfer['created_at']),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              if (otherParty['contact'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  otherParty['contact'].toString(),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              _TransferTimeline(transfer: widget.transfer, incoming: incoming),
              if (actionError != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE6E1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    actionError!,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
              if (widget.transfer['can_accept'] == true) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy ? null : () => _act('decline'),
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: busy ? null : () => _act('accept'),
                        child: busy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Accept ticket'),
                      ),
                    ),
                  ],
                ),
              ] else if (widget.transfer['can_cancel'] == true) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: busy ? null : () => _act('cancel'),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cancel request'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _act(String action) async {
    HapticFeedback.mediumImpact();
    setState(() {
      busy = true;
      actionError = null;
    });
    try {
      final response = await widget.api.post(
        '/buyer/transfers/${widget.transfer['id']}/$action',
        audience: 'buyer',
        data: action == 'accept' ? {'confirmed': true} : null,
      );
      if (!mounted) return;
      showAppNotice(
        context,
        response['message']?.toString() ?? 'Transfer updated successfully.',
      );
      widget.changed();
    } catch (error) {
      if (mounted) setState(() => actionError = errorMessage(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({
    super.key,
    required this.api,
    required this.refreshSignal,
    required this.openTickets,
  });
  final ApiClient api;
  final ValueListenable<int> refreshSignal;
  final VoidCallback openTickets;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late Future<Map<String, dynamic>> future = widget.api.get(
    '/mobile/buyer/orders',
    audience: 'buyer',
  );

  @override
  void initState() {
    super.initState();
    widget.refreshSignal.addListener(_reload);
  }

  void _reload() {
    if (!mounted) return;
    setState(
      () => future = widget.api.get('/mobile/buyer/orders', audience: 'buyer'),
    );
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SlktRefresh(
      onRefresh: () async => setState(
        () =>
            future = widget.api.get('/mobile/buyer/orders', audience: 'buyer'),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
        children: [
          const PageHeading(
            'Your orders',
            subtitle: 'Payments, totals and all tickets in each order.',
          ),
          const SizedBox(height: 22),
          AsyncPanel(
            future: future,
            builder: (context, response) {
              final items = response['data'] as List? ?? const [];
              if (items.isEmpty) {
                return const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No orders yet',
                  message: 'Your purchases will be organized here.',
                );
              }
              return Column(
                children: items.map((raw) {
                  final order = Map<String, dynamic>.from(raw as Map);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OrderDetailScreen(
                                api: widget.api,
                                order: order,
                                openTickets: widget.openTickets,
                              ),
                            ),
                          );
                          _reload();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  StatusChip(
                                    label:
                                        order['status']
                                            ?.toString()
                                            .toUpperCase() ??
                                        'PENDING',
                                    color: _statusColor(
                                      order['status']?.toString(),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    order['order_number']?.toString() ?? '',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                order['event']?['name']?.toString() ??
                                    'Event order',
                                style: Theme.of(
                                  context,
                                ).textTheme.titleLarge?.copyWith(fontSize: 17),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${order['total_amount']} ${order['currency'] ?? 'EGP'} • ${_date(order['created_at'])}',
                                style: const TextStyle(color: AppColors.muted),
                              ),
                              if (order['status']?.toString() == 'pending') ...[
                                const SizedBox(height: 12),
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.play_circle_outline_rounded,
                                      size: 18,
                                      color: AppColors.coralDark,
                                    ),
                                    SizedBox(width: 7),
                                    Text(
                                      'Open to continue payment',
                                      style: TextStyle(
                                        color: AppColors.coralDark,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Spacer(),
                                    Icon(Icons.chevron_right_rounded),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    ),
  );
}

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.api,
    required this.order,
    required this.openTickets,
  });

  final ApiClient api;
  final Map<String, dynamic> order;
  final VoidCallback openTickets;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Future<Map<String, dynamic>> future = _load();
  bool paymentBusy = false;

  Future<Map<String, dynamic>> _load() => widget.api.get(
    '/mobile/buyer/orders/${widget.order['id']}',
    audience: 'buyer',
  );

  void _reload() => setState(() {
    future = _load();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Order details')),
    body: SlktRefresh(
      onRefresh: () async => _reload(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        children: [
          AsyncPanel(
            future: future,
            builder: (context, response) {
              final order = Map<String, dynamic>.from(
                response['data'] as Map? ?? const {},
              );
              final event = Map<String, dynamic>.from(
                order['event'] as Map? ?? const {},
              );
              final items = order['items'] as List? ?? const [];
              final tickets = order['tickets'] as List? ?? const [];
              final canResume = order['can_resume_payment'] == true;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            StatusChip(
                              label:
                                  order['status']?.toString().toUpperCase() ??
                                  'PENDING',
                              color: _statusColor(order['status']?.toString()),
                            ),
                            const Spacer(),
                            Text(
                              order['order_number']?.toString() ?? '',
                              style: const TextStyle(color: Colors.white60),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Text(
                          event['name']?.toString() ?? 'Event order',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${order['total_amount']} ${order['currency'] ?? 'EGP'}  •  ${_date(order['created_at'])}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _OrderTimeline(
                    order: order,
                    ticketsIssued: tickets.isNotEmpty,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Inside this order',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  ...items.map((raw) {
                    final item = Map<String, dynamic>.from(raw as Map);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        leading: Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.yellow,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${item['quantity'] ?? 0}×',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        title: Text(item['name']?.toString() ?? 'Ticket'),
                        subtitle: Text(
                          '${item['unit_price']} ${item['currency'] ?? order['currency'] ?? 'EGP'} each',
                        ),
                      ),
                    );
                  }),
                  if (tickets.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Issued tickets',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    ...tickets.map((raw) {
                      final ticket = Map<String, dynamic>.from(raw as Map);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const Icon(Icons.confirmation_num_rounded),
                          title: Text(
                            ticket['ticket_type']?.toString() ?? 'Admission',
                          ),
                          subtitle: Text(
                            ticket['recipient_name']?.toString() ??
                                'Ticket holder',
                          ),
                          trailing: StatusChip(
                            label:
                                ticket['status']?.toString().toUpperCase() ??
                                'VALID',
                            color: _statusColor(ticket['status']?.toString()),
                          ),
                        ),
                      );
                    }),
                  ],
                  if (canResume) ...[
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: paymentBusy ? null : () => _resume(order),
                      icon: paymentBusy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_rounded),
                      label: const Text('Continue secure payment'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your reservation remains held only until the countdown expires.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ] else if (order['status'] == 'paid') ...[
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.openTickets();
                      },
                      icon: const Icon(Icons.confirmation_num_rounded),
                      label: const Text('View my tickets'),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    ),
  );

  Future<void> _resume(Map<String, dynamic> order) async {
    final checkoutUrl = Uri.tryParse(order['checkout_url']?.toString() ?? '');
    final expiresAt = DateTime.tryParse(
      order['checkout_expires_at']?.toString() ?? '',
    );
    final serverTime = DateTime.tryParse(
      order['server_time']?.toString() ?? '',
    );
    final orderId = (order['id'] as num?)?.toInt();
    if (checkoutUrl == null ||
        !isTrustedPaymobCheckoutUrl(checkoutUrl) ||
        expiresAt == null ||
        serverTime == null ||
        orderId == null) {
      showAppNotice(context, 'This payment session can no longer be resumed.');
      _reload();
      return;
    }

    setState(() => paymentBusy = true);
    final result = await showPaymentSheet(
      context: context,
      api: widget.api,
      checkoutUrl: checkoutUrl,
      orderId: orderId,
      orderNumber: order['order_number']?.toString() ?? 'Order #$orderId',
      redirectPath:
          order['redirect_path']?.toString() ?? '/checkout/$orderId/success',
      expiresAt: expiresAt,
      serverTime: serverTime,
    );
    if (!mounted) return;
    setState(() => paymentBusy = false);
    if (result?.status == CheckoutPaymentStatus.paid) {
      Navigator.pop(context);
      widget.openTickets();
    } else {
      _reload();
    }
  }
}

class _OrderTimeline extends StatelessWidget {
  const _OrderTimeline({required this.order, required this.ticketsIssued});

  final Map<String, dynamic> order;
  final bool ticketsIssued;

  @override
  Widget build(BuildContext context) {
    final status = order['status']?.toString().toLowerCase() ?? 'pending';
    final paid = ['paid', 'completed', 'refunded'].contains(status);
    final refunded = status == 'refunded';
    final steps = [
      ('Order placed', true, Icons.receipt_long_rounded),
      ('Payment confirmed', paid, Icons.verified_rounded),
      ('Tickets issued', ticketsIssued, Icons.confirmation_num_rounded),
      ('Refund completed', refunded, Icons.replay_circle_filled_rounded),
    ];
    return Semantics(
      label: 'Order progress',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order progress',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              ...List.generate(steps.length, (index) {
                final step = steps[index];
                final active = step.$2;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        AnimatedContainer(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 280),
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.black
                                : const Color(0xFFE7E1DC),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            step.$3,
                            size: 17,
                            color: active ? AppColors.yellow : AppColors.muted,
                          ),
                        ),
                        if (index < steps.length - 1)
                          Container(
                            width: 2,
                            height: 28,
                            color: active
                                ? AppColors.black
                                : const Color(0xFFE7E1DC),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          step.$1,
                          style: TextStyle(
                            color: active ? AppColors.ink : AppColors.muted,
                            fontWeight: active
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.api, required this.session});
  final ApiClient api;
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    return SafeArea(
      child: MotionEntrance(
        offset: const Offset(.045, 0),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
          children: [
            const PageHeading(
              'Your profile',
              subtitle: 'Identity, security and support.',
            ),
            const SizedBox(height: 22),
            Card(
              color: AppColors.navy,
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 31,
                      backgroundColor: AppColors.coral,
                      child: Text(
                        _initials(user['name']),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user['name']?.toString() ?? 'TKTS APP buyer',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user['account_code']?.toString() ??
                                user['buyer_account_code']?.toString() ??
                                '',
                            style: const TextStyle(color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      user['phone_verified'] == true
                          ? Icons.verified_rounded
                          : Icons.warning_amber_rounded,
                      color: user['phone_verified'] == true
                          ? const Color(0xFF69E6C0)
                          : Colors.amber,
                    ),
                  ],
                ),
              ),
            ),
            if (user['phone_verified'] != true) ...[
              const SizedBox(height: 14),
              Card(
                color: const Color(0xFFFFE9DF),
                child: ListTile(
                  leading: const Icon(
                    Icons.phone_android_rounded,
                    color: AppColors.coralDark,
                  ),
                  title: const Text('Verify your phone'),
                  subtitle: const Text('Required before ticket purchases.'),
                  trailing: const Icon(Icons.arrow_forward_rounded),
                  onTap: () => _verifyPhone(context),
                ),
              ),
            ],
            const SizedBox(height: 18),
            _ProfileSection(
              title: 'Account',
              icon: Icons.person_outline_rounded,
              children: [
                ProfileTile(
                  onTap: () => _editName(context),
                  icon: Icons.badge_outlined,
                  title: 'Name',
                  subtitle: user['name']?.toString() ?? 'Not set',
                ),
                ProfileTile(
                  icon: Icons.phone_rounded,
                  title: 'Mobile',
                  subtitle: user['phone']?.toString() ?? 'Not set',
                ),
                ProfileTile(
                  icon: Icons.mail_outline_rounded,
                  title: 'Email',
                  subtitle: user['email']?.toString() ?? 'Not set',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ProfileSection(
              title: 'Security',
              icon: Icons.shield_outlined,
              children: [
                ProfileTile(
                  onTap: () => _changePassword(context),
                  icon: Icons.lock_reset_rounded,
                  title: 'Change password',
                  subtitle: 'Current password required',
                ),
                ProfileTile(
                  icon: Icons.phonelink_lock_rounded,
                  title: 'Phone verification',
                  subtitle: user['phone_verified'] == true
                      ? 'Verified'
                      : 'Verification required',
                  onTap: user['phone_verified'] == true
                      ? null
                      : () => _verifyPhone(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _ProfileSection(
              title: 'Notifications',
              icon: Icons.notifications_none_rounded,
              children: [
                ProfileTile(
                  icon: Icons.notifications_active_outlined,
                  title: 'Push notifications',
                  subtitle: 'Orders, tickets and transfer updates',
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _ProfileSection(
              title: 'Help & preferences',
              icon: Icons.tune_rounded,
              children: [
                ProfileTile(
                  icon: Icons.language_rounded,
                  title: 'Language',
                  subtitle: 'English • Arabic ready',
                ),
                ProfileTile(
                  icon: Icons.support_agent_rounded,
                  title: 'Help & support',
                  subtitle: 'Contact the TKTS APP team',
                ),
              ],
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: session.logout,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                shape: const StadiumBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _verifyPhone(BuildContext context) async {
    try {
      await api.post('/buyer/phone/send-otp', audience: 'buyer');
      if (!context.mounted) return;
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            phone: session.user['phone']?.toString() ?? '',
            title: 'Verify your phone',
            subtitle: 'Enter the code sent to your registered mobile.',
            onVerify: (code) => api.post(
              '/buyer/phone/verify',
              audience: 'buyer',
              data: {'code': code},
            ),
            onResend: () =>
                api.post('/buyer/phone/send-otp', audience: 'buyer'),
          ),
        ),
      );
      if (result != null) await session.refreshBuyer();
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _editName(BuildContext context) async {
    final values = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SecureProfileSheet.name(
        initialName: session.user['name']?.toString() ?? '',
      ),
    );
    if (values == null || !context.mounted) return;
    try {
      await api.patch('/buyer/profile', audience: 'buyer', data: values);
      await session.refreshBuyer();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name changed successfully.')),
        );
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final values = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _SecureProfileSheet.password(),
    );
    if (values == null || !context.mounted) return;
    try {
      await api.post(
        '/buyer/profile/password',
        audience: 'buyer',
        data: values,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed successfully.')),
        );
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class _SecureProfileSheet extends StatefulWidget {
  const _SecureProfileSheet.name({required this.initialName})
    : changesName = true;

  const _SecureProfileSheet.password() : changesName = false, initialName = '';

  final bool changesName;
  final String initialName;

  @override
  State<_SecureProfileSheet> createState() => _SecureProfileSheetState();
}

class _SecureProfileSheetState extends State<_SecureProfileSheet> {
  late final name = TextEditingController(text: widget.initialName);
  final current = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();

  @override
  void dispose() {
    name.dispose();
    current.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.changesName) {
      if (name.text.trim().length < 2 || current.text.isEmpty) {
        showAppNotice(
          context,
          'Enter your full name and current password.',
          error: true,
        );
        return;
      }
      FocusScope.of(context).unfocus();
      Navigator.pop(context, {
        'name': name.text.trim(),
        'current_password': current.text,
      });
      return;
    }

    if (current.text.isEmpty || password.text.length < 8) {
      showAppNotice(
        context,
        'Enter your current password and a new password of at least 8 characters.',
        error: true,
      );
      return;
    }
    if (password.text != confirmation.text) {
      showAppNotice(context, 'New passwords do not match.', error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.pop(context, {
      'current_password': current.text,
      'password': password.text,
      'password_confirmation': confirmation.text,
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    padding: EdgeInsets.fromLTRB(
      22,
      20,
      22,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            widget.changesName ? 'Change your name' : 'Change password',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            widget.changesName
                ? 'Enter your new name and confirm the change with your current password.'
                : 'Use at least 8 characters with uppercase, lowercase, number and symbol.',
            style: const TextStyle(color: AppColors.muted, height: 1.4),
          ),
          const SizedBox(height: 20),
          if (widget.changesName) ...[
            TextField(
              key: const ValueKey('profile-name-input'),
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            key: widget.changesName
                ? const ValueKey('profile-name-current-password')
                : const ValueKey('profile-password-current'),
            controller: current,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Current password',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
          ),
          if (!widget.changesName) ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('profile-password-new'),
              controller: password,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('profile-password-confirmation'),
              controller: confirmation,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            key: widget.changesName
                ? const ValueKey('profile-name-submit')
                : const ValueKey('profile-password-submit'),
            onPressed: _submit,
            icon: Icon(
              widget.changesName
                  ? Icons.verified_user_outlined
                  : Icons.lock_reset_rounded,
            ),
            label: Text(
              widget.changesName ? 'Confirm & change name' : 'Change password',
            ),
          ),
        ],
      ),
    ),
  );
}

class _OrganizerProfileCard extends StatelessWidget {
  const _OrganizerProfileCard({required this.organizer});

  final Map<String, dynamic> organizer;

  @override
  Widget build(BuildContext context) {
    final logo = organizer['logo_url']?.toString();
    final blurb = organizer['profile_blurb']?.toString().trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipOval(
              child: SizedBox(
                width: 54,
                height: 54,
                child: logo == null || logo.isEmpty
                    ? const ColoredBox(
                        color: AppColors.yellow,
                        child: Icon(Icons.apartment_rounded),
                      )
                    : EventImage(url: logo),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ORGANIZED BY',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    organizer['name']?.toString() ?? 'Event organizer',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (blurb != null && blurb.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      blurb,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TicketTier extends StatelessWidget {
  const TicketTier({
    super.key,
    required this.type,
    required this.currency,
    required this.onBuy,
    required this.onWaitlist,
  });
  final Map<String, dynamic> type;
  final String currency;
  final VoidCallback onBuy;
  final VoidCallback onWaitlist;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
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
                  '${type['available'] ?? 0} available • ${type['gate_label'] ?? 'Gate TBA'}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${type['early_bird_price'] ?? type['price']} $currency',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: (type['available'] as num? ?? 0) > 0
                    ? onBuy
                    : onWaitlist,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(96, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  (type['available'] as num? ?? 0) > 0 ? 'Select' : 'Waitlist',
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class EventImage extends StatelessWidget {
  const EventImage({super.key, this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final value = url;
    if (value == null || value.isEmpty) {
      return Container(
        color: const Color(0xFFE7DCD5),
        child: const Icon(
          Icons.celebration_rounded,
          color: AppColors.coral,
          size: 42,
        ),
      );
    }
    final absolute = value.startsWith('http')
        ? value
        : 'https://slktegy.com/${value.replaceFirst(RegExp(r'^/'), '')}';
    return CachedNetworkImage(
      imageUrl: absolute,
      fit: BoxFit.cover,
      placeholder: (_, _) => Container(color: const Color(0xFFE7DCD5)),
      errorWidget: (_, _, _) => Container(
        color: const Color(0xFFE7DCD5),
        child: const Icon(Icons.celebration_rounded, color: AppColors.coral),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
    ],
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
    ),
  );
}

class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE7DC),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: AppColors.coralDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Padding(padding: const EdgeInsets.only(top: 10), child: trailing!),
          ],
        ],
      ),
    ),
  );
}

class TicketInfo extends StatelessWidget {
  const TicketInfo({super.key, required this.label, this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Text(label, style: const TextStyle(color: AppColors.muted)),
        const Spacer(),
        Flexible(
          child: Text(
            value?.isNotEmpty == true ? value! : 'N/A',
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class ProfileTile extends StatelessWidget {
  const ProfileTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      leading: Icon(icon, color: AppColors.coralDark),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 20, color: AppColors.coralDark),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
      const SizedBox(height: 10),
      ...children,
    ],
  );
}

void _openEvent(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> event,
  VoidCallback onPurchaseCompleted,
  VoidCallback openTickets,
) {
  HapticFeedback.selectionClick();
  unawaited(BuyerLocalStore.rememberEvent(event));
  Navigator.push(
    context,
    SlktEventPageRoute(
      settings: RouteSettings(name: '/events/${event['slug']}'),
      builder: (_) => EventDetailScreen(
        api: api,
        slug: event['slug'].toString(),
        preview: event,
        onPurchaseCompleted: onPurchaseCompleted,
        openTickets: openTickets,
      ),
    ),
  );
}

String _eventHeroTag(Map<String, dynamic> event) =>
    event['_hero_tag']?.toString() ??
    'slkt-event-banner-${event['slug'] ?? event['id'] ?? event['name']}';

String _eventPriceLabel(Map<String, dynamic> event) {
  final types = (event['ticket_types'] as List? ?? const [])
      .map((raw) => Map<String, dynamic>.from(raw as Map))
      .toList();
  if (types.isEmpty) return 'Tickets coming soon';
  final prices = types
      .map((type) => (type['early_bird_price'] ?? type['price']) as num?)
      .whereType<num>()
      .map((value) => value.toDouble())
      .toList();
  if (prices.isEmpty) return 'View ticket options';
  prices.sort();
  final currency = event['currency']?.toString() ?? 'EGP';
  final minimum = prices.first;
  final formatted = minimum == minimum.roundToDouble()
      ? minimum.toStringAsFixed(0)
      : minimum.toStringAsFixed(2);
  return 'Starts from $formatted $currency';
}

String? _eventAvailabilityLabel(Map<String, dynamic> event) {
  final types = event['ticket_types'] as List? ?? const [];
  if (types.isEmpty) return null;
  final available = types.fold<int>(
    0,
    (sum, raw) => sum + ((raw as Map)['available'] as num? ?? 0).toInt(),
  );
  if (available <= 0) return 'SOLD OUT';
  if (available <= 10) return '$available LEFT';
  return null;
}

String _eventNextSession(Map<String, dynamic> event) {
  final sessions =
      (event['sessions'] as List? ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .where(
            (session) =>
                DateTime.tryParse(
                  session['starts_at']?.toString() ?? '',
                )?.isAfter(DateTime.now()) ??
                false,
          )
          .toList()
        ..sort(
          (a, b) => DateTime.parse(
            a['starts_at'].toString(),
          ).compareTo(DateTime.parse(b['starts_at'].toString())),
        );
  return sessions.isEmpty
      ? _date(event['starts_at'])
      : _date(sessions.first['starts_at']);
}

String _firstName(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? 'there' : text.split(RegExp(r'\s+')).first;
}

String _initials(Object? value) {
  final parts =
      value
          ?.toString()
          .trim()
          .split(RegExp(r'\s+'))
          .where((e) => e.isNotEmpty)
          .toList() ??
      const [];
  if (parts.isEmpty) return 'EA';
  return parts.take(2).map((e) => e[0].toUpperCase()).join();
}

String _date(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed == null
      ? 'DATE TBA'
      : DateFormat('MMM d').format(parsed.toLocal()).toUpperCase();
}

String _dateLong(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed == null
      ? 'Date and time TBA'
      : DateFormat('EEE, MMM d • h:mm a').format(parsed.toLocal());
}

String _time(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed == null ? 'TBA' : DateFormat('h:mm a').format(parsed.toLocal());
}

Color _statusColor(String? status) {
  final value = status?.toLowerCase() ?? '';
  if (['valid', 'paid', 'completed', 'approved'].any(value.contains)) {
    return AppColors.success;
  }
  if (['cancel', 'declin', 'revoke', 'failed', 'expired'].any(value.contains)) {
    return Colors.red.shade700;
  }
  return AppColors.coralDark;
}
