import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app.dart';
import 'src/core/api_client.dart';
import 'src/core/session_controller.dart';
import 'src/core/push_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  final api = ApiClient();
  final session = SessionController(api);
  final pushNotifications = PushNotifications(session);
  // iOS must configure the OneSignal/APNs delegate during launch, before the
  // first Flutter frame. Delaying this until after runApp can cause APNs to
  // time out before the SDK receives the registration callback.
  await pushNotifications.initialize();
  runApp(
    EvntsApp(api: api, session: session, pushNotifications: pushNotifications),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(session.restore());
  });
}
