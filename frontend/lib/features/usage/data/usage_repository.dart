import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../domain/usage_models.dart';

abstract interface class UsageRepositoryContract {
  Future<UsageSummary> summary();
  Future<UsagePageData> usage({required int offset, int limit = 20});
  Future<CreditMovementPage> movements({required int offset, int limit = 20});
}

class UsageRepository implements UsageRepositoryContract {
  const UsageRepository(this._client);
  final ApiClient _client;

  @override
  Future<UsageSummary> summary() async {
    try {
      final responses = await Future.wait([
        _client.dio.get<Map<String, dynamic>>('/credits/wallet'),
        _client.dio.get<Map<String, dynamic>>('/billing/subscription'),
        _client.dio.get<Map<String, dynamic>>('/billing/limits'),
      ]);
      return UsageSummary(
        wallet: CreditWallet.fromJson(responses[0].data!),
        subscription: AccountSubscription.fromJson(responses[1].data!),
        limits: AccountLimits.fromJson(responses[2].data!),
      );
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<UsagePageData> usage({required int offset, int limit = 20}) async {
    try {
      final response = await _client.dio.get<Map<String, dynamic>>(
        '/billing/usage',
        queryParameters: {'offset': offset, 'limit': limit},
      );
      return UsagePageData.fromJson(response.data!);
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<CreditMovementPage> movements(
      {required int offset, int limit = 20}) async {
    try {
      final response = await _client.dio.get<Map<String, dynamic>>(
        '/credits/transactions',
        queryParameters: {'offset': offset, 'limit': limit},
      );
      return CreditMovementPage.fromJson(response.data!);
    } catch (error) {
      _mapError(error);
    }
  }

  Never _mapError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final message = switch (status) {
        401 => 'Sua sessão expirou. Entre novamente.',
        403 => 'Você não tem permissão para acessar estes dados.',
        404 => 'As informações de uso não foram encontradas.',
        429 => 'Limite de solicitações atingido. Tente novamente mais tarde.',
        _ => 'Não foi possível carregar seu uso. Tente novamente.',
      };
      throw AppException(message, statusCode: status);
    }
    throw const AppException('Ocorreu um erro inesperado. Tente novamente.');
  }
}
