import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/auth_interceptor.dart';
import '../../../core/storage/session_storage.dart';
import '../domain/auth_models.dart';

abstract interface class AuthRepositoryContract {
  Future<AuthUser> login({required String email, required String password});
  Future<AuthUser> register({
    required String email,
    required String fullName,
    required String password,
  });
  Future<AuthUser> restoreSession();
  Future<AuthUser> getCurrentUser();
  Future<void> logout();
}

class AuthRepository implements AuthRepositoryContract {
  AuthRepository({required ApiClient client, required SessionStorage storage})
      : _client = client,
        _storage = storage;

  final ApiClient _client;
  final SessionStorage _storage;

  @override
  Future<AuthUser> login(
      {required String email, required String password}) async {
    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email, 'password': password},
        options: Options(extra: {AuthInterceptor.skipAuthKey: true}),
      );
      await _client.refreshCoordinator
          .apply(TokenPair.fromJson(response.data!));
      return await getCurrentUser();
    } catch (error) {
      _client.mapError(error);
    }
  }

  @override
  Future<AuthUser> register({
    required String email,
    required String fullName,
    required String password,
  }) async {
    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        '/auth/register',
        data: {'email': email, 'full_name': fullName, 'password': password},
        options: Options(extra: {AuthInterceptor.skipAuthKey: true}),
      );
      final result = RegistrationResult.fromJson(response.data!);
      await _client.refreshCoordinator.apply(result.tokens);
      return result.user;
    } catch (error) {
      _client.mapError(error);
    }
  }

  @override
  Future<AuthUser> getCurrentUser() async {
    try {
      final response = await _client.dio.get<Map<String, dynamic>>('/users/me');
      return AuthUser.fromJson(response.data!);
    } catch (error) {
      _client.mapError(error);
    }
  }

  @override
  Future<AuthUser> restoreSession() async {
    if (!await _client.refreshCoordinator.refresh()) {
      throw const AppException('Sessão não encontrada.', statusCode: 401);
    }
    return getCurrentUser();
  }

  @override
  Future<void> logout() async {
    final refreshToken = await _storage.readRefreshToken();
    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _client.dio.post<void>(
          '/auth/logout',
          data: {'refresh_token': refreshToken},
          options: Options(extra: {AuthInterceptor.skipAuthKey: true}),
        );
      }
    } on DioException {
      // Logout local permanece obrigatório mesmo se o backend estiver indisponível.
    } finally {
      await _client.refreshCoordinator.clear();
    }
  }
}
