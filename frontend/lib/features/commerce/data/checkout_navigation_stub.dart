import 'checkout_navigation.dart';

CheckoutNavigation createCheckoutNavigation() =>
    const UnsupportedCheckoutNavigation();

class UnsupportedCheckoutNavigation implements CheckoutNavigation {
  const UnsupportedCheckoutNavigation();

  @override
  Future<bool> open(String url, String paymentId) async => false;

  @override
  Future<String?> pendingPaymentId() async => null;

  @override
  Future<void> clearPendingPayment() async {}
}
