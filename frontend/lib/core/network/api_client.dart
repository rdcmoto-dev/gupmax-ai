import 'package:dio/dio.dart';

import '../../features/auth/domain/auth_models.dart';
import '../config/api_config.dart';
import '../errors/app_exception.dart';
import '../storage/session_storage.dart';
import 'auth_interceptor.dart';
import 'token_refresh_coordinator.dart';

class ApiClient {
  ApiClient({
    required SessionStorage storage,
    required SessionExpired onSessionExpired,
    Dio? dio,
    Dio? refreshDio,
  })  : dio = dio ?? Dio(_baseOptions()),
        _refreshDio = refreshDio ?? Dio(_baseOptions()) {
    refreshCoordinator = TokenRefreshCoordinator(
      storage: storage,
      requestRefresh: _requestRefresh,
      onSessionExpired: onSessionExpired,
    );
    this.dio.interceptors.add(
          AuthInterceptor(dio: this.dio, coordinator: refreshCoordinator),
        );
  }

  final Dio dio;
  final Dio _refreshDio;
  late final TokenRefreshCoordinator refreshCoordinator;

  static BaseOptions _baseOptions() => BaseOptions(
        baseUrl: ApiConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 15),
        headers: const {'Accept': 'application/json'},
      );

  Future<TokenPair> _requestRefresh(String refreshToken) async {
    final response = await _refreshDio.post<Map<String, dynamic>>(
      '/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    return TokenPair.fromJson(response.data!);
  }

  Never mapError(Object error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final data = error.response?.data;
      final detail = data is Map<String, dynamic> ? data['detail'] : null;
      if (statusCode == 401) {
        throw const AppException('E-mail ou senha inválidos.', statusCode: 401);
      }
      if (statusCode == 409) {
        throw const AppException('Já existe uma conta com este e-mail.',
            statusCode: 409);
      }
      if (statusCode == 422) {
        throw const AppException('Confira os dados informados.',
            statusCode: 422);
      }
      if (detail is String &&
          detail.isNotEmpty &&
          statusCode != null &&
          statusCode < 500) {
        throw AppException('Não foi possível concluir a solicitação.',
            statusCode: statusCode);
      }
      throw AppException(
        'Serviço temporariamente indisponível. Tente novamente.',
        statusCode: statusCode,
      );
    }
    throw const AppException('Ocorreu um erro inesperado. Tente novamente.');
  }
}
