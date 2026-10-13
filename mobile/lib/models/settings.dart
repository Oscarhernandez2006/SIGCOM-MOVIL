DateTime? _date(Object? value) => value is String ? DateTime.parse(value).toLocal() : null;

class OrderScheduleSetting {
  const OrderScheduleSetting({
    required this.enabled,
    required this.open,
    required this.close,
    required this.isOpen,
    required this.updatedAt,
  });

  factory OrderScheduleSetting.fromJson(Map<String, dynamic> json) => OrderScheduleSetting(
    enabled: json['enabled'] as bool,
    open: json['open'] as String,
    close: json['close'] as String,
    isOpen: json['is_open'] as bool? ?? true,
    updatedAt: _date(json['updated_at']),
  );

  final bool enabled;

  /// Horas "HH:mm" en hora Colombia.
  final String open;
  final String close;
  final bool isOpen;
  final DateTime? updatedAt;
}

const userRoles = {
  'seller': 'Vendedor',
  'admin': 'Administrador',
  'cartera': 'Cartera',
  'alistador': 'Alistador',
  'facturacion': 'Facturación',
};

class UserCompanyAccess {
  const UserCompanyAccess({required this.id, required this.name, required this.sellerCode, required this.permissions});

  factory UserCompanyAccess.fromJson(Map<String, dynamic> json) => UserCompanyAccess(
    id: json['id'] as String,
    name: json['name'] as String,
    sellerCode: json['siesa_seller_code'] as String?,
    permissions: (json['permissions'] as List<dynamic>? ?? const []).cast<String>(),
  );

  final String id;
  final String name;
  final String? sellerCode;

  /// Vacío = módulos predeterminados del rol.
  final List<String> permissions;
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.documentId,
    required this.email,
    required this.name,
    required this.role,
    required this.active,
    required this.clientBudget,
    required this.mustChangePassword,
    required this.passwordChangedAt,
    required this.createdAt,
    required this.companies,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    id: json['id'] as String,
    documentId: json['document_id'] as String,
    email: json['email'] as String?,
    name: json['name'] as String,
    role: json['role'] as String,
    active: json['active'] as bool,
    clientBudget: json['client_budget'] as bool? ?? false,
    mustChangePassword: json['must_change_password'] as bool? ?? false,
    passwordChangedAt: _date(json['password_changed_at']),
    createdAt: _date(json['created_at']),
    companies: (json['companies'] as List<dynamic>? ?? const [])
        .map((e) => UserCompanyAccess.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String documentId;
  final String? email;
  final String name;
  final String role;
  final bool active;
  final bool clientBudget;
  final bool mustChangePassword;
  final DateTime? passwordChangedAt;
  final DateTime? createdAt;
  final List<UserCompanyAccess> companies;

  String get roleLabel => userRoles[role] ?? role;
}

class AdminUsersResult {
  const AdminUsersResult({required this.users, required this.companies});

  factory AdminUsersResult.fromJson(Map<String, dynamic> json) => AdminUsersResult(
    users: (json['users'] as List<dynamic>).map((e) => AdminUser.fromJson(e as Map<String, dynamic>)).toList(),
    companies: [for (final c in json['companies'] as List<dynamic>) (id: c['id'] as String, name: c['name'] as String)],
  );

  final List<AdminUser> users;

  /// Compañías que se pueden asignar.
  final List<({String id, String name})> companies;
}

typedef PermissionModule = ({String key, String label});

/// Módulos asignables por compañía, iguales a modules.ts de la web.
const permissionGroups = <({String title, List<PermissionModule> modules})>[
  (
    title: 'Operativo · Toma de pedidos',
    modules: [
      (key: '/', label: 'Dashboard comercial'),
      (key: '/pedidos', label: 'Pedidos'),
      (key: '/pedidos/canales', label: 'Pedidos · Canales'),
      (key: '/pedidos/subproductos', label: 'Pedidos · Subproductos'),
      (key: '/cotizaciones', label: 'Cotizaciones'),
      (key: '/clientes', label: 'Cartera de clientes'),
      (key: '/disponibilidad', label: 'Disponibilidad'),
    ],
  ),
  (
    title: 'Administrativo',
    modules: [
      (key: '/admin', label: 'Dashboard'),
      (key: '/admin/negocios-nacionales', label: 'Dashboard Negocios Nacionales'),
      (key: '/admin/inventario', label: 'Inventario'),
      (key: '/admin/pedidos', label: 'Administración de pedidos'),
      (key: '/admin/reportes', label: 'Reportes'),
      (key: '/admin/descargar-pedidos', label: 'Descargar pedidos · Cortes'),
      (key: '/admin/descargar-pedidos-subproductos-cerdo', label: 'Descargar subproductos · Cerdo'),
      (key: '/admin/descargar-pedidos-subproductos-res', label: 'Descargar subproductos · Res'),
      (key: '/admin/despacho-drivin-tat', label: 'Despacho · Drivin TAT Facturas'),
      (key: '/admin/canales-control', label: 'Canales · Control'),
      (key: '/admin/canales-cartera', label: 'Canales · Cartera'),
      (key: '/admin/canales-despacho', label: 'Canales · Despacho'),
      (key: '/admin/informe-bajas', label: 'Informe de bajas'),
      (key: '/admin/informe-devoluciones', label: 'Informe de devoluciones'),
      (key: '/admin/listas-precios', label: 'Listas de precios'),
      (key: '/admin/productos-estrella', label: 'Productos estrella'),
      (key: '/admin/clientes', label: 'Clientes'),
      (key: '/admin/presupuestos', label: 'Presupuestos'),
      (key: '/admin/rentabilidad', label: 'Rentabilidad · Costos'),
      (key: '/admin/cartera', label: 'Aprobación de cartera'),
      (key: '/admin/controlador-subproductos', label: 'Controlador subproductos'),
      (key: '/admin/horario-pedidos', label: 'Horario de pedidos'),
      (key: '/admin/api', label: 'API'),
      (key: '/admin/usuarios', label: 'Usuarios'),
    ],
  ),
];
