import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/smart_profile.dart';

abstract interface class AccountRepositoryContract {
  Future<AuthUser> profile();
  Future<AuthUser> updateProfile({
    required String userId,
    required String fullName,
    required String email,
  });
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
  Future<SmartProfile> smartProfile();
  Future<SmartProfile> saveSmartProfile(SmartProfile profile);
  Future<void> deleteSmartProfile();
}

class AccountRepository implements AccountRepositoryContract {
  const AccountRepository(this._client);

  final ApiClient _client;

  @override
  Future<AuthUser> profile() async {
    try {
      final response = await _client.dio.get<Map<String, dynamic>>('/users/me');
      return AuthUser.fromJson(response.data!);
    } catch (error) {
      _mapError(error, fallback: 'Não foi possível carregar sua conta.');
    }
  }

  @override
  Future<AuthUser> updateProfile({
    required String userId,
    required String fullName,
    required String email,
  }) async {
    try {
      final response = await _client.dio.patch<Map<String, dynamic>>(
        '/users/$userId',
        data: {'full_name': fullName, 'email': email},
      );
      return AuthUser.fromJson(response.data!);
    } catch (error) {
      _mapError(error, fallback: 'Não foi possível atualizar seu perfil.');
    }
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _client.dio.patch<void>(
        '/users/me/password',
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        },
      );
    } catch (error) {
      _mapError(error, fallback: 'Não foi possível alterar sua senha.');
    }
  }

  @override
  Future<SmartProfile> smartProfile() async {
    try {
      final response = await _client.dio
          .get<Map<String, dynamic>>('/profile/prompt-preferences');
      return SmartProfile.fromJson(response.data!);
    } catch (error) {
      _mapError(error, fallback: 'Não foi possível carregar o Smart Profile.');
    }
  }

  @override
  Future<SmartProfile> saveSmartProfile(SmartProfile profile) async {
    try {
      final response = await _client.dio.put<Map<String, dynamic>>(
        '/profile/prompt-preferences',
        data: profile.toJson(),
      );
      return SmartProfile.fromJson(response.data!);
    } catch (error) {
      _mapError(error, fallback: 'Não foi possível salvar o Smart Profile.');
    }
  }

  @override
  Future<void> deleteSmartProfile() async {
    try {
      await _client.dio.delete<void>('/profile/prompt-preferences');
    } catch (error) {
      _mapError(error, fallback: 'Não foi possível limpar o Smart Profile.');
    }
  }

  Never _mapError(Object error, {required String fallback}) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final message = switch (status) {
        401 => 'Sua sessão expirou. Entre novamente.',
        403 => 'A senha atual está incorreta ou a ação não foi permitida.',
        409 => 'Este e-mail já está em uso.',
        422 => 'Revise os dados informados.',
        429 => 'Muitas solicitações. Tente novamente mais tarde.',
        _ => '$fallback Tente novamente.',
      };
      throw AppException(message, statusCode: status);
    }
    throw const AppException('Ocorreu um erro inesperado. Tente novamente.');
  }
}
