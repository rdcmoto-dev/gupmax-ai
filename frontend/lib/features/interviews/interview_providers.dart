import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'data/interview_repository.dart';
import 'presentation/interview_controller.dart';

final interviewRepositoryProvider =
    Provider<InterviewRepositoryContract>((ref) {
  return InterviewRepository(ref.watch(apiClientProvider));
});

final interviewControllerProvider =
    ChangeNotifierProvider<InterviewController>((ref) {
  return InterviewController(ref.watch(interviewRepositoryProvider));
});
