import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'data/prompt_repository.dart';
import 'presentation/prompt_controller.dart';

final promptRepositoryProvider = Provider<PromptRepositoryContract>((ref) {
  return PromptRepository(ref.watch(apiClientProvider));
});

final promptControllerProvider =
    ChangeNotifierProvider<PromptController>((ref) {
  return PromptController(ref.watch(promptRepositoryProvider));
});
