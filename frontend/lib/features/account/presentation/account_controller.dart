import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../../auth/domain/auth_models.dart';
import '../data/account_repository.dart';
import '../domain/smart_profile.dart';

class AccountController extends ChangeNotifier {
  AccountController(this._repository);

  final AccountRepositoryContract _repository;

  AuthUser? user;
  bool isLoading = false;
  bool isSavingProfile = false;
  bool isChangingPassword = false;
  String? error;
  String? successMessage;
  SmartProfile smartProfile = const SmartProfile();
  bool isLoadingSmartProfile = false;
  bool isSavingSmartProfile = false;

  Future<void> load() async {
    isLoading = true;
    error = null;
    successMessage = null;
    notifyListeners();
    try {
      user = await _repository.profile();
      await loadSmartProfile();
    } on AppException catch (exception) {
      error = exception.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadSmartProfile() async {
    isLoadingSmartProfile = true;
    notifyListeners();
    try {
      smartProfile = await _repository.smartProfile();
    } on AppException catch (exception) {
      error = exception.message;
    } finally {
      isLoadingSmartProfile = false;
      notifyListeners();
    }
  }

  Future<bool> saveSmartProfile(SmartProfile value) async {
    isSavingSmartProfile = true;
    error = null;
    successMessage = null;
    notifyListeners();
    try {
      smartProfile = await _repository.saveSmartProfile(value);
      successMessage = 'Preferências salvas com sucesso.';
      return true;
    } on AppException catch (exception) {
      error = exception.message;
      return false;
    } finally {
      isSavingSmartProfile = false;
      notifyListeners();
    }
  }

  Future<void> deleteSmartProfile() async {
    isSavingSmartProfile = true;
    error = null;
    notifyListeners();
    try {
      await _repository.deleteSmartProfile();
      smartProfile = const SmartProfile();
      successMessage = 'Preferências removidas.';
    } on AppException catch (exception) {
      error = exception.message;
    } finally {
      isSavingSmartProfile = false;
      notifyListeners();
    }
  }

  Future<AuthUser?> updateProfile({
    required String fullName,
    required String email,
  }) async {
    final currentUser = user;
    if (currentUser == null) return null;
    isSavingProfile = true;
    error = null;
    successMessage = null;
    notifyListeners();
    try {
      user = await _repository.updateProfile(
        userId: currentUser.id,
        fullName: fullName.trim(),
        email: email.trim(),
      );
      successMessage = 'Perfil atualizado com sucesso.';
      return user;
    } on AppException catch (exception) {
      error = exception.message;
      return null;
    } finally {
      isSavingProfile = false;
      notifyListeners();
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    isChangingPassword = true;
    error = null;
    successMessage = null;
    notifyListeners();
    try {
      await _repository.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      successMessage = 'Senha alterada com sucesso.';
      return true;
    } on AppException catch (exception) {
      error = exception.message;
      return false;
    } finally {
      isChangingPassword = false;
      notifyListeners();
    }
  }
}
