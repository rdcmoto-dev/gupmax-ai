import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../data/usage_repository.dart';
import '../domain/usage_models.dart';

class UsageController extends ChangeNotifier {
  UsageController(this._repository);
  final UsageRepositoryContract _repository;

  static const pageSize = 20;
  bool isLoading = false;
  String? error;
  UsageSummary? summary;
  List<AiUsageRecord> usageItems = [];
  int usageTotal = 0;
  int usageOffset = 0;
  List<CreditMovement> movements = [];
  int movementTotal = 0;
  int movementOffset = 0;

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repository.summary(),
        _repository.usage(offset: 0, limit: pageSize),
        _repository.movements(offset: 0, limit: pageSize),
      ]);
      summary = results[0] as UsageSummary;
      _applyUsage(results[1] as UsagePageData);
      _applyMovements(results[2] as CreditMovementPage);
    } on AppException catch (exception) {
      error = exception.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadUsage(int offset) async {
    try {
      _applyUsage(await _repository.usage(offset: offset, limit: pageSize));
      error = null;
    } on AppException catch (exception) {
      error = exception.message;
    }
    notifyListeners();
  }

  Future<void> loadMovements(int offset) async {
    try {
      _applyMovements(
          await _repository.movements(offset: offset, limit: pageSize));
      error = null;
    } on AppException catch (exception) {
      error = exception.message;
    }
    notifyListeners();
  }

  void _applyUsage(UsagePageData page) {
    usageItems = page.items;
    usageTotal = page.total;
    usageOffset = page.offset;
  }

  void _applyMovements(CreditMovementPage page) {
    movements = page.items;
    movementTotal = page.total;
    movementOffset = page.offset;
  }
}
