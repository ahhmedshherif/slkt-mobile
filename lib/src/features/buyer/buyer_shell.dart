import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
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
    setState(() => index = destination == 'orders' ? 3 : 2);
    _refreshCommerce();
    if (destination == 'transfers') {
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
    setState(() => index = action == 'orders' ? 3 : 2);
    if (action == 'transfers') {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ticketsKey.currentState?.showTab(1),
      );
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
  });
  final ApiClient api;
  final SessionController session;
  final VoidCallback explore;
  final VoidCallback purchaseCompleted;
  final ValueListenable<int> unreadNotifications;
  final VoidCallback openNotifications;
  final VoidCallback openTickets;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<Map<String, dynamic>> future = _load();

  Future<Map<String, dynamic>> _load() async {
    final events = await widget.api.get(
      '/mobile/events',
      query: {'per_page': 12},
    );
    Map<String, dynamic> tickets = const {};
    try {
      tickets = await widget.api.get('/buyer/tickets', audience: 'buyer');
    } catch (_) {}
    return {
      'events': events['data'] ?? [],
      'tickets': tickets['tickets'] ?? [],
    };
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: RefreshIndicator(
      onRefresh: () async => setState(() => future = _load()),
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
            builder: (context, raw) {
              final data = Map<String, dynamic>.from(raw as Map);
              final events = List<Map<String, dynamic>>.from(
                (data['events'] as List).map(
                  (e) => Map<String, dynamic>.from(e as Map),
                ),
              );
              final tickets = List<Map<String, dynamic>>.from(
                (data['tickets'] as List).map(
                  (e) => Map<String, dynamic>.from(e as Map),
                ),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _QuickSummary(events: events, tickets: tickets),
                  const SizedBox(height: 28),
                  SectionTitle(
                    title: 'Hot right now',
                    action: 'View all',
                    onTap: widget.explore,
                  ),
                  const SizedBox(height: 14),
                  if (events.isEmpty)
                    const EmptyState(
                      icon: Icons.event_busy_rounded,
                      title: 'Events are on the way',
                      message: 'Approved upcoming events will appear here.',
                    )
                  else
                    ...events
                        .take(4)
                        .map(
                          (event) => Padding(
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
                          ),
                        ),
                ],
              );
            },
          ),
        ],
      ),
    ),
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
  String? category;
  late Future<Map<String, dynamic>> categories = widget.api.get(
    '/mobile/categories',
  );

  Future<Map<String, dynamic>> _events() => widget.api.get(
    '/mobile/events',
    query: {
      if (query.isNotEmpty) 'search': query,
      if (category != null) 'category': category,
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
        const SizedBox(height: 16),
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
                    selected: category == null,
                    onSelected: (_) => setState(() => category = null),
                  ),
                  const SizedBox(width: 8),
                  ...items.map((raw) {
                    final item = Map<String, dynamic>.from(raw as Map);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(item['name'].toString()),
                        selected: category == item['slug'],
                        onSelected: (_) =>
                            setState(() => category = item['slug'].toString()),
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
          key: ValueKey('$query-$category'),
          future: _events(),
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
}

class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, required this.onTap});
  final Map<String, dynamic> event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
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
                        _date(event['starts_at']),
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

      return Scaffold(
        backgroundColor: AppColors.canvas,
        bottomNavigationBar:
            !eventEnded &&
                (event['ticket_types'] as List? ?? const []).isNotEmpty
            ? _EventCheckoutBar(event: event, onPressed: () => _openCart(event))
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
                                title: _dateLong(event['starts_at']),
                                subtitle: event['door_opens_at_note']
                                    ?.toString(),
                              ),
                              const SizedBox(height: 16),
                              DetailRow(
                                icon: Icons.location_on_rounded,
                                title:
                                    event['venue']?['name']?.toString() ??
                                    'Venue TBA',
                                subtitle: event['venue']?['address']
                                    ?.toString(),
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
                            else if ((event['ticket_types'] as List? ??
                                    const [])
                                .isEmpty)
                              const EmptyState(
                                icon: Icons.event_seat_rounded,
                                title: 'Tickets coming soon',
                                message:
                                    'Ticket types will appear here when sales open.',
                              )
                            else
                              ...(event['ticket_types'] as List).map(
                                (raw) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: TicketTier(
                                    type: Map<String, dynamic>.from(raw as Map),
                                    currency:
                                        event['currency']?.toString() ?? 'EGP',
                                    onBuy: () => _openCart(
                                      event,
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

  Future<void> _showCheckoutResult(
    CheckoutCompletion result,
  ) => showModalBottomSheet<void>(
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
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: paid ? const Color(0xFFE1F7EE) : const Color(0xFFFFF6C9),
                shape: BoxShape.circle,
              ),
              child: Icon(
                paid ? Icons.verified_rounded : Icons.schedule_rounded,
                color: paid ? AppColors.success : AppColors.coralDark,
                size: 40,
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
      if (mounted) setState(() => future = _load());
    } catch (error) {
      if (mounted) setState(() => this.error = errorMessage(error));
    } finally {
      if (mounted) setState(() => markingRead = false);
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
            child: RefreshIndicator(
              onRefresh: () async => setState(() => future = _load()),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                children: [
                  AsyncPanel(
                    future: future,
                    builder: (context, response) {
                      final items = response['data'] as List? ?? const [];
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
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Card(
                              color: unread
                                  ? const Color(0xFFFFF6C9)
                                  : AppColors.paper,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(28),
                                onTap: action == null
                                    ? null
                                    : () => Navigator.pop(context, action),
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
                                              item['message']?.toString() ?? '',
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
                                      if (action != null)
                                        const Icon(Icons.chevron_right_rounded),
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
          ),
        ],
      ),
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
  late Future<Map<String, dynamic>> tickets = widget.api.get(
    '/buyer/tickets',
    audience: 'buyer',
  );
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
      tickets = widget.api.get('/buyer/tickets', audience: 'buyer');
      transfers = widget.api.get('/buyer/transfers', audience: 'buyer');
    });
  }

  void showTab(int index) {
    if (!mounted || index < 0 || index >= tabs.length) return;
    tabs.animateTo(index);
    _reload();
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
              RefreshIndicator(
                onRefresh: () async => setState(
                  () => tickets = widget.api.get(
                    '/buyer/tickets',
                    audience: 'buyer',
                  ),
                ),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
                  children: [
                    AsyncPanel(
                      future: tickets,
                      builder: (context, response) {
                        final items = response['tickets'] as List? ?? const [];
                        if (items.isEmpty) {
                          return const EmptyState(
                            icon: Icons.local_activity_outlined,
                            title: 'No tickets yet',
                            message:
                                'Tickets appear here as soon as an order is paid.',
                          );
                        }
                        return Column(
                          children: items.map((raw) {
                            final ticket = Map<String, dynamic>.from(
                              raw as Map,
                            );
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: WalletTicketCard(
                                ticket: ticket,
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
                                    tickets = widget.api.get(
                                      '/buyer/tickets',
                                      audience: 'buyer',
                                    );
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
              RefreshIndicator(
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
}

class WalletTicketCard extends StatelessWidget {
  const WalletTicketCard({
    super.key,
    required this.ticket,
    required this.onTap,
  });
  final Map<String, dynamic> ticket;
  final VoidCallback onTap;

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
                      const Icon(
                        Icons.qr_code_2_rounded,
                        color: Colors.white,
                        size: 32,
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
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: ticket['qr_raw']?.toString() ?? '',
                  size: 230,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
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
              decoration: const InputDecoration(
                labelText: 'Account code, email or mobile',
                prefixIcon: Icon(Icons.person_search_rounded),
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
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.coral,
                    child: Icon(Icons.person_rounded, color: Colors.white),
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

  Future<void> _send() async {
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
    child: RefreshIndicator(
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

  void _reload() => setState(() => future = _load());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Order details')),
    body: RefreshIndicator(
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
            const ProfileTile(
              icon: Icons.language_rounded,
              title: 'Language',
              subtitle: 'English • Arabic ready',
            ),
            const ProfileTile(
              icon: Icons.support_agent_rounded,
              title: 'Help & support',
              subtitle: 'Contact the TKTS APP team',
            ),
            ProfileTile(
              onTap: () => _changePassword(context),
              icon: Icons.lock_reset_rounded,
              title: 'Change password',
              subtitle: 'Current password required',
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
    final name = TextEditingController(text: session.user['name']?.toString());
    final nextName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change your name'),
        content: TextField(
          controller: name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Full name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, name.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    name.dispose();
    if (nextName == null || nextName.isEmpty || !context.mounted) return;

    final password = TextEditingController();
    final currentPassword = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.shield_outlined, color: AppColors.coralDark),
        title: const Text('Confirm it is you'),
        content: TextField(
          controller: password,
          autofocus: true,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(labelText: 'Current password'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, password.text),
            child: const Text('Confirm & change'),
          ),
        ],
      ),
    );
    password.dispose();
    if (currentPassword == null ||
        currentPassword.isEmpty ||
        !context.mounted) {
      return;
    }
    try {
      await api.patch(
        '/buyer/profile',
        audience: 'buyer',
        data: {'name': nextName, 'current_password': currentPassword},
      );
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
    final current = TextEditingController();
    final password = TextEditingController();
    final confirmation = TextEditingController();
    final submit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          20,
          22,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
        ),
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
              'Change password',
              style: Theme.of(sheetContext).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Use at least 8 characters with uppercase, lowercase, number and symbol.',
              style: TextStyle(color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmation,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(sheetContext, true),
              child: const Text('Change password'),
            ),
          ],
        ),
      ),
    );
    if (submit != true || !context.mounted) {
      current.dispose();
      password.dispose();
      confirmation.dispose();
      return;
    }
    try {
      await api.post(
        '/buyer/profile/password',
        audience: 'buyer',
        data: {
          'current_password': current.text,
          'password': password.text,
          'password_confirmation': confirmation.text,
        },
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed successfully.')),
        );
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    } finally {
      current.dispose();
      password.dispose();
      confirmation.dispose();
    }
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
  });
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Row(
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
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    ],
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

void _openEvent(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> event,
  VoidCallback onPurchaseCompleted,
  VoidCallback openTickets,
) => Navigator.push(
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

String _eventHeroTag(Map<String, dynamic> event) =>
    'slkt-event-banner-${event['slug'] ?? event['id'] ?? event['name']}';

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
