import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/core/network/token_refresh_coordinator.dart';
import 'package:gupmax_ai/core/storage/session_storage.dart';
import 'package:gupmax_ai/features/auth/domain/auth_models.dart';

void main() {
  test('refresh bem-sucedido rotaciona tokens sem expô-los', () async {
    final storage = MemorySessionStorage()..refreshToken = 'old-refresh';
    var expired = false;
    final coordinator = TokenRefreshCoordinator(
      storage: storage,
      requestRefresh: (token) async {
        expect(token, 'old-refresh');
        return const TokenPair(
            accessToken: 'new-access',
            refreshToken: 'new-refresh',
            tokenType: 'bearer');
      },
      onSessionExpired: () async => expired = true,
    );

    expect(await coordinator.refresh(), isTrue);
    expect(coordinator.accessToken, 'new-access');
    expect(await storage.readRefreshToken(), 'new-refresh');
    expect(expired, isFalse);
  });

  test('refresh falho limpa tokens e sinaliza logout local', () async {
    final storage = MemorySessionStorage()..refreshToken = 'invalid-refresh';
    var expired = false;
    final coordinator = TokenRefreshCoordinator(
      storage: storage,
      requestRefresh: (_) async => throw Exception('unauthorized'),
      onSessionExpired: () async => expired = true,
    )..accessToken = 'expired-access';

    expect(await coordinator.refresh(), isFalse);
    expect(coordinator.accessToken, isNull);
    expect(await storage.readRefreshToken(), isNull);
    expect(expired, isTrue);
  });
}
