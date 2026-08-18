import 'dart:async';

import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'session_controller.dart';

class PushNotifications {
  PushNotifications(this.session);

  static const appId = String.fromEnvironment('ONESIGNAL_APP_ID');

  final SessionController session;
  String? identifiedUser;
  bool initialized = false;
  bool permissionRequested = false;

  Future<void> initialize() async {
    if (appId.trim().isEmpty) return;
    try {
      await OneSignal.initialize(appId.trim());
      OneSignal.Notifications.addClickListener(_handleClick);
      session.addListener(_handleSessionChanged);
      initialized = true;
      await _syncIdentity();
    } catch (_) {
      // Push setup must never block login or app startup.
    }
  }

  void _handleSessionChanged() => unawaited(_syncIdentity());

  Future<void> _syncIdentity() async {
    if (!initialized) return;
    final userId = session.isBuyer ? session.user['id']?.toString() : null;
    final externalId = userId == null || userId.isEmpty
        ? null
        : 'buyer-$userId';
    if (externalId == identifiedUser) return;

    try {
      if (externalId == null) {
        await OneSignal.logout();
      } else {
        await OneSignal.login(externalId);
        if (!permissionRequested) {
          permissionRequested = true;
          await OneSignal.Notifications.requestPermission(false);
        }
      }
      identifiedUser = externalId;
    } catch (_) {
      // The API and ticket wallet remain usable if push is unavailable.
    }
  }

  void _handleClick(OSNotificationClickEvent event) {
    final raw = event.notification.additionalData ?? const <String, dynamic>{};
    final nested = raw['custom_data'];
    final data = <String, dynamic>{
      ...raw,
      if (nested is Map) ...Map<String, dynamic>.from(nested),
    };
    final action = data['action']?.toString().toLowerCase();
    session.requestBuyerDestination(
      action == 'orders'
          ? 'orders'
          : action == 'transfers'
          ? 'transfers'
          : 'tickets',
    );
  }
}
