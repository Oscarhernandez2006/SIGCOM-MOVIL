class FeaturedProduct {
  const FeaturedProduct({
    required this.sku,
    required this.name,
    required this.unit,
    required this.stock,
    required this.inCatalog,
  });

  factory FeaturedProduct.fromJson(Map<String, dynamic> json) => FeaturedProduct(
    sku: json['sku'] as String,
    name: json['name'] as String,
    unit: json['unit'] as String?,
    stock: (json['stock'] as num?)?.toDouble(),
    inCatalog: json['in_catalog'] as bool? ?? true,
  );

  final String sku;
  final String name;
  final String? unit;

  /// Null si el SKU ya no existe en el inventario de la compañía.
  final double? stock;
  final bool inCatalog;
}
