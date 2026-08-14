abstract final class AuthValidators {
  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Informe seu e-mail.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Informe um e-mail válido.';
    }
    return null;
  }

  static String? password(String? value, {bool registration = false}) {
    final password = value ?? '';
    if (password.isEmpty) return 'Informe sua senha.';
    if (registration && password.length < 8) {
      return 'Use pelo menos 8 caracteres.';
    }
    if (password.length > 128) {
      return 'A senha deve ter no máximo 128 caracteres.';
    }
    return null;
  }

  static String? fullName(String? value) {
    final name = value?.trim() ?? '';
    if (name.length < 2) return 'Informe seu nome completo.';
    if (name.length > 120) return 'Use no máximo 120 caracteres.';
    return null;
  }
}
