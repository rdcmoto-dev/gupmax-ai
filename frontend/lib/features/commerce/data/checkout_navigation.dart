import 'checkout_navigation_stub.dart'
    if (dart.library.html) 'checkout_navigation_web.dart' as platform;

abstract interface class CheckoutNavigation {
  Future<bool> open(String url, String paymentId);
  Future<String?> pendingPaymentId();
  Future<void> clearPendingPayment();
}

CheckoutNavigation createCheckoutNavigation() =>
    platform.createCheckoutNavigation();
