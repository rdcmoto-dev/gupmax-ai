import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/session_expiry_bus.dart';
import '../../core/storage/session_storage.dart';
import 'data/auth_repository.dart';
import 'presentation/auth_controller.dart';

final sessionStorageProvider =
    Provider<SessionStorage>((ref) => SecureSessionStorage());

final sessionExpiryBusProvider = Provider<SessionExpiryBus>((ref) {
  final bus = SessionExpiryBus();
  ref.onDispose(bus.dispose);
  return bus;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final bus = ref.watch(sessionExpiryBusProvider);
  return ApiClient(
    storage: ref.watch(sessionStorageProvider),
    onSessionExpired: () async => bus.expire(),
  );
});

final authRepositoryProvider = Provider<AuthRepositoryContract>((ref) {
  return AuthRepository(
    client: ref.watch(apiClientProvider),
    storage: ref.watch(sessionStorageProvider),
  );
});

final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  return AuthController(
    repository: ref.watch(authRepositoryProvider),
    expiryBus: ref.watch(sessionExpiryBusProvider),
  );
});
