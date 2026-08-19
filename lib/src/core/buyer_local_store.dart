import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class BuyerLocalStore {
  static const _secure = FlutterSecureStorage();
  static const _ticketsKey = 'tkts_offline_tickets_v1';
  static const _favoritesKey = 'tkts_favorite_events_v1';
  static const _recentKey = 'tkts_recent_events_v1';
  static const _notificationPreferencesKey = 'tkts_notification_preferences_v1';

  static String _cartKey(String slug) => 'tkts_cart_v1_$slug';

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
