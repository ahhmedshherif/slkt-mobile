import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class BuyerLocalStore {
  static const _secure = FlutterSecureStorage();
  static const _ticketsKey = 'tkts_offline_tickets_v1';
  static const _ordersKey = 'tkts_offline_orders_v1';
  static const _homeKey = 'tkts_offline_home_v1';
  static const _exploreKey = 'tkts_offline_explore_v1';
  static const _pendingCheckoutKey = 'tkts_pending_checkout_v1';
  static const _favoritesKey = 'tkts_favorite_events_v1';
  static const _recentKey = 'tkts_recent_events_v1';
  static const _notificationPreferencesKey = 'tkts_notification_preferences_v1';

  static String _cartKey(String slug) => 'tkts_cart_v1_$slug';
  static String _checkoutAttemptKey(String slug) =>
      'tkts_checkout_attempt_v1_$slug';

  static Future<Map<String, dynamic>?> cart(String slug) async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeMap(prefs.getString(_cartKey(slug)));
  }

  static Future<void> saveCart(
    String slug, {
    required Map<String, int> quantities,
    required String promo,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (quantities.isEmpty && promo.isEmpty) {
      await prefs.remove(_cartKey(slug));
      return;
    }
    await prefs.setString(
      _cartKey(slug),
      jsonEncode({
        'quantities': quantities,
        'promo': promo,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  static Future<void> clearCart(String slug) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cartKey(slug));
  }

  static Future<void> cacheTickets(List<Object?> tickets) => _secure.write(
    key: _ticketsKey,
    value: jsonEncode({
      'tickets': tickets,
      'cached_at': DateTime.now().toUtc().toIso8601String(),
    }),
  );

  static Future<Map<String, dynamic>?> cachedTickets() async =>
      _decodeMap(await _secure.read(key: _ticketsKey));

  static Future<void> cacheOrders(Map<String, dynamic> response) =>
      _secure.write(
        key: _ordersKey,
        value: jsonEncode({
          ...response,
          'cached_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );

  static Future<Map<String, dynamic>?> cachedOrders() async =>
      _decodeMap(await _secure.read(key: _ordersKey));

  static Future<void> cacheHome(Map<String, dynamic> response) => _secure.write(
    key: _homeKey,
    value: jsonEncode({
      ...response,
      'cached_at': DateTime.now().toUtc().toIso8601String(),
    }),
  );

  static Future<Map<String, dynamic>?> cachedHome() async =>
      _decodeMap(await _secure.read(key: _homeKey));

  static Future<void> cacheExplore(Map<String, dynamic> response) =>
      _secure.write(
        key: _exploreKey,
        value: jsonEncode({
          ...response,
          'cached_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );

  static Future<Map<String, dynamic>?> cachedExplore() async =>
      _decodeMap(await _secure.read(key: _exploreKey));

  static Future<void> savePendingCheckout(Map<String, dynamic> checkout) =>
      _secure.write(key: _pendingCheckoutKey, value: jsonEncode(checkout));

  static Future<Map<String, dynamic>?> pendingCheckout() async =>
      _decodeMap(await _secure.read(key: _pendingCheckoutKey));

  static Future<void> clearPendingCheckout() =>
      _secure.delete(key: _pendingCheckoutKey);

  static Future<String?> checkoutAttempt(String slug) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_checkoutAttemptKey(slug));
  }

  static Future<void> saveCheckoutAttempt(String slug, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_checkoutAttemptKey(slug), value);
  }

  static Future<void> clearCheckoutAttempt(String slug) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_checkoutAttemptKey(slug));
  }

  static Future<void> clearPrivateData() async {
    await Future.wait([
      _secure.delete(key: _ticketsKey),
      _secure.delete(key: _ordersKey),
      _secure.delete(key: _homeKey),
      _secure.delete(key: _exploreKey),
      _secure.delete(key: _pendingCheckoutKey),
    ]);
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where(
      (key) =>
          key.startsWith('tkts_cart_v1_') ||
          key.startsWith('tkts_checkout_attempt_v1_'),
    )) {
      await prefs.remove(key);
    }
  }

  static Future<Set<String>> favorites() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_favoritesKey)?.toSet() ?? <String>{};
  }

  static Future<bool> toggleFavorite(String slug) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_favoritesKey)?.toSet() ?? <String>{};
    final selected = values.contains(slug);
    selected ? values.remove(slug) : values.add(slug);
    await prefs.setStringList(_favoritesKey, values.toList());
    return !selected;
  }

  static Future<void> rememberEvent(Map<String, dynamic> event) async {
    final prefs = await SharedPreferences.getInstance();
    final current = recentEvents();
    final values = await current;
    final slug = event['slug']?.toString();
    if (slug == null || slug.isEmpty) return;
    values.removeWhere((value) => value['slug']?.toString() == slug);
    values.insert(0, event);
    await prefs.setString(_recentKey, jsonEncode(values.take(10).toList()));
  }

  static Future<List<Map<String, dynamic>>> recentEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, bool>> notificationPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _decodeMap(prefs.getString(_notificationPreferencesKey));
    return {
      'orders': raw?['orders'] as bool? ?? true,
      'payments': raw?['payments'] as bool? ?? true,
      'transfers': raw?['transfers'] as bool? ?? true,
      'promotions': raw?['promotions'] as bool? ?? true,
    };
  }

  static Future<void> saveNotificationPreferences(
    Map<String, bool> values,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_notificationPreferencesKey, jsonEncode(values));
  }

  static Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }
}
