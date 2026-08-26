import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'data/prompt_chain_repository.dart';
import 'presentation/prompt_chain_controller.dart';

final promptChainRepositoryProvider = Provider<PromptChainRepositoryContract>(
    (ref) => PromptChainRepository(ref.watch(apiClientProvider)));

final promptChainControllerProvider =
    ChangeNotifierProvider<PromptChainController>((ref) =>
        PromptChainController(ref.watch(promptChainRepositoryProvider)));
