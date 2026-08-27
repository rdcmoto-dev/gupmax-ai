import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'data/expert_planner_repository.dart';
import 'presentation/expert_planner_controller.dart';

final expertPlannerRepositoryProvider =
    Provider<ExpertPlannerRepositoryContract>(
        (ref) => ExpertPlannerRepository(ref.watch(apiClientProvider)));

final expertPlannerControllerProvider = ChangeNotifierProvider.autoDispose(
    (ref) =>
        ExpertPlannerController(ref.watch(expertPlannerRepositoryProvider)));
