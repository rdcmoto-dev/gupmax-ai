import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'data/project_repository.dart';
import 'presentation/project_controller.dart';

final projectRepositoryProvider = Provider<ProjectRepositoryContract>(
    (ref) => ProjectRepository(ref.watch(apiClientProvider)));
final projectControllerProvider = ChangeNotifierProvider<ProjectController>(
    (ref) => ProjectController(ref.watch(projectRepositoryProvider)));
