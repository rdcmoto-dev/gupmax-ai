import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'data/template_repository.dart';
import 'presentation/template_controller.dart';

final templateRepositoryProvider = Provider<TemplateRepositoryContract>((ref) {
  return TemplateRepository(ref.watch(apiClientProvider));
});

final templateControllerProvider =
    ChangeNotifierProvider<TemplateController>((ref) {
  return TemplateController(ref.watch(templateRepositoryProvider));
});
