import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/session_controller.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class StaffShell extends StatefulWidget {
  const StaffShell({super.key, required this.api, required this.session});
  final ApiClient api;
  final SessionController session;

  @override
  State<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends State<StaffShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      OperationsDashboard(api: widget.api, session: widget.session),
      OperationsEvents(api: widget.api),
      OperationsScanner(api: widget.api),
      OperationsWorkspace(api: widget.api, admin: widget.session.isAdmin),
      OperationsProfile(session: widget.session),
    ];
    return AnnotatedRegion(
      value: AppSystemUi.dark,
      child: Scaffold(
        extendBody: true,
        body: AnimatedIndexedStack(index: index, children: pages),
        bottomNavigationBar: SlktNavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              label: 'Overview',
            ),
            const NavigationDestination(
              icon: Icon(Icons.event_outlined),
              label: 'Events',
            ),
            const NavigationDestination(
              icon: Icon(Icons.qr_code_scanner_rounded),
              label: 'Scan',
            ),
            NavigationDestination(
              icon: Icon(
                widget.session.isAdmin
                    ? Icons.admin_panel_settings_outlined
                    : Icons.groups_outlined,
              ),
              label: widget.session.isAdmin ? 'Admin' : 'Team',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }
}

class OperationsDashboard extends StatefulWidget {
  const OperationsDashboard({
    super.key,
    required this.api,
    required this.session,
  });
  final ApiClient api;
  final SessionController session;

  @override
  State<OperationsDashboard> createState() => _OperationsDashboardState();
}

class _OperationsDashboardState extends State<OperationsDashboard> {
  late Future<Map<String, dynamic>> future = _load();

