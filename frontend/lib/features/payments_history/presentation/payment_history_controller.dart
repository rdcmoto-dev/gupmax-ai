import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../data/payment_history_repository.dart';
import '../domain/payment_history_models.dart';

class PaymentHistoryController extends ChangeNotifier {
  PaymentHistoryController(this._repository);
  final PaymentHistoryRepositoryContract _repository;

  static const pageSize = 20;
  bool isLoading = false;
  bool isLoadingDetail = false;
  String? error;
  CommercialSummary? summary;
  List<PaymentRecord> items = [];
  int total = 0;
  int offset = 0;
  PaymentRecord? selectedPayment;
  String? statusFilter;
  String? providerFilter;
  String? purposeFilter;

  PaymentFilters get filters => PaymentFilters(
        status: statusFilter,
        provider: providerFilter,
        purpose: purposeFilter,
      );

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repository.summary(),
        _repository.payments(offset: 0, limit: pageSize, filters: filters),
      ]);
      summary = results[0] as CommercialSummary;
      _applyPage(results[1] as PaymentHistoryPageData);
    } on AppException catch (exception) {
      error = exception.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadPage(int newOffset) async {
    try {
      _applyPage(await _repository.payments(
        offset: newOffset,
        limit: pageSize,
        filters: filters,
      ));
      error = null;
    } on AppException catch (exception) {
      error = exception.message;
    }
    notifyListeners();
  }

  Future<void> setFilters({String? status, String? provider, String? purpose}) {
    statusFilter = status;
    providerFilter = provider;
    purposeFilter = purpose;
    return loadPage(0);
  }

  Future<void> loadDetail(String id) async {
    isLoadingDetail = true;
    error = null;
    selectedPayment = null;
    notifyListeners();
    try {
      summary ??= await _repository.summary();
      selectedPayment = await _repository.payment(id);
    } on AppException catch (exception) {
      error = exception.message;
    } finally {
      isLoadingDetail = false;
      notifyListeners();
    }
  }

  void _applyPage(PaymentHistoryPageData page) {
    items = page.items;
    total = page.total;
    offset = page.offset;
  }
}
