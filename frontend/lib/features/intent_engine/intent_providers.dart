import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'data/intent_repository.dart';
import 'presentation/intent_controller.dart';

final intentRepositoryProvider = Provider<IntentRepositoryContract>(
    (ref) => IntentRepository(ref.watch(apiClientProvider)));
final intentControllerProvider = ChangeNotifierProvider<IntentController>(
    (ref) => IntentController(ref.watch(intentRepositoryProvider)));
