import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../domain/commerce_models.dart';

abstract interface class CommerceRepositoryContract {
  Future<CommerceCatalog> catalog();
  Future<CheckoutResult> createCreditCheckout({
    required String packageId,
    required CheckoutProvider provider,
    required String idempotencyKey,
  });
  Future<CheckoutResult> createSubscriptionCheckout({
    required String planId,
    required CheckoutProvider provider,
    required String idempotencyKey,
  });
  Future<PaymentInfo> payment(String id);
  Future<int> walletBalance();
}

class CommerceRepository implements CommerceRepositoryContract {
  const CommerceRepository(this._client);
  final ApiClient _client;

  @override
  Future<CommerceCatalog> catalog() async {
    try {
      final responses = await Future.wait([
        _client.dio.get<List<dynamic>>('/credits/packages'),
        _client.dio.get<List<dynamic>>('/billing/plans'),
      ]);
      return CommerceCatalog(
        packages: responses[0]
            .data!
            .cast<Map<String, dynamic>>()
            .map(CreditPackage.fromJson)
            .toList(),
        plans: responses[1]
            .data!
            .cast<Map<String, dynamic>>()
            .map(CommercePlan.fromJson)
            .toList(),
      );
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<CheckoutResult> createCreditCheckout({
    required String packageId,
    required CheckoutProvider provider,
    required String idempotencyKey,
  }) =>
      _checkout(
        '/payments/credits/checkout',
        {'package_id': packageId, 'provider': provider.apiValue},
        idempotencyKey,
      );

  @override
  Future<CheckoutResult> createSubscriptionCheckout({
    required String planId,
    required CheckoutProvider provider,
    required String idempotencyKey,
  }) =>
      _checkout(
        '/payments/subscriptions/checkout',
        {'plan_id': planId, 'provider': provider.apiValue},
        idempotencyKey,
      );

  Future<CheckoutResult> _checkout(
      String path, Map<String, dynamic> data, String key) async {
    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        path,
        data: data,
        options: Options(headers: {'Idempotency-Key': key}),
      );
      return CheckoutResult.fromJson(response.data!);
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<PaymentInfo> payment(String id) async {
    try {
      final response =
          await _client.dio.get<Map<String, dynamic>>('/payments/$id');
      return PaymentInfo.fromJson(response.data!);
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<int> walletBalance() async {
    try {
      final response =
          await _client.dio.get<Map<String, dynamic>>('/credits/wallet');
      return response.data!['available_balance'] as int;
    } catch (error) {
      _mapError(error);
    }
  }

  Never _mapError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final message = switch (status) {
        401 => 'Sua sessão expirou. Entre novamente.',
        403 => 'Você não tem permissão para esta operação.',
        404 => 'O item ou pagamento não está mais disponível.',
        409 => 'Esta contratação não pode ser concluída no estado atual.',
        429 => 'Muitas solicitações. Tente novamente em instantes.',
        502 => 'O provedor de pagamento está indisponível. Tente outro.',
        _ => 'Não foi possível concluir a solicitação. Tente novamente.',
      };
      throw AppException(message, statusCode: status);
    }
    throw const AppException('Ocorreu um erro inesperado. Tente novamente.');
  }
}
