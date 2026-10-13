import '../utils/format.dart';

class SellerRef {
  const SellerRef({required this.id, required this.name});

  factory SellerRef.fromJson(Map<String, dynamic> json) =>
      SellerRef(id: json['id'] as String, name: json['name'] as String);

  final String id;
  final String name;
}

class Amounts {
  const Amounts({this.revenue, this.kilos});

  static Amounts? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return Amounts(revenue: _toDouble(json['revenue']), kilos: _toDouble(json['kilos']));
  }

  final double? revenue;
  final double? kilos;
}

class Profitability {
  const Profitability({required this.cost, required this.margin, this.marginPct});

  static Profitability? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return Profitability(
      cost: _toDouble(json['cost']) ?? 0,
      margin: _toDouble(json['margin']) ?? 0,
      marginPct: _toDouble(json['margin_pct']),
    );
  }

  final double cost;
  final double margin;
  final double? marginPct;
}

class TrendPoint {
  const TrendPoint({required this.date, required this.revenue});

  factory TrendPoint.fromJson(Map<String, dynamic> json) =>
      TrendPoint(date: DateTime.parse(json['date'] as String), revenue: _toDouble(json['revenue']) ?? 0);

  final DateTime date;
  final double revenue;
}

class SalesLine {
  const SalesLine({required this.name, required this.kilos, required this.revenue, this.ref});

  factory SalesLine.fromJson(Map<String, dynamic> json) => SalesLine(
    name: json['name'] as String,
    ref: json['ref'] as String?,
    kilos: _toDouble(json['kilos']) ?? 0,
    revenue: _toDouble(json['revenue']) ?? 0,
  );

  final String name;
  final String? ref;
  final double kilos;
  final double revenue;
}

class SalesCategory {
  const SalesCategory({required this.name, required this.kilos, required this.revenue, required this.items});

  factory SalesCategory.fromJson(Map<String, dynamic> json) => SalesCategory(
    name: json['category'] as String,
    kilos: _toDouble(json['kilos']) ?? 0,
    revenue: _toDouble(json['revenue']) ?? 0,
    items: _list(json['items'], SalesLine.fromJson),
  );

  final String name;
  final double kilos;
  final double revenue;
  final List<SalesLine> items;
}

class ClientBudget {
  const ClientBudget({
    required this.code,
    required this.name,
    required this.branch,
    required this.targetRevenue,
    required this.revenue,
    required this.compliance,
  });

  factory ClientBudget.fromJson(Map<String, dynamic> json) => ClientBudget(
    code: json['code'] as String,
    name: json['name'] as String,
    branch: json['branch'] as String?,
    targetRevenue: _toDouble(json['target_revenue']) ?? 0,
    revenue: _toDouble(json['revenue']) ?? 0,
    compliance: _toDouble(json['compliance']),
  );

  final String code;
  final String name;
  final String? branch;
  final double targetRevenue;
  final double revenue;
  final double? compliance;
}

class CustomerSummary {
  const CustomerSummary({
    required this.name,
    required this.code,
    required this.branch,
    required this.city,
    required this.orders,
    required this.revenue,
    required this.lastPurchase,
  });

  factory CustomerSummary.fromJson(Map<String, dynamic> json) => CustomerSummary(
    name: json['name'] as String,
    code: json['code'] as String,
    branch: json['branch'] as String?,
    city: json['city'] as String?,
    orders: (json['orders'] as num).toInt(),
    revenue: _toDouble(json['revenue']) ?? 0,
    lastPurchase: json['last_purchase'] == null ? null : DateTime.parse(json['last_purchase'] as String).toLocal(),
  );

  final String name;
  final String code;
  final String? branch;
  final String? city;
  final int orders;
  final double revenue;
  final DateTime? lastPurchase;

  bool matches(String query) => [name, code, branch, city].any((v) => v != null && v.toLowerCase().contains(query));
}

