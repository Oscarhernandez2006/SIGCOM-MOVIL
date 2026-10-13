class PriceListInfo {
  const PriceListInfo({
    required this.code,
    required this.name,
    required this.items,
    required this.clients,
    required this.updatedAt,
  });

  factory PriceListInfo.fromJson(Map<String, dynamic> json) => PriceListInfo(
    code: json['code'] as String,
    name: json['name'] as String? ?? json['code'] as String,
    items: (json['items'] as num).toInt(),
    clients: (json['clients'] as num).toInt(),
    updatedAt: json['updated_at'] == null ? null : DateTime.parse(json['updated_at'] as String).toLocal(),
  );

  final String code;
  final String name;
  final int items;

  /// Clientes que tienen asignada esta lista en Siesa.
  final int clients;
  final DateTime? updatedAt;
}

class PriceListsResult {
  const PriceListsResult({required this.lists, required this.canSync});

  factory PriceListsResult.fromJson(Map<String, dynamic> json) => PriceListsResult(
    lists: (json['lists'] as List<dynamic>).map((e) => PriceListInfo.fromJson(e as Map<String, dynamic>)).toList(),
    canSync: json['can_sync'] as bool? ?? false,
  );

  final List<PriceListInfo> lists;
  final bool canSync;
}

class PriceListItem {
  const PriceListItem({required this.sku, required this.name, required this.unit, required this.price});

  factory PriceListItem.fromJson(Map<String, dynamic> json) => PriceListItem(
    sku: json['sku'] as String,
    name: json['name'] as String,
    unit: json['unit'] as String?,
    price: (json['price'] as num).toDouble(),
  );

  final String sku;
  final String name;
  final String? unit;
  final double price;
}

class PriceListSyncResult {
  const PriceListSyncResult({
    required this.lists,
    required this.created,
    required this.updated,
    required this.removed,
    required this.total,
  });

  factory PriceListSyncResult.fromJson(Map<String, dynamic> json) => PriceListSyncResult(
    lists: (json['lists'] as num).toInt(),
    created: (json['created'] as num).toInt(),
    updated: (json['updated'] as num).toInt(),
    removed: (json['removed'] as num).toInt(),
    total: (json['total'] as num).toInt(),
  );

  final int lists;
  final int created;
  final int updated;
  final int removed;
  final int total;
}
