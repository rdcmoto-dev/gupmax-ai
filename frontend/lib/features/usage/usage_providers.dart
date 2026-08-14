import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'data/usage_repository.dart';
import 'presentation/usage_controller.dart';

final usageRepositoryProvider = Provider<UsageRepositoryContract>((ref) {
  return UsageRepository(ref.watch(apiClientProvider));
});

final usageControllerProvider = ChangeNotifierProvider<UsageController>((ref) {
  return UsageController(ref.watch(usageRepositoryProvider));
});
