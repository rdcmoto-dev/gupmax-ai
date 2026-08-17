import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/session_expiry_bus.dart';
import '../data/auth_repository.dart';
import '../domain/auth_models.dart';

enum AuthStatus { restoring, authenticated, unauthenticated }

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepositoryContract repository,
    required SessionExpiryBus expiryBus,
    bool restoreOnCreate = true,
  })  : _repository = repository,
        _expiryBus = expiryBus {
    _expiryBus.addListener(_handleExpiredSession);
    if (restoreOnCreate) {
      Future<void>.microtask(restoreSession);
    }
  }

  final AuthRepositoryContract _repository;
  final SessionExpiryBus _expiryBus;
  AuthStatus status = AuthStatus.restoring;
  AuthUser? user;
  bool isSubmitting = false;
  String? errorMessage;

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && user != null;

  Future<void> restoreSession() async {
    status = AuthStatus.restoring;
    errorMessage = null;
    notifyListeners();
    try {
      user = await _repository.restoreSession();
      status = AuthStatus.authenticated;
    } catch (_) {
      user = null;
      status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login({required String email, required String password}) =>
      _submit(() => _repository.login(email: email.trim(), password: password));

  Future<bool> register({
    required String email,
    required String fullName,
    required String password,
  }) =>
      _submit(
        () => _repository.register(
          email: email.trim(),
          fullName: fullName.trim(),
          password: password,
        ),
      );

  Future<bool> _submit(Future<AuthUser> Function() action) async {
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      user = await action();
      status = AuthStatus.authenticated;
      return true;
    } on AppException catch (error) {
      if (user == null) status = AuthStatus.unauthenticated;
      errorMessage = error.message;
      return false;
    } catch (_) {
      if (user == null) status = AuthStatus.unauthenticated;
      errorMessage = 'Não foi possível concluir. Tente novamente.';
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    isSubmitting = true;
    notifyListeners();
    await _repository.logout();
    _setUnauthenticated();
  }

  void syncUser(AuthUser updatedUser) {
    if (user?.id != updatedUser.id) return;
    user = updatedUser;
    notifyListeners();
  }

  void _handleExpiredSession() => _setUnauthenticated();

  void _setUnauthenticated() {
    user = null;
    status = AuthStatus.unauthenticated;
    isSubmitting = false;
    errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _expiryBus.removeListener(_handleExpiredSession);
    super.dispose();
  }
}
