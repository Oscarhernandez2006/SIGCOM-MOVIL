/// Datos para tomar pedidos (la API móvil los obtiene del SIGCOM web).
class OrderingContext {
  const OrderingContext({
    required this.scheduleEnabled,
    required this.open,
    required this.close,
    required this.isOpen,
    required this.minTotal,
    required this.requiresLocation,
    required this.featured,
  });

  factory OrderingContext.fromJson(Map<String, dynamic> json) {
    final schedule = json['schedule'] as Map<String, dynamic>;
    return OrderingContext(
      scheduleEnabled: schedule['enabled'] as bool,
      open: schedule['open'] as String,
      close: schedule['close'] as String,
      isOpen: schedule['is_open'] as bool,
      minTotal: (json['min_total'] as num).toDouble(),
      requiresLocation: json['requires_location'] as bool,
      featured: [
        for (final f in json['featured'] as List<dynamic>) (sku: f['sku'] as String, name: f['name'] as String),
      ],
    );
  }

  final bool scheduleEnabled;
  final String open;
  final String close;
  final bool isOpen;
  final double minTotal;
  final bool requiresLocation;
  final List<({String sku, String name})> featured;
}

/// Horario de recibido del cliente; días 0=lunes … 6=domingo (igual que la web).
class DeliverySchedule {
  const DeliverySchedule({required this.days, required this.hourFrom, required this.hourTo});

  static DeliverySchedule? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final days = (json['days'] as List<dynamic>? ?? const []).map((d) => (d as num).toInt()).toSet();
    final from = json['hourFrom'] as String?;
    final to = json['hourTo'] as String?;
    if (days.isEmpty || from == null || to == null) return null;
    return DeliverySchedule(days: days, hourFrom: from, hourTo: to);
  }

  static const weekDays = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

  final Set<int> days;
  final String hourFrom;
  final String hourTo;

  bool get isComplete => days.isNotEmpty;

  DeliverySchedule copyWith({Set<int>? days, String? hourFrom, String? hourTo}) =>
      DeliverySchedule(days: days ?? this.days, hourFrom: hourFrom ?? this.hourFrom, hourTo: hourTo ?? this.hourTo);

  Map<String, dynamic> toJson() => {'days': (days.toList()..sort()), 'hour_from': hourFrom, 'hour_to': hourTo};

  /// "Lunes a viernes de 7 a. m. a 5 p. m.", igual que formatDeliverySchedule de la web.
  String get label {
    final sorted = days.toList()..sort();
    final runs = <List<int>>[];
    for (final day in sorted) {
      if (runs.isNotEmpty && day == runs.last.last + 1) {
        runs.last.add(day);
      } else {
        runs.add([day]);
      }
    }
    final parts = [
      for (final run in runs)
        run.length == 1 ? weekDays[run.first] : '${weekDays[run.first]} a ${weekDays[run.last].toLowerCase()}',
    ];
    final text = parts.length == 1
        ? parts.first
        : '${[for (final (i, p) in parts.sublist(0, parts.length - 1).indexed) i == 0 ? p : p.toLowerCase()].join(', ')}'
              ' y ${parts.last.toLowerCase()}';
    return '$text de ${hour12(hourFrom)} a ${hour12(hourTo)}';
  }

  static String hour12(String value) {
    final parts = value.split(':');
    final h = int.tryParse(parts.first);
    final m = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    if (h == null || m == null) return value;
    final period = h < 12 ? 'a. m.' : 'p. m.';
    final hour = h % 12 == 0 ? 12 : h % 12;
    return '$hour${m == 0 ? '' : ':${m.toString().padLeft(2, '0')}'} $period';
  }
}

class OrderClient {
  const OrderClient({
    required this.id,
    required this.code,
    required this.name,
    this.branch,
    this.branchName,
    this.priceList,
    this.priceListName,
    this.paymentTerm,
    this.address,
    this.city,
    this.phone,
    this.email,
    this.deliverySchedule,
  });

