import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/core/network/api_client.dart';
import 'package:gupmax_ai/core/storage/session_storage.dart';
import 'package:gupmax_ai/features/projects/data/project_repository.dart';

void main() {
  test('limite de pins preserva c?digo e UTF-8 da API', () async {
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: options,
          statusCode: 409,
          data: {'detail': {'code': 'project_pin_limit_reached', 'message': 'Você pode fixar até 3 projetos. Desafixe um projeto para continuar.'}},
        ),
      ));
    }));
    await expectLater(
      ProjectRepository(ApiClient(storage: MemorySessionStorage(), onSessionExpired: () async {}, dio: dio)).setPinned('project-4', true),
      throwsA(isA<AppException>()
          .having((error) => error.code, 'code', 'project_pin_limit_reached')
          .having((error) => error.message, 'message', 'Você pode fixar até 3 projetos. Desafixe um projeto para continuar.')),
    );
  });
}
