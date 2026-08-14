class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
  });

  factory TokenPair.fromJson(Map<String, dynamic> json) => TokenPair(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        tokenType: json['token_type'] as String? ?? 'bearer',
      );

  final String accessToken;
  final String refreshToken;
  final String tokenType;
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.isActive,
    required this.role,
    required this.createdAt,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        isActive: json['is_active'] as bool,
        role: json['role'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String email;
  final String fullName;
  final bool isActive;
  final String role;
  final DateTime createdAt;
}

class RegistrationResult {
  const RegistrationResult({required this.tokens, required this.user});

  factory RegistrationResult.fromJson(Map<String, dynamic> json) =>
      RegistrationResult(
        tokens: TokenPair.fromJson(json),
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );

  final TokenPair tokens;
  final AuthUser user;
}
