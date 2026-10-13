import '../utils/format.dart';

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

List<T> _list<T>(Object? json, T Function(Map<String, dynamic>) parse) =>
    json is List ? json.map((e) => parse(e as Map<String, dynamic>)).toList() : <T>[];

/// Fila genérica de ranking (vendedor, producto o cliente).
class RankItem {
  const RankItem({
    required this.name,
    required this.revenue,
    this.code,
    this.orders,
    this.quantity,
    this.profit,
    this.marginPct,
    this.kilos,
  });

  factory RankItem.fromJson(Map<String, dynamic> json) => RankItem(
    name: json['name'] as String,
    revenue: _d(json['revenue'] ?? json['total']),
    code: json['code'] as String?,
    orders: (json['orders'] as num?)?.toInt(),
    quantity: (json['quantity'] as num?)?.toDouble(),
    profit: (json['profit'] as num?)?.toDouble(),
    marginPct: (json['margin_pct'] as num?)?.toDouble(),
    kilos: (json['kilos'] as num?)?.toDouble(),
  );

  final String name;
  final double revenue;
  final String? code;
  final int? orders;
  final double? quantity;
  final double? profit;
  final double? marginPct;
  final double? kilos;
}

class CompanyMargin {
  const CompanyMargin({
    required this.revenue,
    required this.profit,
    required this.marginPct,
    required this.kilos,
    required this.bySeller,
    required this.byProduct,
  });

  static CompanyMargin? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return CompanyMargin(
      revenue: _d(json['revenue']),
      profit: _d(json['profit']),
      marginPct: _d(json['margin_pct']),
      kilos: _d(json['kilos']),
      bySeller: _list(json['by_seller'], RankItem.fromJson),
      byProduct: _list(json['by_product'], RankItem.fromJson),
    );
  }

  final double revenue;
  final double profit;
  final double marginPct;
  final double kilos;
  final List<RankItem> bySeller;
  final List<RankItem> byProduct;
}

class CompanyStats {
  const CompanyStats({
    required this.id,
    required this.name,
    required this.revenue,
    required this.orders,
    required this.units,
    required this.avgTicket,
    required this.customers,
    required this.trend,
    required this.topProducts,
    required this.topCustomers,
    required this.topSellers,
    required this.margin,
    this.unit = QtyUnit.kilos,
  });

  factory CompanyStats.fromJson(Map<String, dynamic> json) {
    final totals = json['totals'] as Map<String, dynamic>;
    return CompanyStats(
      id: json['id'] as String,
      name: json['name'] as String,
      unit: QtyUnit(json['unit'] as String? ?? 'kg'),
      revenue: _d(totals['revenue']),
      orders: (totals['orders'] as num).toInt(),
      units: _d(totals['units']),
      avgTicket: _d(totals['avg_ticket']),
      customers: (totals['customers'] as num).toInt(),
      trend: [
        for (final p in json['trend'] as List<dynamic>)
          (date: DateTime.parse(p['date'] as String), label: p['label'] as String?, revenue: _d(p['revenue'])),
      ],
      topProducts: _list(json['top_products'], RankItem.fromJson),
      topCustomers: _list(json['top_customers'], RankItem.fromJson),
      topSellers: _list(json['top_sellers'], RankItem.fromJson),
      margin: CompanyMargin.fromJson(json['margin']),
    );
  }

  final String id;
  final String name;
  final double revenue;
  final int orders;
  final double units;
  final double avgTicket;
  final int customers;
  final List<({DateTime date, String? label, double revenue})> trend;
  final List<RankItem> topProducts;
  final List<RankItem> topCustomers;
  final List<RankItem> topSellers;
  final CompanyMargin? margin;

  /// Kilos o unidades (Carnes Frías) para las cantidades del margen.
  final QtyUnit unit;

  /// Igual que la web: con margen (Agropecuaria) la venta es la facturación del ERP.
  double get sales => margin?.revenue ?? revenue;
}

class SellersRanking {
  const SellersRanking({
    required this.periodLabel,
    required this.salesTotal,
    required this.sales,
    required this.ordersTotal,
    required this.ordersCount,
    required this.orders,
  });

  factory SellersRanking.fromJson(Map<String, dynamic> json) {
    final sales = json['sales'] as Map<String, dynamic>;
    final orders = json['orders'] as Map<String, dynamic>;
    return SellersRanking(
      periodLabel: json['period_label'] as String,
      salesTotal: _d(sales['total']),
      sales: _list(sales['sellers'], RankItem.fromJson),
      ordersTotal: _d(orders['total']),
      ordersCount: (orders['count'] as num?)?.toInt() ?? 0,
      orders: _list(orders['sellers'], RankItem.fromJson),
    );
  }

  final String periodLabel;
  final double salesTotal;
  final List<RankItem> sales;
  final double ordersTotal;
  final int ordersCount;
  final List<RankItem> orders;
}
