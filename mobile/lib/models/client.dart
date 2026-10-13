import 'ordering.dart';

DateTime? _date(Object? value) => value is String ? DateTime.parse(value).toLocal() : null;

class ClientRow {
  const ClientRow({
    required this.id,
    required this.code,
    required this.name,
    required this.branch,
    required this.branchName,
    required this.city,
    required this.priceList,
    required this.priceListName,
    required this.sellerCode,
    required this.seller,
    required this.phone,
  });

  factory ClientRow.fromJson(Map<String, dynamic> json) => ClientRow(
    id: json['id'] as String,
    code: json['code'] as String,
    name: json['name'] as String,
    branch: json['branch'] as String?,
    branchName: json['branch_name'] as String?,
    city: json['city'] as String?,
    priceList: json['price_list'] as String?,
    priceListName: json['price_list_name'] as String?,
    sellerCode: json['seller_code'] as String?,
    seller: json['seller'] as String?,
    phone: json['phone'] as String?,
  );

  final String id;
  final String code;
  final String name;
  final String? branch;
  final String? branchName;
  final String? city;
  final String? priceList;
  final String? priceListName;
  final String? sellerCode;
  final String? seller;
  final String? phone;

  String? get sellerLabel =>
      seller ?? (sellerCode == null || sellerCode!.trim().isEmpty ? null : 'Vendedor $sellerCode');
}

class ClientsPage {
  const ClientsPage({
    required this.clients,
    required this.total,
    required this.page,
    required this.hasMore,
    required this.canSync,
  });

  factory ClientsPage.fromJson(Map<String, dynamic> json) => ClientsPage(
    clients: (json['clients'] as List<dynamic>).map((e) => ClientRow.fromJson(e as Map<String, dynamic>)).toList(),
    total: (json['total'] as num).toInt(),
    page: (json['page'] as num).toInt(),
    hasMore: json['has_more'] as bool? ?? false,
    canSync: json['can_sync'] as bool? ?? false,
  );

  final List<ClientRow> clients;
  final int total;
  final int page;
  final bool hasMore;
  final bool canSync;
}

class ClientSeller {
  const ClientSeller({required this.code, required this.name, required this.clients});

  factory ClientSeller.fromJson(Map<String, dynamic> json) => ClientSeller(
    code: json['code'] as String,
    name: json['name'] as String,
    clients: (json['clients'] as num).toInt(),
  );

  /// 'none' agrupa los clientes sin vendedor.
  final String code;
  final String name;
  final int clients;
}

/// Ubicación que capturó un vendedor al tomar un pedido.
class ClientLocationInfo {
  const ClientLocationInfo({
    required this.address,
    required this.reference,
    required this.neighborhood,
    required this.city,
    required this.department,
    required this.phone,
    required this.seller,
    required this.updatedAt,
  });

  factory ClientLocationInfo.fromJson(Map<String, dynamic> json) => ClientLocationInfo(
    address: json['address'] as String?,
    reference: json['reference'] as String?,
    neighborhood: json['neighborhood'] as String?,
    city: json['city'] as String?,
    department: json['department'] as String?,
    phone: json['phone'] as String?,
    seller: json['seller'] as String?,
    updatedAt: _date(json['updated_at']),
  );

  final String? address;
  final String? reference;
  final String? neighborhood;
  final String? city;
  final String? department;
  final String? phone;
  final String? seller;
  final DateTime? updatedAt;
}

class ClientRecentOrder {
  const ClientRecentOrder({
    required this.id,
    required this.number,
    required this.secondNumber,
    required this.status,
    required this.total,
    required this.createdAt,
    required this.seller,
  });

  factory ClientRecentOrder.fromJson(Map<String, dynamic> json) => ClientRecentOrder(
    id: json['id'] as String,
    number: json['number'] as String,
    secondNumber: json['second_number'] as String?,
    status: json['status'] as String,
    total: (json['total'] as num).toDouble(),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    seller: json['seller'] as String?,
  );

  final String id;
  final String number;
  final String? secondNumber;
  final String status;
  final double total;
  final DateTime createdAt;
  final String? seller;

  String get numberLabel => secondNumber == null ? '#$number' : '#$number / #$secondNumber';
}

class ClientDetail {
  const ClientDetail({
    required this.row,
    required this.paymentTerm,
    required this.address,
    required this.neighborhood,
    required this.department,
    required this.email,
    required this.schedule,
    required this.locations,
    required this.ordersCount,
    required this.ordersTotal,
    required this.recentOrders,
  });

  factory ClientDetail.fromJson(Map<String, dynamic> json) {
    final stats = json['orders_90d'] as Map<String, dynamic>? ?? const {};
    return ClientDetail(
      row: ClientRow.fromJson(json),
      paymentTerm: json['payment_term'] as String?,
      address: json['address'] as String?,
      neighborhood: json['neighborhood'] as String?,
      department: json['department'] as String?,
      email: json['email'] as String?,
      schedule: DeliverySchedule.fromJson(json['delivery_schedule']),
      locations: (json['locations'] as List<dynamic>? ?? const [])
          .map((e) => ClientLocationInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      ordersCount: (stats['count'] as num?)?.toInt() ?? 0,
      ordersTotal: (stats['total'] as num?)?.toDouble() ?? 0,
      recentOrders: (json['recent_orders'] as List<dynamic>? ?? const [])
          .map((e) => ClientRecentOrder.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final ClientRow row;
  final String? paymentTerm;
  final String? address;
  final String? neighborhood;
  final String? department;
  final String? email;
  final DeliverySchedule? schedule;
  final List<ClientLocationInfo> locations;

  /// Pedidos vigentes de los últimos 90 días.
  final int ordersCount;
  final double ordersTotal;
  final List<ClientRecentOrder> recentOrders;
}

class ClientSyncResult {
  const ClientSyncResult({required this.created, required this.updated, required this.removed, required this.total});

  factory ClientSyncResult.fromJson(Map<String, dynamic> json) => ClientSyncResult(
    created: (json['created'] as num).toInt(),
    updated: (json['updated'] as num).toInt(),
    removed: (json['removed'] as num).toInt(),
    total: (json['total'] as num).toInt(),
  );

  final int created;
  final int updated;
  final int removed;
  final int total;
}
