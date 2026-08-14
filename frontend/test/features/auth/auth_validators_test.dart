import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/auth/presentation/auth_validators.dart';

void main() {
  test('valida e-mail, nome e limites de senha do backend', () {
    expect(AuthValidators.email('invalido'), isNotNull);
    expect(AuthValidators.email('user@example.com'), isNull);
    expect(AuthValidators.fullName('A'), isNotNull);
    expect(AuthValidators.fullName('Usuário Teste'), isNull);
    expect(AuthValidators.password('1234567', registration: true), isNotNull);
    expect(AuthValidators.password('12345678', registration: true), isNull);
  });
}
