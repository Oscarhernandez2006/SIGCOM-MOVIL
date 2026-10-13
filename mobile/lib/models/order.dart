import 'package:flutter/material.dart';

/// Agrupación de estados usada en los filtros (igual en la API).
enum OrderGroup {
  inProgress('in_progress', 'En curso'),
  synced('synced', 'Enviados'),
  issues('issues', 'Con novedad'),
  cancelled('cancelled', 'Anulados');

  const OrderGroup(this.key, this.label);

  final String key;
  final String label;
}

/// Etiquetas y colores de estado, iguales a los de la web (OrderStatusBadge).
class OrderStatusStyle {
  const OrderStatusStyle(this.label, this.color);

  final String label;
  final Color color;

  static const _styles = {
    'draft': OrderStatusStyle('Borrador', Color(0xFF64748B)),
    'pending_approval': OrderStatusStyle('Pendiente aprobación cartera', Color(0xFFCA8A04)),
    'pending_control': OrderStatusStyle('Esperando controlador', Color(0xFF2563EB)),
    'confirmed': OrderStatusStyle('Pendiente por envío', Color(0xFFEA580C)),
    'syncing': OrderStatusStyle('Enviando', Color(0xFFD97706)),
    'synced': OrderStatusStyle('Enviado a Siesa', Color(0xFF16A34A)),
    'failed': OrderStatusStyle('Error', Color(0xFFDC2626)),
    'cancelled': OrderStatusStyle('Cancelado', Color(0xFFDC2626)),
    'disapproved': OrderStatusStyle('Desaprobado', Color(0xFFDC2626)),
    'expired': OrderStatusStyle('Vencido', Color(0xFFDC2626)),
    'bounced': OrderStatusStyle('Rebotado', Color(0xFFC026D3)),
  };

  static OrderStatusStyle of(String status) => _styles[status] ?? OrderStatusStyle(status, const Color(0xFF64748B));

  /// Estado de trazabilidad en Siesa (Elaborado, Aprobado, Cumplido, ...).
  static OrderStatusStyle? siesa(String? state) {
    if (state == null || state.trim().isEmpty) return null;
    final s = state.toLowerCase();
    if (s.contains('elabora')) return const OrderStatusStyle('Elaborado', Color(0xFFB45309));
    if (s.contains('aprobad')) return const OrderStatusStyle('Aprobado', Color(0xFF0284C7));
    if (s.contains('cumplid')) return const OrderStatusStyle('Cumplido', Color(0xFF16A34A));
    if (s.contains('anulad')) return const OrderStatusStyle('Anulado', Color(0xFFDC2626));
    if (s.contains('reten')) return const OrderStatusStyle('Retenido', Color(0xFFEA580C));
    if (s.contains('factur')) return const OrderStatusStyle('Facturado', Color(0xFF4F46E5));
    if (s.contains('despach')) return const OrderStatusStyle('Despachado', Color(0xFF0D9488));
    return OrderStatusStyle(state, const Color(0xFF64748B));
  }
}

class OrderCustomer {
  const OrderCustomer({
    required this.name,
    required this.code,
    this.branch,
    this.priceList,
    this.paymentTerm,
    this.address,
    this.city,
    this.phone,
  });

  factory OrderCustomer.fromJson(Map<String, dynamic> json) => OrderCustomer(
    name: json['name'] as String,
    code: json['code'] as String,
    branch: json['branch'] as String?,
    priceList: json['price_list'] as String?,
    paymentTerm: json['payment_term'] as String?,
    address: json['address'] as String?,
    city: json['city'] as String?,
    phone: json['phone'] as String?,
  );

  final String name;
  final String code;
  final String? branch;
  final String? priceList;
  final String? paymentTerm;
  final String? address;
  final String? city;
  final String? phone;
}

class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.number,
    required this.secondNumber,
    required this.type,
    required this.status,
    required this.siesaStatus,
    required this.total,
    required this.itemsCount,
    required this.customer,
    required this.seller,
    required this.createdAt,
    required this.deliveryDate,
    required this.approvalDeadline,
    required this.note,
    this.downloadCount = 0,
    this.linkedNumber,
  });

  factory OrderSummary.fromJson(Map<String, dynamic> json) => OrderSummary(
    id: json['id'] as String,
    number: json['number'] as String,
    secondNumber: json['second_number'] as String?,
    type: json['type'] as String? ?? 'corte',
    status: json['status'] as String,
    siesaStatus: json['siesa_status'] as String?,
    total: (json['total'] as num).toDouble(),
    itemsCount: (json['items_count'] as num).toInt(),
    customer: OrderCustomer.fromJson(json['customer'] as Map<String, dynamic>),
    seller: json['seller'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    deliveryDate: _date(json['delivery_date']),
    approvalDeadline: _date(json['approval_deadline']),
    note: json['note'] as String?,
    downloadCount: (json['download_count'] as num?)?.toInt() ?? 0,
    linkedNumber: json['linked_number'] as String?,
  );

  final String id;
  final String number;
  final String? secondNumber;
  final String type;
  final String status;
  final String? siesaStatus;
  final double total;
  final int itemsCount;
  final OrderCustomer customer;
  final String? seller;
  final DateTime createdAt;
  final DateTime? deliveryDate;
  final DateTime? approvalDeadline;
  final String? note;

  /// Veces que logística descargó el documento del pedido.
  final int downloadCount;
  final String? linkedNumber;

  String get numberLabel => secondNumber == null ? '#$number' : '#$number / #$secondNumber';
}

