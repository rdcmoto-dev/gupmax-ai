import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'data/checkout_navigation.dart';
import 'data/commerce_repository.dart';
import 'presentation/commerce_controller.dart';

final commerceRepositoryProvider = Provider<CommerceRepositoryContract>((ref) {
  return CommerceRepository(ref.watch(apiClientProvider));
});

final checkoutNavigationProvider = Provider<CheckoutNavigation>((ref) {
  return createCheckoutNavigation();
});

final commerceControllerProvider =
    ChangeNotifierProvider<CommerceController>((ref) {
  return CommerceController(
    ref.watch(commerceRepositoryProvider),
    ref.watch(checkoutNavigationProvider),
  );
});
