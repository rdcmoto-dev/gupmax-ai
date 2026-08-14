import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/auth/domain/auth_models.dart';

void main() {
  test('decodifica exatamente o contrato GET /api/v1/users/me', () {
    final user = AuthUser.fromJson({
      'id': '10000000-0000-0000-0000-000000000001',
      'email': 'teste@example.com',
      'full_name': 'Usuário Teste',
      'is_active': true,
      'role': 'user',
      'created_at': '2026-08-14T12:00:00Z',
    });
    expect(user.fullName, 'Usuário Teste');
    expect(user.role, 'user');
    expect(user.isActive, isTrue);
  });
}
