import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download/file_download.dart';
import '../auth/auth_providers.dart';
import 'data/project_repository.dart';
import 'presentation/project_controller.dart';
import 'project_library.dart';

final projectRepositoryProvider = Provider<ProjectRepositoryContract>(
    (ref) => ProjectRepository(ref.watch(apiClientProvider)));
final fileDownloadProvider =
    Provider<FileDownloadService>((ref) => const PlatformFileDownloadService());
final projectControllerProvider = ChangeNotifierProvider<ProjectController>(
    (ref) => ProjectController(ref.watch(projectRepositoryProvider)));
final projectLibraryProvider = FutureProvider.autoDispose
    .family<ProjectLibraryData, String>((ref, projectId) =>
        ref.read(projectRepositoryProvider).library(projectId));
