import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evnts_app/src/core/api_client.dart';
import 'package:evnts_app/src/core/session_controller.dart';
import 'package:evnts_app/src/core/theme.dart';
import 'package:evnts_app/src/features/auth/auth_screen.dart';
import 'package:evnts_app/src/app.dart';
import 'package:evnts_app/src/features/buyer/buyer_shell.dart';
import 'package:evnts_app/src/features/buyer/checkout_flow.dart';
import 'package:evnts_app/src/widgets/common.dart';

void main() {
  testWidgets('Flutter test environment is ready', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('TKTS APP')));
    expect(find.text('TKTS APP'), findsOneWidget);
  });

  testWidgets('cinematic splash renders TKTS APP brand sequence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildTheme(), home: const SplashScreen()),
    );
    await tester.pump(const Duration(milliseconds: 1800));

    expect(find.text('SELECT SMART. ENTER SMOOTH.'), findsOneWidget);
    for (var index = 0; index < 7; index++) {
      expect(find.byKey(ValueKey('splash-letter-$index')), findsWidgets);
    }
  });

  testWidgets('brand mark renders the black TKTS APP wordmark', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BrandMark())),
    );

    expect(
      find.image(
        const AssetImage('assets/brand/tkts-wordmark-transparent.png'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tab transition fully fades the previous page', (tester) async {
    var index = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return AnimatedIndexedStack(
              index: index,
              children: const [
                ColoredBox(key: ValueKey('page-0'), color: Colors.red),
                ColoredBox(key: ValueKey('page-1'), color: Colors.blue),
              ],
            );
          },
        ),
      ),
    );

    update(() => index = 1);
    await tester.pumpAndSettle();

    final oldPageOpacity = find.ancestor(
      of: find.byKey(const ValueKey('page-0')),
      matching: find.byType(AnimatedOpacity),
    );
    final render = tester.renderObject<RenderAnimatedOpacity>(oldPageOpacity);
    expect(render.opacity.value, 0);
  });

  testWidgets('event checkout exposes all ticket tiers in a cart', (
    tester,
  ) async {
    final api = _FakeCheckoutApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: EventDetailScreen(
          api: api,
          slug: api.event['slug'].toString(),
          preview: api.event,
          onPurchaseCompleted: () {},
          openTickets: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose tickets'));
    await tester.pumpAndSettle();

    expect(find.text('Platinum'), findsWidgets);
    expect(find.text('Gold'), findsWidgets);
    expect(find.text('Silver'), findsWidgets);
    expect(find.byKey(const ValueKey('empty-cart')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final payButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('create-order-and-pay')),
    );
    expect(payButton.onPressed, isNotNull);
    expect(find.text('Create order & pay 570 EGP'), findsOneWidget);
  });

  test('payment redirect only accepts the trusted SLKT return URL', () {
    const path = '/checkout/42/success';
    expect(
      isCheckoutReturnUrl('https://slktegy.com$path?success=true', path),
      isTrue,
    );
    expect(
      isCheckoutReturnUrl('https://evil.example$path?success=true', path),
      isFalse,
    );
    expect(
      isCheckoutReturnUrl('http://slktegy.com$path?success=true', path),
      isFalse,
    );
  });

  test('payment sheet accepts only an HTTPS Paymob checkout URL', () {
    expect(
      isTrustedPaymobCheckoutUrl(
        Uri.parse('https://accept.paymob.com/unifiedcheckout/?clientSecret=x'),
      ),
      isTrue,
    );
    expect(
      isTrustedPaymobCheckoutUrl(
        Uri.parse('https://evilpaymob.com/unifiedcheckout/?clientSecret=x'),
      ),
      isFalse,
    );
    expect(
      isTrustedPaymobCheckoutUrl(
        Uri.parse('http://accept.paymob.com/unifiedcheckout/?clientSecret=x'),
      ),
      isFalse,
    );
  });

  testWidgets('SLKT navigation keeps selected and unselected items readable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          bottomNavigationBar: SlktNavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );

    final material = tester.widget<Material>(
      find.byKey(const ValueKey('slkt-glass-navigation')),
    );
    expect(material.color, const Color(0xD90B0B0D));
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('new phone signup requires all account fields', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: CompletePhoneSignupScreen(
          api: ApiClient(),
          phone: '01000000020',
          registrationToken: 'temporary-token',
        ),
      ),
    );

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.text('Create account & continue'), findsOneWidget);
  });

  testWidgets('buyer app has no organizer staff or admin sign in', (
    tester,
  ) async {
    final api = ApiClient();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AuthScreen(api: api, session: SessionController(api)),
      ),
    );

    expect(find.textContaining('Organizer'), findsNothing);
    expect(find.textContaining('staff'), findsNothing);
    expect(find.textContaining('admin'), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('auth edge swipe returns to the previous auth screen', (
    tester,
  ) async {
    final api = ApiClient();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AuthScreen(api: api, session: SessionController(api)),
      ),
    );

    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);

    await tester.dragFrom(const Offset(2, 360), const Offset(110, 0));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Create your account'), findsNothing);
  });

  test('ticket links accept only the trusted SLKT destinations', () {
    expect(isTicketsAppLink(Uri.parse('https://slktegy.com/tickets')), isTrue);
    expect(
      isTicketsAppLink(Uri.parse('https://slktegy.com/tickets/order')),
      isTrue,
    );
    expect(isTicketsAppLink(Uri.parse('slkt://tickets')), isTrue);
    expect(
      isTicketsAppLink(Uri.parse('https://evil.example/tickets')),
      isFalse,
    );
    expect(isTicketsAppLink(Uri.parse('http://slktegy.com/tickets')), isFalse);
  });

  test('system bars are transparent for edge-to-edge rendering', () {
    expect(AppSystemUi.light.statusBarColor, Colors.transparent);
    expect(AppSystemUi.dark.statusBarColor, Colors.transparent);
    expect(AppSystemUi.light.systemNavigationBarColor, Colors.transparent);
    expect(AppSystemUi.dark.systemNavigationBarColor, Colors.transparent);
  });

  testWidgets('authenticator challenge uses six boxes and has no SMS resend', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: OtpScreen(
          phone: '',
          title: 'Security verification',
          subtitle: 'Enter the current code from your authenticator app.',
          showResend: false,
          maskPhone: false,
          onVerify: (code) async => <String, dynamic>{},
        ),
      ),
    );

    expect(find.text('Security verification'), findsOneWidget);
    expect(find.byKey(const ValueKey('otp-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('otp-box-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('otp-box-5')), findsOneWidget);
    expect(find.text('Resend code'), findsNothing);
    expect(find.text('Verify & continue'), findsOneWidget);
  });

  testWidgets('OTP auto-submits after the sixth digit', (tester) async {
    final completion = Completer<Map<String, dynamic>>();
    String? submittedCode;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: OtpScreen(
          phone: '01000000020',
          title: 'Verify your phone',
          subtitle: 'Enter the code.',
          onVerify: (code) {
            submittedCode = code;
            return completion.future;
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(const ValueKey('otp-input')), '123456');
    await tester.pump();

    expect(submittedCode, '123456');
    expect(find.text('Checking code...'), findsOneWidget);
    completion.complete(<String, dynamic>{'ok': true});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
  });

  testWidgets('transfer lookup error is rendered inside the transfer sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: TransferSheet(
            api: _FailingTransferApi(),
            ticket: const {'id': 7},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'missing@example.com');
    await tester.tap(find.text('Find registered recipient'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('transfer-error')), findsOneWidget);
    expect(
      find.text('No registered buyer matches these details.'),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('pending order exposes its items and resume action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: OrderDetailScreen(
          api: _FakeOrderApi(),
          order: const {'id': 14},
          openTickets: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inside this order'), findsOneWidget);
    expect(find.text('2×'), findsOneWidget);
    expect(find.text('Platinum'), findsOneWidget);
    expect(find.text('Continue secure payment'), findsOneWidget);
  });
}

