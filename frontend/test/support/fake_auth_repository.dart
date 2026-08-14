import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/features/auth/data/auth_repository.dart';
import 'package:gupmax_ai/features/auth/domain/auth_models.dart';

class FakeAuthRepository implements AuthRepositoryContract {
  AuthUser? resultUser;
  AppException? error;
  int loginCalls = 0;
  int registerCalls = 0;
  int restoreCalls = 0;
  int meCalls = 0;
  int logoutCalls = 0;

  static final user = AuthUser(
    id: '10000000-0000-0000-0000-000000000001',
    email: 'teste@example.com',
    fullName: 'Usuário Teste',
    isActive: true,
    role: 'user',
    createdAt: DateTime.utc(2026, 8, 14),
  );

  AuthUser _result() {
    if (error case final exception?) throw exception;
    return resultUser ?? user;
  }

  @override
  Future<AuthUser> getCurrentUser() async {
    meCalls++;
    return _result();
  }

  @override
  Future<AuthUser> login(
      {required String email, required String password}) async {
    loginCalls++;
    return _result();
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
  }

  @override
  Future<AuthUser> register(
      {required String email,
      required String fullName,
      required String password}) async {
    registerCalls++;
    return _result();
  }

  @override
  Future<AuthUser> restoreSession() async {
    restoreCalls++;
    return _result();
  }
}
