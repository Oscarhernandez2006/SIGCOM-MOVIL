import '../utils/format.dart';

/// Tipo de filtro de fechas de cada reporte (igual que en la web).
enum ReportFilter { day, range, month, period }

class ReportDef {
  const ReportDef(this.key, this.title, this.description, this.filter);

  final String key;
  final String title;
  final String description;
  final ReportFilter filter;
}

/// Catálogo de reportes de la web (/admin/reportes), en el mismo orden.
const reportCatalog = [
  ReportDef(
    'inventory',
    'Resumen de inventario por día',
    'Lo vendido en el día, el stock que queda y las referencias agotadas.',
    ReportFilter.day,
  ),
  ReportDef(
    'product-sales',
    'Productos vendidos',
    'Cantidad vendida e ingresos por producto en un rango de fechas.',
    ReportFilter.range,
  ),
  ReportDef(
    'sales-summary',
    'Ventas por cliente y producto',
    'Cuánto se ha vendido a cada cliente o de cada producto en un rango de fechas.',
    ReportFilter.range,
  ),
  ReportDef(
    'seller-ranking',
    'Ranking de vendedores',
    'Los vendedores que más venden y los que menos en un rango de fechas.',
    ReportFilter.range,
  ),
  ReportDef(
    'seller-product',
    'Ventas por vendedor y producto',
    'Cuánto vendió un vendedor de un producto en un rango de fechas.',
    ReportFilter.range,
  ),
  ReportDef(
    'product-seller',
    'Mejor vendedor por producto',
    'Por cada producto, quién fue el vendedor que más lo vendió (ranking).',
    ReportFilter.range,
  ),
  ReportDef(
    'seller-sales',
    'Ventas por vendedor (mensual)',
    'Presupuesto vs. ventas y kilos por vendedor, con cumplimiento y valor promedio por kilo.',
    ReportFilter.month,
  ),
  ReportDef(
    'vendor-product-sales',
    'Ventas acumuladas por vendedor y producto',
    'Por cada vendedor, el desglose de productos vendidos en el mes (cantidad y venta neta).',
    ReportFilter.period,
  ),
];

String formatReportValue(Object? value, String format) {
  if (value == null) return '—';
  if (value is! num) return value.toString();
  final v = value.toDouble();
  return switch (format) {
    'money' => formatMoney(v),
    'int' => formatInt(v),
    'pct' => formatPercent(v),
    'qty' => formatQuantity(v),
    _ => value.toString(),
  };
}

class ReportValue {
  const ReportValue({required this.label, required this.value, required this.format});

  factory ReportValue.fromJson(Map<String, dynamic> json) =>
      ReportValue(label: json['label'] as String, value: json['value'], format: json['format'] as String? ?? 'text');

  final String label;
  final Object? value;
  final String format;

  String get text => formatReportValue(value, format);
}

class ReportRow {
  const ReportRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.format,
    required this.details,
    required this.highlight,
    required this.items,
  });

  factory ReportRow.fromJson(Map<String, dynamic> json) => ReportRow(
    title: json['title'] as String,
    subtitle: json['subtitle'] as String?,
    value: json['value'],
    format: json['format'] as String? ?? 'text',
    details: [
      for (final d in json['details'] as List<dynamic>? ?? const []) ReportValue.fromJson(d as Map<String, dynamic>),
    ],
    highlight: json['highlight'] as bool? ?? false,
    items: [for (final i in json['items'] as List<dynamic>? ?? const []) ReportRow.fromJson(i as Map<String, dynamic>)],
  );

  final String title;
  final String? subtitle;
  final Object? value;
  final String format;
  final List<ReportValue> details;
  final bool highlight;
  final List<ReportRow> items;

  String get valueText => formatReportValue(value, format);

  bool matches(String query) =>
      title.toLowerCase().contains(query) ||
      (subtitle?.toLowerCase().contains(query) ?? false) ||
      items.any((i) => i.matches(query));
}

class ReportData {
  const ReportData({
    required this.title,
    required this.subtitle,
    required this.kpis,
    required this.rows,
    required this.totalRow,
    required this.sellers,
    required this.products,
  });

  factory ReportData.fromJson(Map<String, dynamic> json) {
    final options = json['options'] as Map<String, dynamic>? ?? const {};
    return ReportData(
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      kpis: [for (final k in json['kpis'] as List<dynamic>) ReportValue.fromJson(k as Map<String, dynamic>)],
      rows: [for (final r in json['rows'] as List<dynamic>) ReportRow.fromJson(r as Map<String, dynamic>)],
      totalRow: json['total_row'] == null ? null : ReportRow.fromJson(json['total_row'] as Map<String, dynamic>),
      sellers: [
        for (final s in options['sellers'] as List<dynamic>? ?? const [])
          (id: s['id'] as String, name: s['name'] as String),
      ],
      products: [
        for (final p in options['products'] as List<dynamic>? ?? const [])
          (id: p['sku'] as String, name: p['name'] as String),
      ],
    );
  }

  final String title;
  final String? subtitle;
  final List<ReportValue> kpis;
  final List<ReportRow> rows;
  final ReportRow? totalRow;
  final List<({String id, String name})> sellers;
  final List<({String id, String name})> products;
}

/// Filtros elegidos en el visor; se envían tal cual a la API.
class ReportQuery {
  const ReportQuery({this.from, this.to, this.date, this.month, this.groupBy, this.sellerId, this.sku});

  final DateTime? from;
  final DateTime? to;
  final DateTime? date;
  final DateTime? month;
  final String? groupBy;
  final String? sellerId;
  final String? sku;

  Map<String, String> toParams() => {
    if (from != null) 'from': formatApiDate(from!),
    if (to != null) 'to': formatApiDate(to!),
    if (date != null) 'date': formatApiDate(date!),
    if (month != null) 'month': '${month!.year}-${month!.month.toString().padLeft(2, '0')}',
    'group_by': ?groupBy,
    'seller_id': ?sellerId,
    'sku': ?sku,
  };
}