class _FakeCheckoutApi extends ApiClient {
  final event = <String, dynamic>{
    'id': 1,
    'slug': 'test-event',
    'name': 'Test Event',
    'currency': 'EGP',
    'starts_at': '2026-08-20T20:00:00+02:00',
    'summary': 'A test event.',
    'venue': {'name': 'SLKT Arena', 'address': 'Cairo'},
    'max_tickets_per_order': 5,
    'ticket_types': [
      {
        'id': 1,
        'name': 'Platinum',
        'price': 500,
        'available': 20,
        'gate_label': 'A',
      },
      {
        'id': 2,
        'name': 'Gold',
        'price': 400,
        'available': 20,
        'gate_label': 'B',
      },
      {
        'id': 3,
        'name': 'Silver',
        'price': 300,
        'available': 20,
        'gate_label': 'C',
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    String? audience,
    Map<String, dynamic>? query,
  }) async => {'data': event};

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    String? audience,
    Object? data,
  }) async {
    if (path.endsWith('/checkout/preview')) {
      return {
        'data': {
          'ticket_count': 1,
          'subtotal': 500,
          'tax': 70,
          'discount': 0,
          'total': 570,
          'currency': 'EGP',
        },
      };
    }
    return const {};
  }
}

class _FailingTransferApi extends ApiClient {
  @override
  Future<Map<String, dynamic>> post(
    String path, {
    String? audience,
    Object? data,
  }) async => throw const ApiException(
    'No registered buyer matches these details.',
    statusCode: 422,
  );
}

class _FakeOrderApi extends ApiClient {
  @override
  Future<Map<String, dynamic>> get(
    String path, {
    String? audience,
    Map<String, dynamic>? query,
  }) async => {
    'data': {
      'id': 14,
      'order_number': 'ORD-TEST14',
      'status': 'pending',
      'total_amount': 1000,
      'currency': 'EGP',
      'created_at': '2026-08-18T20:00:00+02:00',
      'checkout_expires_at': '2026-08-18T20:15:00+02:00',
      'server_time': '2026-08-18T20:02:00+02:00',
      'checkout_url':
          'https://accept.paymob.com/unifiedcheckout/?publicKey=test&clientSecret=test',
      'redirect_path': '/checkout/14/success',
      'can_resume_payment': true,
      'event': {'name': 'TKTS Live'},
      'items': [
        {
          'name': 'Platinum',
          'quantity': 2,
          'unit_price': 500,
          'currency': 'EGP',
        },
      ],
      'tickets': [],
    },
  };
}