class DashboardData {
  const DashboardData({
    required this.seller,
    required this.sellers,
    required this.budget,
    required this.sales,
    required this.compliance,
    required this.projection,
    required this.profitability,
    required this.growth,
    required this.salesError,
    required this.trend,
    required this.categories,
    required this.topCustomers,
    required this.customersNotBuying,
    this.clientBudgets,
    required this.ordersCount,
    required this.ordersRevenue,
    required this.ordersKilos,
    required this.ordersCustomers,
    required this.ordersAvgTicket,
    required this.workingDaysTotal,
    required this.workingDaysElapsed,
    required this.generatedAt,
    this.unit = QtyUnit.kilos,
    this.salesFromOrders = false,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final orders = json['orders'] as Map<String, dynamic>;
    final days = json['working_days'] as Map<String, dynamic>;
    return DashboardData(
      seller: json['seller'] == null ? null : SellerRef.fromJson(json['seller'] as Map<String, dynamic>),
      sellers: (json['sellers'] as List<dynamic>).map((e) => SellerRef.fromJson(e as Map<String, dynamic>)).toList(),
      budget: Amounts.fromJson(json['budget'])!,
      sales: Amounts.fromJson(json['sales']),
      compliance: Amounts.fromJson(json['compliance']),
      projection: Amounts.fromJson(json['projection']),
      profitability: Profitability.fromJson(json['profitability']),
      growth: Amounts.fromJson(json['growth']),
      salesError: json['sales_error'] as String?,
      trend: _list(json['trend'], TrendPoint.fromJson),
      categories: _list(json['categories'], SalesCategory.fromJson),
      topCustomers: _list(json['top_customers'], CustomerSummary.fromJson),
      customersNotBuying: _list(json['customers_not_buying'], CustomerSummary.fromJson),
      clientBudgets: json['client_budgets'] == null ? null : _list(json['client_budgets'], ClientBudget.fromJson),
      ordersCount: (orders['count'] as num).toInt(),
      ordersRevenue: _toDouble(orders['revenue']) ?? 0,
      ordersKilos: _toDouble(orders['kilos']) ?? 0,
      ordersCustomers: (orders['customers'] as num?)?.toInt() ?? 0,
      ordersAvgTicket: _toDouble(orders['avg_ticket']) ?? 0,
      workingDaysTotal: (days['total'] as num).toInt(),
      workingDaysElapsed: (days['elapsed'] as num).toInt(),
      generatedAt: DateTime.parse(json['generated_at'] as String).toLocal(),
      unit: QtyUnit(json['unit'] as String? ?? 'kg'),
      salesFromOrders: json['sales_source'] == 'orders',
    );
  }

  final SellerRef? seller;
  final List<SellerRef> sellers;
  final Amounts budget;
  final Amounts? sales;
  final Amounts? compliance;
  final Amounts? projection;
  final Profitability? profitability;

  /// Variación (ratio) frente al periodo anterior de igual duración.
  final Amounts? growth;
  final String? salesError;
  final List<TrendPoint> trend;
  final List<SalesCategory> categories;
  final List<CustomerSummary> topCustomers;
  final List<CustomerSummary> customersNotBuying;

  /// Meta vs. venta por cliente/tienda (solo negocios nacionales).
  final List<ClientBudget>? clientBudgets;
  final int ordersCount;
  final double ordersRevenue;
  final double ordersKilos;
  final int ordersCustomers;
  final double ordersAvgTicket;
  final int workingDaysTotal;
  final int workingDaysElapsed;
  final DateTime generatedAt;

  /// Las cantidades (`kilos`) son unidades en Carnes Frías.
  final QtyUnit unit;

  /// Montería TAT: la venta sale de los pedidos de la app, no de la facturación de Siesa.
  final bool salesFromOrders;
}

double? _toDouble(Object? value) => value is num ? value.toDouble() : null;

List<T> _list<T>(Object? json, T Function(Map<String, dynamic>) parse) =>
    json is List ? json.map((e) => parse(e as Map<String, dynamic>)).toList() : <T>[];
