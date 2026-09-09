import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/core/network/api_client.dart';
import 'package:gupmax_ai/core/storage/session_storage.dart';
import 'package:gupmax_ai/features/projects/data/project_repository.dart';
import 'package:gupmax_ai/features/projects/domain/project.dart';

void main() {
  final json = <String, dynamic>{
    'id': 'project-1',
    'name': 'Projeto',
    'status': 'active',
    'created_at': '2026-09-09T00:00:00Z',
    'updated_at': '2026-09-09T00:00:00Z',
  };

  test('favorito envia somente booleano e usa a resposta do servidor',
      () async {
    final dio = Dio();
    final client = ApiClient(
        storage: MemorySessionStorage(),
        onSessionExpired: () async {},
        dio: dio);
    addTearDown(() => dio.close(force: true));
    var persisted = false;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.method == 'PUT') {
        expect(options.path, '/projects/project-1/favorite');
        expect(options.data, {'is_favorite': !persisted});
        persisted = (options.data as Map)['is_favorite'] as bool;
      } else {
        expect(options.method, 'GET');
        expect(options.path, '/projects/project-1');
      }
      handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: {...json, 'is_favorite': persisted}));
    }));
    final repository = ProjectRepository(client);
    expect(
        (await repository.setFavorite('project-1', true)).isFavorite, isTrue);
    expect(
        (await ProjectRepository(client).get('project-1')).isFavorite, isTrue);
    expect(
        (await repository.setFavorite('project-1', false)).isFavorite, isFalse);
    expect(ProjectRecord.fromJson(json).isFavorite, isFalse);
  });

  test('falha HTTP no favorito é traduzida sem retornar sucesso local',
      () async {
    final dio = Dio();
    final client = ApiClient(
        storage: MemorySessionStorage(),
        onSessionExpired: () async {},
        dio: dio);
    addTearDown(() => dio.close(force: true));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.reject(DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 404),
          type: DioExceptionType.badResponse));
    }));
    await expectLater(
        ProjectRepository(client).setFavorite('missing', true),
        throwsA(isA<AppException>().having(
            (error) => error.message, 'message', 'Projeto não encontrado.')));
  });
}
