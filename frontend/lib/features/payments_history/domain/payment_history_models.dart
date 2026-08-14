import '../../usage/domain/usage_models.dart';

class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.provider,
    required this.purpose,
    required this.status,
    required this.amount,
    required this.currency,
    required this.createdAt,
    required this.updatedAt,
    this.creditPackageId,
    this.planId,
    this.paidAt,
    this.canceledAt,
    this.failedAt,
  });

  factory PaymentRecord.fromJson(Map<String, dynamic> json) => PaymentRecord(
        id: json['id'] as String,
        provider: json['provider'] as String,
        purpose: json['purpose'] as String,
        status: json['status'] as String,
        amount: json['amount'] as String,
        currency: json['currency'] as String,
        creditPackageId: json['credit_package_id'] as String?,
        planId: json['plan_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        paidAt: _date(json['paid_at']),
        canceledAt: _date(json['canceled_at']),
        failedAt: _date(json['failed_at']),
      );

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  final String id;
  final String provider;
  final String purpose;
  final String status;
  final String amount;
  final String currency;
  final String? creditPackageId;
  final String? planId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? paidAt;
  final DateTime? canceledAt;
  final DateTime? failedAt;
}

class PaymentHistoryPageData {
  const PaymentHistoryPageData({
    required this.items,
    required this.total,
    required this.offset,
    required this.limit,
  });

  factory PaymentHistoryPageData.fromJson(Map<String, dynamic> json) =>
      PaymentHistoryPageData(
        items: (json['items'] as List<dynamic>)
            .map((item) => PaymentRecord.fromJson(item as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int,
        offset: json['offset'] as int,
        limit: json['limit'] as int,
      );

  final List<PaymentRecord> items;
  final int total;
  final int offset;
  final int limit;
}

class CommercialSummary {
  const CommercialSummary({
    required this.wallet,
    required this.subscription,
    required this.productNames,
  });
  final CreditWallet wallet;
  final AccountSubscription subscription;
  final Map<String, String> productNames;
}

class PaymentFilters {
  const PaymentFilters({this.status, this.provider, this.purpose});
  final String? status;
  final String? provider;
  final String? purpose;

  Map<String, dynamic> query(int offset, int limit) => {
        'offset': offset,
        'limit': limit,
        if (status != null) 'status': status,
        if (provider != null) 'provider': provider,
        if (purpose != null) 'purpose': purpose,
      };
}
