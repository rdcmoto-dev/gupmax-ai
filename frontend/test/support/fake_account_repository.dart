import 'dart:async';

import 'package:gupmax_ai/core/errors/app_exception.dart';
import 'package:gupmax_ai/features/account/data/account_repository.dart';
import 'package:gupmax_ai/features/account/domain/smart_profile.dart';
import 'package:gupmax_ai/features/auth/domain/auth_models.dart';

class FakeAccountRepository implements AccountRepositoryContract {
  AuthUser profileValue = userFixture();
  AppException? error;
  Completer<AuthUser>? profileCompleter;
  int profileCalls = 0;
  int updateCalls = 0;
  int passwordCalls = 0;
  String? updatedName;
  String? updatedEmail;
  SmartProfile smartProfileValue = const SmartProfile();
  int smartProfileCalls = 0;
  int smartProfileSaveCalls = 0;
  int smartProfileDeleteCalls = 0;

  @override
  Future<AuthUser> profile() async {
    profileCalls++;
    if (error case final currentError?) throw currentError;
    return profileCompleter?.future ?? profileValue;
  }

  @override
  Future<AuthUser> updateProfile({
    required String userId,
    required String fullName,
    required String email,
  }) async {
    updateCalls++;
    if (error case final currentError?) throw currentError;
    updatedName = fullName;
    updatedEmail = email;
    profileValue = AuthUser(
      id: userId,
      email: email,
      fullName: fullName,
      isActive: profileValue.isActive,
      role: profileValue.role,
      createdAt: profileValue.createdAt,
    );
    return profileValue;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    passwordCalls++;
    if (error case final currentError?) throw currentError;
  }

  @override
  Future<SmartProfile> smartProfile() async {
    smartProfileCalls++;
    if (error case final currentError?) throw currentError;
    return smartProfileValue;
  }

  @override
  Future<SmartProfile> saveSmartProfile(SmartProfile profile) async {
    smartProfileSaveCalls++;
    if (error case final currentError?) throw currentError;
    smartProfileValue = profile;
    return profile;
  }

  @override
  Future<void> deleteSmartProfile() async {
    smartProfileDeleteCalls++;
    if (error case final currentError?) throw currentError;
    smartProfileValue = const SmartProfile();
  }
}

AuthUser userFixture() => AuthUser(
      id: 'user-1',
      email: 'usuario@example.com',
      fullName: 'Usuário Teste',
      isActive: true,
      role: 'user',
      createdAt: DateTime.utc(2026, 8, 1),
    );
