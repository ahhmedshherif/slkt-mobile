import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class TicketPrivacyGuard {
  static const _channel = MethodChannel('tkts/security');
  static int _activeViews = 0;

  static Future<void> enable() async {
    _activeViews++;
    if (_activeViews == 1) await _set(enabled: true);
  }

  static Future<void> disable() async {
    if (_activeViews > 0) _activeViews--;
    if (_activeViews == 0) await _set(enabled: false);
  }

  static Future<void> _set({required bool enabled}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'enabled': enabled});
    } on PlatformException {
      // Ticket display remains usable if a device cannot apply FLAG_SECURE.
    } on MissingPluginException {
      // Hot reload may briefly retain the previous native activity instance.
    }
  }
}
