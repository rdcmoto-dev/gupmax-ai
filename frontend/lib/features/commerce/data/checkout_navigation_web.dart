// ignore_for_file: avoid_web_libraries_in_flutter

// ignore: deprecated_member_use
import 'dart:html' as html;

import 'checkout_navigation.dart';

CheckoutNavigation createCheckoutNavigation() => const WebCheckoutNavigation();

class WebCheckoutNavigation implements CheckoutNavigation {
  const WebCheckoutNavigation();
  static const _pendingKey = 'gupmax_pending_payment_id';

  @override
  Future<bool> open(String url, String paymentId) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return false;
    }
    html.window.sessionStorage[_pendingKey] = paymentId;
    html.window.location.assign(uri.toString());
    return true;
  }

  @override
  Future<String?> pendingPaymentId() async =>
      html.window.sessionStorage[_pendingKey];

  @override
  Future<void> clearPendingPayment() async {
    html.window.sessionStorage.remove(_pendingKey);
  }
}
