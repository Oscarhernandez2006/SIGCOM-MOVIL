class PortfolioSummary {
  const PortfolioSummary({
    required this.total,
    required this.overdue,
    required this.current,
    required this.maxDaysOverdue,
    required this.documentsCount,
    required this.creditLimit,
    required this.aging,
    required this.asOf,
  });

  factory PortfolioSummary.fromJson(Map<String, dynamic> json) {
    final aging = json['aging'] as Map<String, dynamic>? ?? const {};
    return PortfolioSummary(
      total: (json['total'] as num).toDouble(),
      overdue: (json['overdue'] as num).toDouble(),
      current: (json['current'] as num).toDouble(),
      maxDaysOverdue: (json['max_days_overdue'] as num).toInt(),
      documentsCount: (json['documents_count'] as num).toInt(),
      creditLimit: (json['credit_limit'] as num?)?.toDouble(),
      aging: {for (final key in agingLabels.keys) key: (aging[key] as num?)?.toDouble() ?? 0},
      asOf: DateTime.parse(json['as_of'] as String),
    );
  }

  /// Rangos de antigüedad, iguales al PDF de cartera de la web.
  static const agingLabels = {
    'current': 'Corriente',
    'd1_30': '1 a 30 días',
    'd31_60': '31 a 60 días',
    'd61_90': '61 a 90 días',
    'd90_plus': 'Más de 90 días',
  };

  final double total;
  final double overdue;
  final double current;
  final int maxDaysOverdue;
  final int documentsCount;
  final double? creditLimit;
  final Map<String, double> aging;
  final DateTime asOf;

  bool get hasOverdue => overdue > 0;
}

class PortfolioClient {
  const PortfolioClient({
    required this.nit,
    required this.name,
    required this.branches,
    this.phone,
    this.email,
    this.city,
  });

  factory PortfolioClient.fromJson(Map<String, dynamic> json) => PortfolioClient(
    nit: json['nit'] as String,
    name: json['name'] as String,
    branches: (json['branches'] as num).toInt(),
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    city: json['city'] as String?,
  );

  final String nit;
  final String name;
  final int branches;
  final String? phone;
  final String? email;
  final String? city;
}

class PortfolioDocument {
  const PortfolioDocument({
    required this.number,
    required this.type,
    required this.branch,
    required this.date,
    required this.dueDate,
    required this.daysOverdue,
    required this.balance,
  });

  factory PortfolioDocument.fromJson(Map<String, dynamic> json) => PortfolioDocument(
    number: json['number'] as String,
    type: json['type'] as String? ?? '',
    branch: json['branch'] as String? ?? '001',
    date: json['date'] == null ? null : DateTime.parse(json['date'] as String),
    dueDate: json['due_date'] == null ? null : DateTime.parse(json['due_date'] as String),
    daysOverdue: (json['days_overdue'] as num).toInt(),
    balance: (json['balance'] as num).toDouble(),
  );

  final String number;
  final String type;
  final String branch;
  final DateTime? date;
  final DateTime? dueDate;
  final int daysOverdue;
  final double balance;

  bool get overdue => daysOverdue > 0 && balance > 0;
}

class PortfolioBranch {
  const PortfolioBranch({required this.code, this.name, this.address, this.city});

  factory PortfolioBranch.fromJson(Map<String, dynamic> json) => PortfolioBranch(
    code: json['code'] as String? ?? '001',
    name: json['name'] as String?,
    address: json['address'] as String?,
    city: json['city'] as String?,
  );

  final String code;
  final String? name;
  final String? address;
  final String? city;
}

class PortfolioDetail {
  const PortfolioDetail({
    required this.nit,
    required this.name,
    required this.paymentTerm,
    required this.emails,
    required this.phones,
    required this.branches,
    required this.summary,
    required this.documents,
  });

  factory PortfolioDetail.fromJson(Map<String, dynamic> json) {
    final client = json['client'] as Map<String, dynamic>;
    return PortfolioDetail(
      nit: client['nit'] as String,
      name: client['name'] as String,
      paymentTerm: client['payment_term'] as String?,
      emails: (client['emails'] as List<dynamic>).cast<String>(),
      phones: (client['phones'] as List<dynamic>).cast<String>(),
      branches: (client['branches'] as List<dynamic>)
          .map((e) => PortfolioBranch.fromJson(e as Map<String, dynamic>))
          .toList(),
      summary: PortfolioSummary.fromJson(json['summary'] as Map<String, dynamic>),
      documents: (json['documents'] as List<dynamic>)
          .map((e) => PortfolioDocument.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String nit;
  final String name;
  final String? paymentTerm;
  final List<String> emails;
  final List<String> phones;
  final List<PortfolioBranch> branches;
  final PortfolioSummary summary;
  final List<PortfolioDocument> documents;

  String branchName(String code) {
    for (final b in branches) {
      if (b.code == code) return b.name?.trim().isNotEmpty == true ? '${b.code} · ${b.name}' : code;
    }
    return code;
  }
}