class OrderGroupTotals {
  const OrderGroupTotals({required this.count, required this.total});

  factory OrderGroupTotals.fromJson(Object? json) {
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    return OrderGroupTotals(
      count: (map['count'] as num?)?.toInt() ?? 0,
      total: (map['total'] as num?)?.toDouble() ?? 0,
    );
  }

  final int count;
  final double total;
}

class OrdersResult {
  const OrdersResult({required this.orders, required this.summary, required this.limited});

  factory OrdersResult.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>? ?? const {};
    return OrdersResult(
      orders: (json['orders'] as List<dynamic>).map((e) => OrderSummary.fromJson(e as Map<String, dynamic>)).toList(),
      summary: {for (final g in OrderGroup.values) g: OrderGroupTotals.fromJson(summary[g.key])},
      limited: json['limited'] as bool? ?? false,
    );
  }

  final List<OrderSummary> orders;
  final Map<OrderGroup, OrderGroupTotals> summary;
  final bool limited;
}

class OrderLine {
  const OrderLine({
    required this.sku,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.discountPct,
    required this.total,
  });

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
    sku: json['sku'] as String,
    name: json['name'] as String,
    unit: json['unit'] as String?,
    quantity: (json['quantity'] as num).toDouble(),
    unitPrice: (json['unit_price'] as num).toDouble(),
    discountPct: (json['discount_pct'] as num).toDouble(),
    total: (json['total'] as num).toDouble(),
  );

  final String sku;
  final String name;
  final String? unit;
  final double quantity;
  final double unitPrice;
  final double discountPct;
  final double total;
}

/// Quién generó el pedido, cartera, Siesa y descargas (seguimiento de pedidos).
class OrderTracking {
  const OrderTracking({
    this.sellerDocument,
    this.sellerCode,
    this.linkedNumber,
    this.carteraBalance,
    this.approvedBy,
    this.approvedAt,
    this.siesaPreviousStatus,
    this.siesaDocument,
    this.downloadCount = 0,
    this.downloadedAt,
    this.downloadedBy,
  });

  static OrderTracking? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return OrderTracking(
      sellerDocument: json['seller_document'] as String?,
      sellerCode: json['seller_code'] as String?,
      linkedNumber: json['linked_number'] as String?,
      carteraBalance: (json['cartera_balance'] as num?)?.toDouble(),
      approvedBy: json['approved_by'] as String?,
      approvedAt: _date(json['approved_at']),
      siesaPreviousStatus: json['siesa_previous_status'] as String?,
      siesaDocument: json['siesa_document'] as String?,
      downloadCount: (json['download_count'] as num?)?.toInt() ?? 0,
      downloadedAt: _date(json['downloaded_at']),
      downloadedBy: json['downloaded_by'] as String?,
    );
  }

  final String? sellerDocument;
  final String? sellerCode;
  final String? linkedNumber;
  final double? carteraBalance;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? siesaPreviousStatus;
  final String? siesaDocument;
  final int downloadCount;
  final DateTime? downloadedAt;
  final String? downloadedBy;
}

class OrderDetail {
  const OrderDetail({
    required this.summary,
    required this.subtotal,
    required this.taxes,
    required this.notes,
    required this.logisticsNote,
    required this.deliveryType,
    required this.deliverySchedule,
    required this.syncedAt,
    this.tracking,
    required this.items,
  });

  factory OrderDetail.fromJson(Map<String, dynamic> json) => OrderDetail(
    summary: OrderSummary.fromJson({
      ...json,
      'items_count': (json['items'] as List<dynamic>).length,
      'note': json['sync_error'] ?? json['disapproval_reason'] ?? json['cancel_reason'],
    }),
    subtotal: (json['subtotal'] as num).toDouble(),
    taxes: (json['taxes'] as num).toDouble(),
    notes: json['notes'] as String?,
    logisticsNote: json['logistics_note'] as String?,
    deliveryType: json['delivery_type'] as String?,
    deliverySchedule: json['delivery_schedule'] as String?,
    syncedAt: _date(json['synced_at']),
    tracking: OrderTracking.fromJson(json['tracking']),
    items: (json['items'] as List<dynamic>).map((e) => OrderLine.fromJson(e as Map<String, dynamic>)).toList(),
  );

  final OrderSummary summary;
  final double subtotal;
  final double taxes;
  final String? notes;
  final String? logisticsNote;
  final String? deliveryType;
  final String? deliverySchedule;
  final DateTime? syncedAt;
  final OrderTracking? tracking;
  final List<OrderLine> items;
}

DateTime? _date(Object? value) => value is String ? DateTime.parse(value).toLocal() : null;
