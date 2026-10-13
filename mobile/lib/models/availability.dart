class AvailableProduct {
  const AvailableProduct({
    required this.sku,
    required this.name,
    required this.unit,
    required this.stock,
    required this.price,
    required this.category,
  });

  factory AvailableProduct.fromJson(Map<String, dynamic> json) => AvailableProduct(
    sku: json['sku'] as String,
    name: json['name'] as String,
    unit: json['unit'] as String?,
    stock: (json['stock'] as num).toDouble(),
    price: (json['price'] as num?)?.toDouble(),
    category: json['category'] as String?,
  );

  final String sku;
  final String name;
  final String? unit;
  final double stock;
  final double? price;
  final String? category;

  /// Igual que en pedidos: CERDO es su categoría y todo lo demás va a Res.
  bool get isPork => category?.toUpperCase() == 'CERDO';
}

class PriceListRef {
  const PriceListRef({required this.code, required this.name});

  factory PriceListRef.fromJson(Map<String, dynamic> json) =>
      PriceListRef(code: json['code'] as String, name: json['name'] as String);

  final String code;
  final String name;

  String get label => '$name ($code)';
}