  Future<Map<String, dynamic>> _load() => widget.api.get(
    widget.session.isAdmin
        ? '/mobile/admin/dashboard'
        : '/mobile/staff/dashboard',
    audience: 'staff',
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: RefreshIndicator(
      onRefresh: () async => setState(() => future = _load()),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        children: [
          const BrandMark(),
          const SizedBox(height: 28),
          PageHeading(
            'Operations center',
            subtitle:
                'Good to see you, ${widget.session.user['name'] ?? 'team member'}.',
          ),
          const SizedBox(height: 22),
          AsyncPanel(
            future: future,
            builder: (context, response) {
              final data = Map<String, dynamic>.from(response['data'] as Map);
              final metrics = data.entries
                  .where(
                    (entry) =>
                        entry.value is num && entry.key != 'organizer_id',
                  )
                  .toList();
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.22,
                ),
                itemCount: metrics.length,
                itemBuilder: (_, index) => MetricCard(
                  label: metrics[index].key.replaceAll('_', ' '),
                  value: metrics[index].value.toString(),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE8DE),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.insights_rounded,
              size: 20,
              color: AppColors.coralDark,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    ),
  );
}

class OperationsEvents extends StatefulWidget {
  const OperationsEvents({super.key, required this.api});
  final ApiClient api;

  @override
  State<OperationsEvents> createState() => _OperationsEventsState();
}

class _OperationsEventsState extends State<OperationsEvents> {
  late Future<Map<String, dynamic>> future = widget.api.get(
    '/mobile/staff/events',
    audience: 'staff',
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: RefreshIndicator(
      onRefresh: () async => setState(
        () =>
            future = widget.api.get('/mobile/staff/events', audience: 'staff'),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
        children: [
          const PageHeading(
            'Assigned events',
            subtitle: 'Only the events permitted for this account.',
          ),
          const SizedBox(height: 22),
          AsyncPanel(
            future: future,
            builder: (context, response) {
              final events = response['data'] as List? ?? const [];
              if (events.isEmpty) {
                return const EmptyState(
                  icon: Icons.event_busy_rounded,
                  title: 'No event assignments',
                  message:
                      'The organizer owner can assign this account to events.',
                );
              }
              return Column(
                children: events.map((raw) {
                  final event = Map<String, dynamic>.from(raw as Map);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(17),
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFFE8DE),
                        child: Icon(
                          Icons.event_available_rounded,
                          color: AppColors.coralDark,
                        ),
                      ),
                      title: Text(
                        event['name']?.toString() ?? 'Event',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        event['venue']?['name']?.toString() ?? 'Venue TBA',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EventOperationsDetail(
                            api: widget.api,
                            eventId: event['id'],
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

class EventOperationsDetail extends StatelessWidget {
  const EventOperationsDetail({
    super.key,
    required this.api,
    required this.eventId,
  });
  final ApiClient api;
  final Object? eventId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Event operations')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AsyncPanel(
          future: api.get('/mobile/staff/events/$eventId', audience: 'staff'),
          builder: (context, response) {
            final event = Map<String, dynamic>.from(response['data'] as Map);
            final permissions = Map<String, dynamic>.from(
              event['permissions'] as Map? ?? const {},
            );
            final analytics = Map<String, dynamic>.from(
              event['analytics'] as Map? ?? const {},
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event['name']?.toString() ?? 'Event',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  event['venue']?['name']?.toString() ?? 'Venue TBA',
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: permissions.entries
                      .where((e) => e.value == true)
                      .map((e) => Chip(label: Text(e.key.toUpperCase())))
                      .toList(),
                ),
                if (analytics.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.25,
                    children: analytics.entries
                        .map(
                          (e) => MetricCard(
                            label: e.key.replaceAll('_', ' '),
                            value: e.value.toString(),
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (permissions['analytics'] == true) ...[
                  const SizedBox(height: 20),
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AttendeesScreen(api: api, eventId: eventId),
                      ),
                    ),
                    icon: const Icon(Icons.people_rounded),
                    label: const Text('View attendee list'),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    ),
  );
}

class AttendeesScreen extends StatelessWidget {
  const AttendeesScreen({super.key, required this.api, required this.eventId});
  final ApiClient api;
  final Object? eventId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Attendees')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AsyncPanel(
          future: api.get(
            '/mobile/staff/events/$eventId/attendees',
            audience: 'staff',
          ),
          builder: (_, response) {
            final items = response['data'] as List? ?? const [];
            if (items.isEmpty) {
              return const EmptyState(
                icon: Icons.people_outline_rounded,
                title: 'No attendees yet',
                message: 'Paid ticket holders will appear here.',
              );
            }
            return Column(
              children: items.map((raw) {
                final item = Map<String, dynamic>.from(raw as Map);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text(
                      item['holder_name']?.toString() ?? 'Ticket holder',
                    ),
                    subtitle: Text(
                      '${item['ticket_type'] ?? 'Ticket'} • ${item['gate'] ?? 'Gate TBA'}',
                    ),
                    trailing: Text(item['status']?.toString() ?? 'valid'),
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

class OperationsScanner extends StatefulWidget {
  const OperationsScanner({super.key, required this.api});
  final ApiClient api;

  @override
  State<OperationsScanner> createState() => _OperationsScannerState();
}

class _OperationsScannerState extends State<OperationsScanner> {
  final camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  List<Map<String, dynamic>> events = const [];
  List<Map<String, dynamic>> devices = const [];
  Map<String, dynamic>? event;
  Map<String, dynamic>? device;
  String action = 'checkin';
  bool loading = true;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void dispose() {
    camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
      children: [
        const PageHeading(
          'Ticket scanner',
          subtitle: 'Select an event and validate its current QR.',
        ),
        const SizedBox(height: 18),
        if (loading)
          const SkeletonList(count: 2)
        else ...[
          DropdownButtonFormField<Map<String, dynamic>>(
            initialValue: event,
            decoration: const InputDecoration(labelText: 'Event'),
            items: events
                .map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Text(item['name'].toString()),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                event = value;
                device = null;
              });
              _loadDevices();
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Map<String, dynamic>>(
            initialValue: device,
            decoration: const InputDecoration(labelText: 'Scanner device'),
            items: devices
                .map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Text(
                      item['label']?.toString() ?? 'Scanner ${item['id']}',
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => device = value),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'validate', label: Text('Validate')),
              ButtonSegment(value: 'checkin', label: Text('Check in')),
              ButtonSegment(value: 'checkout', label: Text('Exit')),
            ],
            selected: {action},
            onSelectionChanged: (value) => setState(() => action = value.first),
          ),
          const SizedBox(height: 18),
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (event != null && device != null)
                    MobileScanner(controller: camera, onDetect: _detect)
                  else
                    Container(
                      color: AppColors.navy,
                      child: const Center(
                        child: Text(
                          'Select an event and scanner',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  IgnorePointer(
                    child: Container(
                      margin: const EdgeInsets.all(48),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                  if (sending)
                    const ColoredBox(
                      color: Color(0x66000000),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.coral,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Future<void> _loadEvents() async {
    try {
      final response = await widget.api.get(
        '/mobile/staff/events',
        audience: 'staff',
      );
      events = List<Map<String, dynamic>>.from(
        (response['data'] as List? ?? const []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
      if (events.isNotEmpty) event = events.first;
      await _loadDevices();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadDevices() async {
    if (event == null) return;
    try {
      final response = await widget.api.get(
        '/mobile/staff/events/${event!['id']}/scanners',
        audience: 'staff',
      );
      devices = List<Map<String, dynamic>>.from(
        (response['data'] as List? ?? const [])
            .where((e) => e['active'] == true)
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );
      device = devices.isEmpty ? null : devices.first;
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _detect(BarcodeCapture capture) async {
    if (sending ||
        event == null ||
        device == null ||
        capture.barcodes.isEmpty) {
      return;
    }
    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;
    setState(() => sending = true);
    await camera.stop();
    try {
      final response = await widget.api.post(
        '/mobile/staff/events/${event!['id']}/scan',
        audience: 'staff',
        data: {
          'scanner_device_id': device!['id'],
          'action': action,
          'qr_raw': raw,
          'idempotency_key': const Uuid().v4(),
        },
      );
      if (!mounted) return;
      final result = Map<String, dynamic>.from(
        response['data'] as Map? ?? const {},
      );
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: Icon(
            result['success'] == false
                ? Icons.cancel_rounded
                : Icons.check_circle_rounded,
            color: result['success'] == false ? Colors.red : AppColors.success,
            size: 54,
          ),
          title: Text(
            result['status']?.toString().replaceAll('_', ' ') ??
                'Scan complete',
          ),
          content: Text(
            result['message']?.toString() ?? 'The server recorded this scan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Scan next'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => sending = false);
      await camera.start();
    }
  }
}

class OperationsWorkspace extends StatelessWidget {
  const OperationsWorkspace({
    super.key,
    required this.api,
    required this.admin,
  });
  final ApiClient api;
  final bool admin;

  @override
  Widget build(BuildContext context) {
    final future = api.get(
      admin ? '/mobile/admin/approvals' : '/mobile/staff/team',
      audience: 'staff',
    );
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
        children: [
          PageHeading(
            admin ? 'Admin workspace' : 'Organizer team',
            subtitle: admin
                ? 'Pending events, venues and global controls.'
                : 'Managers, analysts and assigned scanners.',
          ),
          const SizedBox(height: 22),
          AsyncPanel(
            future: future,
            builder: (_, response) {
              final List items;
              if (admin) {
                final data = Map<String, dynamic>.from(response['data'] as Map);
                items = [
                  ...(data['events'] as List? ?? const []),
                  ...(data['venues'] as List? ?? const []),
                ];
              } else {
                items = response['data'] as List? ?? const [];
              }
              if (items.isEmpty) {
                return EmptyState(
                  icon: admin ? Icons.verified_rounded : Icons.groups_outlined,
                  title: admin
                      ? 'Approval queue is clear'
                      : 'No team members yet',
                  message: admin
                      ? 'New organizer submissions appear here.'
                      : 'Create and assign staff from the organizer dashboard.',
                );
              }
              return Column(
                children: items.map((raw) {
                  final item = Map<String, dynamic>.from(raw as Map);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(
                          admin ? Icons.approval_rounded : Icons.badge_outlined,
                        ),
                      ),
                      title: Text(
                        admin
                            ? item['name']?.toString() ?? 'Submission'
                            : item['user']?['name']?.toString() ??
                                  'Team member',
                      ),
                      subtitle: Text(
                        admin
                            ? item['status']?.toString() ?? 'pending approval'
                            : '${item['role'] ?? 'staff'} • ${(item['events'] as List? ?? const []).length} events',
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
}

class OperationsProfile extends StatelessWidget {
  const OperationsProfile({super.key, required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
      children: [
        const PageHeading(
          'Operations account',
          subtitle: 'Role and secure session settings.',
        ),
        const SizedBox(height: 22),
        Card(
          color: AppColors.navy,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.user['name']?.toString() ?? 'Staff member',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  session.user['email']?.toString() ?? '',
                  style: const TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 14),
                Text(
                  (session.user['staff_role'] ??
                          session.user['role'] ??
                          'staff')
                      .toString()
                      .toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF69E6C0),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
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
  );
}
