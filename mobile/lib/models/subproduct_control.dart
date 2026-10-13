import 'order.dart';

/// Pedido de subproducto esperando al controlador (o con error al subir a Siesa).
class ControlOrder {
  const ControlOrder({
    required this.id,
    required this.number,
    required this.secondNumber,
    required this.status,
    required this.total,
    required this.createdAt,
    required this.deliveryDate,
    required this.notes,
    required this.logisticsNote,
    required this.syncError,
    required this.seller,
    required this.customer,
    required this.items,
    this.company,
  });

  factory ControlOrder.fromJson(Map<String, dynamic> json) => ControlOrder(
    id: json['id'] as String,
    number: json['number'] as String,
    secondNumber: json['second_number'] as String?,
    status: json['status'] as String,
    total: (json['total'] as num).toDouble(),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    deliveryDate: json['delivery_date'] == null ? null : DateTime.parse(json['delivery_date'] as String),
    notes: json['notes'] as String?,
    logisticsNote: json['logistics_note'] as String?,
    syncError: json['sync_error'] as String?,
    seller: json['seller'] as String?,
    customer: OrderCustomer.fromJson(json['customer'] as Map<String, dynamic>),
    items: (json['items'] as List<dynamic>).map((e) => OrderLine.fromJson(e as Map<String, dynamic>)).toList(),
    company: json['company'] as String?,
  );

  final String id;
  final String number;
  final String? secondNumber;
  final String status;
  final double total;
  final DateTime createdAt;
  final DateTime? deliveryDate;
  final String? notes;
  final String? logisticsNote;
  final String? syncError;
  final String? seller;
  final OrderCustomer customer;
  final List<OrderLine> items;

  /// Nombre de la compañía del pedido (Agropecuaria o Montería TAT).
  final String? company;

  bool get failed => status == 'failed';

  String get numberLabel => secondNumber == null ? '#$number' : '#$number / #$secondNumber';
}
