import 'package:dio/dio.dart';

import 'token_refresh_coordinator.dart';

class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor(
      {required Dio dio, required TokenRefreshCoordinator coordinator})
      : _dio = dio,
        _coordinator = coordinator;

  static const _retriedKey = 'auth_retry_completed';
  static const skipAuthKey = 'skip_auth_refresh';
  final Dio _dio;
  final TokenRefreshCoordinator _coordinator;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _coordinator.accessToken;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    if (err.response?.statusCode == 401 && options.extra[_retriedKey] == true) {
      await _coordinator.clear();
      handler.next(err);
      return;
    }
    final canRefresh = err.response?.statusCode == 401 &&
        options.extra[skipAuthKey] != true &&
        options.extra[_retriedKey] != true;
    if (!canRefresh || !await _coordinator.refresh()) {
      handler.next(err);
      return;
    }

    options.extra[_retriedKey] = true;
    options.headers['Authorization'] = 'Bearer ${_coordinator.accessToken}';
    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }
}
