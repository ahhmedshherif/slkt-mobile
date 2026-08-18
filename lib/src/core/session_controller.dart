import 'package:flutter/foundation.dart';

import 'api_client.dart';

enum SessionKind { guest, buyer }

class SessionController extends ChangeNotifier {
  SessionController(this.api);

  final ApiClient api;
  SessionKind kind = SessionKind.guest;
  Map<String, dynamic> user = const {};
  bool restoring = true;
  String? _requestedBuyerDestination;

  bool get isBuyer => kind == SessionKind.buyer;
  bool get isAdmin => ['admin', 'super_admin'].contains(user['role']);

  Future<void> restore() async {
    restoring = true;
    final buyerToken = await api.tokenFor('buyer');
    if (buyerToken != null) {
      try {
        final response = await api.get('/buyer/profile', audience: 'buyer');
        user = Map<String, dynamic>.from(response['buyer'] as Map? ?? const {});
        kind = SessionKind.buyer;
        restoring = false;
        notifyListeners();
        return;
      } catch (_) {
        await api.clearToken('buyer');
      }
    }
    // This app is buyer-only. Remove tokens left by older app versions.
    await api.clearToken('staff');
    kind = SessionKind.guest;
    restoring = false;
    notifyListeners();
  }

  Future<void> acceptBuyerSession(Map<String, dynamic> response) async {
    await api.saveToken('buyer', response['access_token'].toString());
    user = Map<String, dynamic>.from(response['buyer'] as Map? ?? const {});
    kind = SessionKind.buyer;
    notifyListeners();
  }

  Future<void> refreshBuyer() async {
    final response = await api.get('/buyer/profile', audience: 'buyer');
    user = Map<String, dynamic>.from(response['buyer'] as Map? ?? const {});
    notifyListeners();
  }

  Future<void> logout() async {
    final previous = kind;
    try {
      if (previous == SessionKind.buyer) {
        await api.post('/mobile/buyer/logout', audience: 'buyer');
      }
    } catch (_) {
      // Local logout must always work, even while offline.
    }
    await api.clearToken('buyer');
    await api.clearToken('staff');
    kind = SessionKind.guest;
    user = const {};
    notifyListeners();
  }

  void requestOpenTickets() {
    requestBuyerDestination('tickets');
  }

  void requestBuyerDestination(String destination) {
    _requestedBuyerDestination = destination;
    notifyListeners();
  }

  bool consumeOpenTicketsRequest() {
    return consumeBuyerDestination() == 'tickets';
  }

  String? consumeBuyerDestination() {
    final destination = _requestedBuyerDestination;
    _requestedBuyerDestination = null;
    return destination;
  }
}
