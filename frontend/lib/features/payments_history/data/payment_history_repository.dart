import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../usage/domain/usage_models.dart';
import '../domain/payment_history_models.dart';

abstract interface class PaymentHistoryRepositoryContract {
  Future<CommercialSummary> summary();
  Future<PaymentHistoryPageData> payments({
    required int offset,
    int limit = 20,
    PaymentFilters filters = const PaymentFilters(),
  });
  Future<PaymentRecord> payment(String id);
}

class PaymentHistoryRepository implements PaymentHistoryRepositoryContract {
  const PaymentHistoryRepository(this._client);
  final ApiClient _client;

  @override
  Future<CommercialSummary> summary() async {
    try {
      final responses = await Future.wait([
        _client.dio.get<Map<String, dynamic>>('/credits/wallet'),
        _client.dio.get<Map<String, dynamic>>('/billing/subscription'),
        _client.dio.get<List<dynamic>>('/credits/packages'),
        _client.dio.get<List<dynamic>>('/billing/plans'),
      ]);
      final names = <String, String>{};
      for (final item in responses[2].data! as List<dynamic>) {
        final json = item as Map<String, dynamic>;
        names[json['id'] as String] = json['name'] as String;
      }
      for (final item in responses[3].data! as List<dynamic>) {
        final json = item as Map<String, dynamic>;
        names[json['id'] as String] = json['name'] as String;
      }
      return CommercialSummary(
        wallet: CreditWallet.fromJson(
          responses[0].data! as Map<String, dynamic>,
        ),
        subscription: AccountSubscription.fromJson(
          responses[1].data! as Map<String, dynamic>,
        ),
        productNames: names,
      );
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<PaymentHistoryPageData> payments({
    required int offset,
    int limit = 20,
    PaymentFilters filters = const PaymentFilters(),
  }) async {
    try {
      final response = await _client.dio.get<Map<String, dynamic>>(
        '/payments',
        queryParameters: filters.query(offset, limit),
      );
      return PaymentHistoryPageData.fromJson(response.data!);
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<PaymentRecord> payment(String id) async {
    try {
      final response =
          await _client.dio.get<Map<String, dynamic>>('/payments/$id');
      return PaymentRecord.fromJson(response.data!);
    } catch (error) {
      _mapError(error);
    }
  }

  Never _mapError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final message = switch (status) {
        401 => 'Sua sessão expirou. Entre novamente.',
        403 => 'Você não tem permissão para ver estes pagamentos.',
        404 => 'O pagamento não foi encontrado.',
        429 => 'Muitas solicitações. Tente novamente mais tarde.',
        _ => 'Não foi possível carregar os pagamentos. Tente novamente.',
      };
      throw AppException(message, statusCode: status);
    }
    throw const AppException('Ocorreu um erro inesperado. Tente novamente.');
  }
}