  factory OrderClient.fromJson(Map<String, dynamic> json) => OrderClient(
    id: json['id'] as String,
    code: json['code'] as String,
    name: json['name'] as String,
    branch: json['branch'] as String?,
    branchName: json['branch_name'] as String?,
    priceList: json['price_list'] as String?,
    priceListName: json['price_list_name'] as String?,
    paymentTerm: json['payment_term'] as String?,
    address: json['address'] as String?,
    city: json['city'] as String?,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    deliverySchedule: DeliverySchedule.fromJson(json['delivery_schedule']),
  );

  final String id;
  final String code;
  final String name;
  final String? branch;
  final String? branchName;
  final String? priceList;
  final String? priceListName;
  final String? paymentTerm;
  final String? address;
  final String? city;
  final String? phone;
  final String? email;
  final DeliverySchedule? deliverySchedule;

  String get subtitle => [branchName ?? branch, city].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');
}

class Product {
  const Product({
    required this.sku,
    required this.name,
    required this.price,
    required this.unit,
    required this.stock,
    required this.taxRate,
    required this.category,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    sku: json['sku'] as String,
    name: json['name'] as String,
    price: (json['price'] as num).toDouble(),
    unit: json['unit'] as String?,
    stock: (json['stock'] as num).toDouble(),
    taxRate: (json['tax_rate'] as num).toDouble(),
    category: json['category'] as String?,
  );

  final String sku;
  final String name;
  final double price;
  final String? unit;
  final double stock;
  final double taxRate;
  final String? category;

  /// Igual que la web: en cortes, CERDO es su categoría y todo lo demás va a Res.
  bool get isPork => category?.toUpperCase() == 'CERDO';
}

class TodayOrder {
  const TodayOrder({required this.id, required this.number, required this.total, this.createdAt});

  factory TodayOrder.fromJson(Map<String, dynamic> json) => TodayOrder(
    id: json['id'] as String,
    number: json['number'] as String,
    total: (json['total'] as num).toDouble(),
    createdAt: json['created_at'] == null ? null : DateTime.parse(json['created_at'] as String).toLocal(),
  );

  final String id;
  final String number;
  final double total;
  final DateTime? createdAt;
}

class ClientLocation {
  const ClientLocation({
    required this.direccion,
    required this.barrio,
    required this.ciudad,
    this.referencia,
    this.departamento,
    this.telefono,
  });

  static ClientLocation? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return ClientLocation(
      direccion: json['direccion'] as String? ?? '',
      barrio: json['barrio'] as String? ?? '',
      ciudad: json['ciudad'] as String? ?? '',
      referencia: json['referencia'] as String?,
      departamento: json['departamento'] as String?,
      telefono: json['telefono'] as String?,
    );
  }

  final String direccion;
  final String barrio;
  final String ciudad;
  final String? referencia;
  final String? departamento;
  final String? telefono;

  Map<String, dynamic> toJson() => {
    'direccion': direccion,
    'barrio': barrio,
    'ciudad': ciudad,
    'referencia': ?referencia,
    'departamento': ?departamento,
    'telefono': ?telefono,
  };
}

class OrderDraft {
  const OrderDraft({
    required this.customerId,
    required this.deliveryDate,
    required this.deliveryType,
    required this.items,
    required this.idempotencyKey,
    this.schedule,
    this.notes,
    this.logisticsNote,
    this.linkedOrderId,
  });

  final String customerId;
  final DateTime deliveryDate;
  final String deliveryType;
  final Map<String, int> items;
  final String idempotencyKey;
  final DeliverySchedule? schedule;
  final String? notes;
  final String? logisticsNote;
  final String? linkedOrderId;
}

class OrderResult {
  const OrderResult({
    required this.id,
    required this.number,
    required this.secondNumber,
    required this.status,
    required this.total,
    required this.syncError,
  });

  factory OrderResult.fromJson(Map<String, dynamic> json) => OrderResult(
    id: json['id'] as String?,
    number: json['number'] as String?,
    secondNumber: json['second_number'] as String?,
    status: json['status'] as String? ?? '',
    total: (json['total'] as num?)?.toDouble() ?? 0,
    syncError: json['sync_error'] as String?,
  );

  final String? id;
  final String? number;
  final String? secondNumber;
  final String status;
  final double total;
  final String? syncError;
}
