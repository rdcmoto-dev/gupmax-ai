import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'data/payment_history_repository.dart';
import 'presentation/payment_history_controller.dart';

final paymentHistoryRepositoryProvider =
    Provider<PaymentHistoryRepositoryContract>((ref) {
  return PaymentHistoryRepository(ref.watch(apiClientProvider));
});

final paymentHistoryControllerProvider =
    ChangeNotifierProvider<PaymentHistoryController>((ref) {
  return PaymentHistoryController(ref.watch(paymentHistoryRepositoryProvider));
});
