import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'data/account_repository.dart';
import 'presentation/account_controller.dart';

final accountRepositoryProvider = Provider<AccountRepositoryContract>((ref) {
  return AccountRepository(ref.watch(apiClientProvider));
});

final accountControllerProvider =
    ChangeNotifierProvider<AccountController>((ref) {
  return AccountController(ref.watch(accountRepositoryProvider));
});
