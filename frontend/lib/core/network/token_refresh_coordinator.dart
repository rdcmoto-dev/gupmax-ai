import '../../features/auth/domain/auth_models.dart';
import '../storage/session_storage.dart';

typedef RefreshRequest = Future<TokenPair> Function(String refreshToken);
typedef SessionExpired = Future<void> Function();

class TokenRefreshCoordinator {
  TokenRefreshCoordinator({
    required SessionStorage storage,
    required RefreshRequest requestRefresh,
    required SessionExpired onSessionExpired,
  })  : _storage = storage,
        _requestRefresh = requestRefresh,
        _onSessionExpired = onSessionExpired;

  final SessionStorage _storage;
  final RefreshRequest _requestRefresh;
  final SessionExpired _onSessionExpired;
  Future<bool>? _activeRefresh;
  String? accessToken;

  Future<void> apply(TokenPair tokens) async {
    accessToken = tokens.accessToken;
    await _storage.writeRefreshToken(tokens.refreshToken);
  }

  Future<bool> refresh() =>
      _activeRefresh ??= _performRefresh().whenComplete(() {
        _activeRefresh = null;
      });

  Future<bool> _performRefresh() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await clear();
      return false;
    }
    try {
      await apply(await _requestRefresh(refreshToken));
      return true;
    } catch (_) {
      await clear();
      return false;
    }
  }

  Future<void> clear() async {
    accessToken = null;
    await _storage.clearRefreshToken();
    await _onSessionExpired();
  }
}
