import 'order.dart';

/// Pedido retenido por cartera (pending_approval), como en "Aprobación de cartera" de la web.
class PendingApproval {
  const PendingApproval({
    required this.id,
    required this.number,
    required this.secondNumber,
    required this.type,
    required this.total,
    required this.carteraBalance,
    required this.createdAt,
    required this.deadline,
    required this.deliveryDate,
    required this.notes,
    required this.seller,
    required this.customer,
    required this.items,
  });

  factory PendingApproval.fromJson(Map<String, dynamic> json) => PendingApproval(
    id: json['id'] as String,
    number: json['number'] as String,
    secondNumber: json['second_number'] as String?,
    type: json['type'] as String? ?? 'corte',
    total: (json['total'] as num).toDouble(),
    carteraBalance: (json['cartera_balance'] as num?)?.toDouble(),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    deadline: json['approval_deadline'] == null ? null : DateTime.parse(json['approval_deadline'] as String).toLocal(),
    deliveryDate: json['delivery_date'] == null ? null : DateTime.parse(json['delivery_date'] as String),
    notes: json['notes'] as String?,
    seller: json['seller'] as String?,
    customer: OrderCustomer.fromJson(json['customer'] as Map<String, dynamic>),
    items: (json['items'] as List<dynamic>).map((e) => OrderLine.fromJson(e as Map<String, dynamic>)).toList(),
  );

  final String id;
  final String number;
  final String? secondNumber;
  final String type;
  final double total;
  final double? carteraBalance;
  final DateTime createdAt;
  final DateTime? deadline;
  final DateTime? deliveryDate;
  final String? notes;
  final String? seller;
  final OrderCustomer customer;
  final List<OrderLine> items;

  String get numberLabel => secondNumber == null ? '#$number' : '#$number / #$secondNumber';
}

class ApprovalsResult {
  const ApprovalsResult({required this.orders, required this.clockOffset});

  factory ApprovalsResult.fromJson(Map<String, dynamic> json) {
    final server = DateTime.tryParse(json['server_time'] as String? ?? '');
    return ApprovalsResult(
      orders: (json['orders'] as List<dynamic>)
          .map((e) => PendingApproval.fromJson(e as Map<String, dynamic>))
          .toList(),
      clockOffset: server == null ? Duration.zero : server.difference(DateTime.now()),
    );
  }

  final List<PendingApproval> orders;

  /// Diferencia entre el reloj del servidor y el del teléfono, para la cuenta regresiva.
  final Duration clockOffset;
}

/// Resultado de aprobar o desaprobar en la web.
class ApprovalDecision {
  const ApprovalDecision({required this.status, this.syncError});

  factory ApprovalDecision.fromJson(Map<String, dynamic> json) =>
      ApprovalDecision(status: json['status'] as String? ?? '', syncError: json['sync_error'] as String?);

  final String status;
  final String? syncError;
}
