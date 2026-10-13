import 'order.dart';

class QuoteCustomer {
  const QuoteCustomer({required this.name, required this.code, this.branch, this.email, this.phone});

  factory QuoteCustomer.fromJson(Map<String, dynamic> json) => QuoteCustomer(
    name: json['name'] as String,
    code: json['code'] as String,
    branch: json['branch'] as String?,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
  );

  final String name;
  final String code;
  final String? branch;
  final String? email;
  final String? phone;
}

class QuoteSummary {
  const QuoteSummary({
    required this.id,
    required this.number,
    required this.total,
    required this.itemsCount,
    required this.createdAt,
    required this.validUntil,
    required this.expired,
    required this.seller,
    required this.customer,
  });

  factory QuoteSummary.fromJson(Map<String, dynamic> json) => QuoteSummary(
    id: json['id'] as String,
    number: json['number'] as String,
    total: (json['total'] as num).toDouble(),
    itemsCount: (json['items_count'] as num).toInt(),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    validUntil: json['valid_until'] == null ? null : DateTime.parse(json['valid_until'] as String).toLocal(),
    expired: json['expired'] as bool? ?? false,
    seller: json['seller'] as String?,
    customer: QuoteCustomer.fromJson(json['customer'] as Map<String, dynamic>),
  );

  final String id;
  final String number;
  final double total;
  final int itemsCount;
  final DateTime createdAt;
  final DateTime? validUntil;
  final bool expired;
  final String? seller;
  final QuoteCustomer customer;
}

class QuoteDetail {
  const QuoteDetail({
    required this.summary,
    required this.subtotal,
    required this.taxes,
    required this.notes,
    required this.items,
  });

  factory QuoteDetail.fromJson(Map<String, dynamic> json) => QuoteDetail(
    summary: QuoteSummary.fromJson(json),
    subtotal: (json['subtotal'] as num).toDouble(),
    taxes: (json['taxes'] as num).toDouble(),
    notes: json['notes'] as String?,
    items: (json['items'] as List<dynamic>).map((e) => OrderLine.fromJson(e as Map<String, dynamic>)).toList(),
  );

  final QuoteSummary summary;
  final double subtotal;
  final double taxes;
  final String? notes;
  final List<OrderLine> items;
}

class QuoteDraftLine {
  QuoteDraftLine({required this.quantity, this.discountPct = 0});

  int quantity;
  double discountPct;
}

class CreatedQuote {
  const CreatedQuote({required this.id, required this.number, required this.total});

  factory CreatedQuote.fromJson(Map<String, dynamic> json) => CreatedQuote(
    id: json['id'] as String,
    number: json['number'] as String,
    total: (json['total'] as num).toDouble(),
  );

  final String id;
  final String number;
  final double total;
}
