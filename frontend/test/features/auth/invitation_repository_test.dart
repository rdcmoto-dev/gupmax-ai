import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/core/network/api_client.dart';
import 'package:gupmax_ai/core/storage/session_storage.dart';
import 'package:gupmax_ai/features/auth/data/auth_repository.dart';

void main() {
  const invitation = 'private-invitation-test-only';
  late Dio dio;
  late MemorySessionStorage storage;
  late AuthRepository repository;
  late List<RequestOptions> requests;
  late List<String> logs;
  late DebugPrintCallback originalDebugPrint;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://isolated'));
    storage = MemorySessionStorage();
    requests = [];
    logs = [];
    originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    repository = AuthRepository(
      client: ApiClient(storage: storage, onSessionExpired: () async {}, dio: dio),
      storage: storage,
    );
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
    dio.close();
    expect(logs.join(), isNot(contains(invitation)));
  });

  test('envia convite no corpo e conserva sessao sem armazenar convite',
      () async {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      handler.resolve(Response(requestOptions: options, statusCode: 201, data: {
        'access_token': 'test-access',
        'refresh_token': 'test-refresh',
        'user': {
          'id': 'test-user',
          'email': 'invited@example.com',
          'full_name': 'Pilot',
          'role': 'user',
          'is_active': true,
          'created_at': '2026-09-21T00:00:00Z',
        },
      }));
    }));
    final user = await repository.register(
        email: 'invited@example.com',
        fullName: 'Pilot',
        password: 'test-password',
        invitationToken: ' $invitation ');
    expect(user.role, 'user');
    expect(requests.single.data['invitation_token'], invitation);
    expect(requests.single.uri.toString(), isNot(contains(invitation)));
    expect(await storage.readRefreshToken(), 'test-refresh');
  });

  test('convite ausente bloqueia requisicao', () async {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      handler.reject(DioException(requestOptions: options));
    }));
    await expectLater(
        repository.register(
            email: 'invited@example.com',
            fullName: 'Pilot',
            password: 'test-password',
            invitationToken: '  '),
        throwsA(isA<AppException>().having((e) => e.message, 'message',
            'Informe o convite recebido do administrador.')));
    expect(requests, isEmpty);
    expect(await storage.readRefreshToken(), isNull);
  });

  test('403 nao reflete token ou detalhes do servidor em erros ou logs',
      () async {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.reject(DioException(
        requestOptions: options,
        response: Response(
            requestOptions: options,
            statusCode: 403,
            data: {'detail': 'internal detail $invitation'}),
        type: DioExceptionType.badResponse,
      ));
    }));
    await runZoned(() async {
      await expectLater(
          repository.register(
              email: 'invited@example.com',
              fullName: 'Pilot',
              password: 'test-password',
              invitationToken: invitation),
          throwsA(isA<AppException>()
              .having((e) => e.statusCode, 'status', 403)
              .having((e) => e.message, 'message',
                  contains('Convite inválido, vencido ou já utilizado.'))
              .having(
                  (e) => e.message, 'secret', isNot(contains(invitation)))));
    },
        zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => logs.add(line)));
    expect(await storage.readRefreshToken(), isNull);
  });
}
